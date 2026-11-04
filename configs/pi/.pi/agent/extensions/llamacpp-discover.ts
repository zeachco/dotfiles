/**
 * llamacpp-discover — refresh the local llama.cpp routers' models after pi starts.
 *
 * Boot never waits on the router: the `llamacpp` provider is registered from the
 * models.json definitions at load time, and once the session is up a background fetch
 * of GET http://127.0.0.1:7070/v1/models re-registers the provider with what the router
 * serves now (pi applies a post-startup registerProvider immediately, no /reload).
 * The same refresh runs on every session_start (startup, /new, /reload, resume, fork)
 * and through `/llamacpp-refresh`. Mirrors the rules of bin/llamacpp-sync:
 *
 *   - decision/classifier models (output_modalities contains "decisions") are dropped
 *     — pi's built-in llama.cpp provider lists them as classifiers, not chat models
 *   - the light tier's gemma-4 models stay hidden (see PI_HIDDEN in llamacpp-sync)
 *   - contextWindow is the per-slot context derived from the preset args
 *     (ctx-size / parallel, or the full pool under --kv-unified, capped by
 *     --kv-unified-per-slot), never the pool size
 *   - per-model tuning already in models.json (name, reasoning, thinkingLevelMap,
 *     compat, cost, samplingParams, inputLimits, maxTokens) is preserved
 *
 * Selecting a llamacpp model that the router reports `unloaded` (the heavy tier runs
 * --no-models-autoload, so a request would fail with 400 "model is not loaded") loads
 * it the way `los-load` does — POST /models/load, then poll until `loaded` — but only
 * when it fits: its footprint (the figure `los` measured when it was last resident, or
 * its weights on disk) is checked against free GPU memory (amdgpu GTT via sysfs). When
 * it does not fit, or the check is impossible, pi warns and prints the `los-load`
 * command to run by hand instead of OOMing the box under someone else's model.
 *
 * When nothing listens on a router's port (that tier is not installed on this box) the
 * provider is emptied so /model does not offer dead models; a transient failure
 * (timeout, bad response) keeps the models.json definitions in place. models.json is still rewritten by
 * `llamacpp-sync` for opencode and as the offline fallback; this extension only makes
 * pi stop needing a sync run after a router change.
 */

import { existsSync, readFileSync, readdirSync, statSync } from "node:fs";
import { homedir } from "node:os";
import { basename, dirname, join } from "node:path";
import type { ExtensionAPI } from "@earendil-works/pi-coding-agent";
import { getAgentDir } from "@earendil-works/pi-coding-agent";

const ROUTERS = [
	{ provider: "llamacpp", baseUrl: "http://127.0.0.1:7070/v1" },
	{ provider: "llamacpp-heavy", baseUrl: "http://127.0.0.1:7072/v1" },
];
/** The router's own endpoints (POST /models/load, …) live beside /v1, not under it. */
const routerRoot = (baseUrl: string) => baseUrl.replace(/\/v1\/?$/, "");
const isHeavyRouter = (baseUrl: string) => ROUTERS.some((r) => r.provider === "llamacpp-heavy" && r.baseUrl === baseUrl);

const FETCH_TIMEOUT_MS = 3000;
const LOAD_POST_TIMEOUT_MS = 30_000;
const LOAD_POLL_MS = 3000;
// why: right after POST /models/load the router can still report "unloaded" for a
// few polls before it flips to "loading"; trusting that early verdict would call
// every load a failure. ~9 s of grace at LOAD_POLL_MS.
const LOAD_GRACE_POLLS = 3;
const LOAD_TIMEOUT_MS = 10 * 60 * 1000;
/** Written by the `los` menu whenever it sees a model resident: id<TAB>bytes pinned as GTT. */
const MEASURED_TSV = join(process.env.XDG_CACHE_HOME || join(homedir(), ".cache"), "los-menu", "resident.tsv");
const DEFAULT_CONTEXT = 131_072;
const DEFAULT_MAX_TOKENS = 16_384;
const PI_HIDDEN = /^gemma-4-/i;
const REASONING_HINT = /(qwen3|deepseek|glm-[45]|gpt-oss|ministral|mistral|kimi|reasoning|think)/i;
const KEPT_TUNING = ["thinkingLevelMap", "compat", "cost", "samplingParams", "inputLimits"] as const;
const ZERO_COST = { input: 0, output: 0, cacheRead: 0, cacheWrite: 0 };

type ModelDef = Record<string, unknown> & { id: string };

interface LiveModel {
	id: string;
	name?: string;
	status?: { value?: string; args?: string[] };
	architecture?: { input_modalities?: string[]; output_modalities?: string[] };
}

function readStaticModels(provider: string): ModelDef[] {
	const path = join(getAgentDir(), "models.json");
	try {
		const parsed = JSON.parse(readFileSync(path, "utf-8"));
		const models = parsed?.providers?.[provider]?.models;
		return Array.isArray(models) ? models.filter((m) => m && typeof m.id === "string") : [];
	} catch {
		return [];
	}
}

function argValue(args: string[], flag: string): string | undefined {
	const i = args.indexOf(flag);
	return i >= 0 ? args[i + 1] : undefined;
}

function asInt(value: string | undefined): number | undefined {
	return value !== undefined && /^\d+$/.test(value) ? Number(value) : undefined;
}

/** The context one conversation actually gets — see per_slot_context in bin/llamacpp-sync. */
function perSlotContext(args: string[]): number | undefined {
	let ctx = asInt(argValue(args, "--ctx-size"));
	if (ctx === undefined) return undefined;
	const cap = asInt(argValue(args, "--kv-unified-per-slot"));
	if (cap) ctx = Math.min(ctx, cap);
	if (args.includes("--kv-unified") || args.includes("-kvu")) return ctx;
	const np = asInt(argValue(args, "--parallel")) ?? asInt(argValue(args, "-np"));
	return np ? Math.floor(ctx / np) : ctx;
}

function isChat(live: LiveModel): boolean {
	return !(live.architecture?.output_modalities ?? []).includes("decisions");
}

function buildModel(live: LiveModel, existing: ModelDef | undefined): ModelDef {
	const ex = existing ?? {};
	const hasImage = (live.architecture?.input_modalities ?? []).includes("image");
	const model: ModelDef = {
		id: live.id,
		name: ex.name ?? live.name ?? live.id,
		contextWindow: perSlotContext(live.status?.args ?? []) ?? ex.contextWindow ?? DEFAULT_CONTEXT,
		maxTokens: ex.maxTokens ?? DEFAULT_MAX_TOKENS,
		input: hasImage ? ["text", "image"] : ["text"],
		reasoning: "reasoning" in ex ? ex.reasoning : REASONING_HINT.test(live.id),
	};
	for (const key of KEPT_TUNING) {
		if (ex[key] != null) model[key] = ex[key];
	}
	model.cost ??= ZERO_COST;
	return model;
}

async function fetchLive(baseUrl: string): Promise<LiveModel[]> {
	const response = await fetch(`${routerRoot(baseUrl)}/v1/models`, {
		headers: { Accept: "application/json" },
		signal: AbortSignal.timeout(FETCH_TIMEOUT_MS),
	});
	if (!response.ok) throw new Error(`HTTP ${response.status}`);
	const payload = (await response.json()) as { data?: unknown };
	if (!Array.isArray(payload.data)) throw new Error("response has no data[] array");
	return payload.data.filter((m): m is LiveModel => !!m && typeof m.id === "string");
}

/** True when the TCP connect itself was refused — the service is simply not running here. */
function isRefused(err: unknown): boolean {
	for (let e: any = err; e; e = e.cause) {
		if (e.code === "ECONNREFUSED" || /ECONNREFUSED/.test(String(e.message))) return true;
	}
	return false;
}

function discoverModels(fallback: ModelDef[], live: LiveModel[]): ModelDef[] {
	const existing = new Map(fallback.map((m) => [m.id, m]));
	return live
		.filter((m) => isChat(m) && !PI_HIDDEN.test(m.id))
		.map((m) => buildModel(m, existing.get(m.id)));
}

// ---- loading on select ------------------------------------------------------------

const GIB = 1 << 30;
const gib = (n: number) => `${(n / GIB).toFixed(1)} GiB`;

/** Free GPU memory, or undefined when it cannot be read (not amdgpu, not Linux). */
function freeGpuBytes(): number | undefined {
	const drm = "/sys/class/drm";
	if (!existsSync(drm)) return undefined;
	for (const card of readdirSync(drm)) {
		const total = join(drm, card, "device", "mem_info_gtt_total");
		try {
			const t = Number(readFileSync(total, "utf-8"));
			const u = Number(readFileSync(total.replace("_total", "_used"), "utf-8"));
			if (t > 0) return t - u;
		} catch {}
	}
	return undefined;
}

/** Weights on disk; sharded models (-00001-of-0000N.gguf) are summed like los does. */
function weightsBytes(path: string | undefined): number {
	if (!path || !existsSync(path)) return 0;
	const name = basename(path);
	if (!name.includes("-of-")) return statSync(path).size;
	const stem = name.split("-").slice(0, -3).join("-");
	return readdirSync(dirname(path))
		.filter((f) => f.startsWith(`${stem}-`) && f.includes("-of-") && f.endsWith(".gguf"))
		.reduce((sum, f) => sum + statSync(join(dirname(path), f)).size, 0);
}

function measuredBytes(id: string): number {
	if (!existsSync(MEASURED_TSV)) return 0;
	for (const line of readFileSync(MEASURED_TSV, "utf-8").split("\n")) {
		const [k, v] = line.split("\t");
		if (k === id) return Number(v) || 0;
	}
	return 0;
}

/** Bytes the model will pin once loaded: the measured figure when it is credible, else weights. */
function footprint(live: LiveModel): { need: number; measured: boolean } {
	const weights = weightsBytes(argValue(live.status?.args ?? [], "--model"));
	const measured = measuredBytes(live.id);
	// A figure below the weights was taken while the model slept (weights released).
	return measured >= weights ? { need: measured, measured: true } : { need: weights, measured: false };
}

function loadCommand(baseUrl: string, id: string): string {
	// los-load targets the heavy router by default; any other router needs the override.
	return isHeavyRouter(baseUrl) ? `los-load ${id}` : `LOS_HEAVY_URL=${routerRoot(baseUrl)} los-load ${id}`;
}

async function routerStatus(baseUrl: string, id: string): Promise<LiveModel | undefined> {
	const live = await fetchLive(baseUrl);
	return live.find((m) => m.id === id);
}

type Notify = (message: string, level: "info" | "warning" | "error") => void;

/** Load `id` on its router if it is unloaded and fits in free GPU memory; otherwise warn. */
async function ensureLoaded(baseUrl: string, id: string, notify: Notify): Promise<void> {
	let live: LiveModel | undefined;
	try {
		live = await routerStatus(baseUrl, id);
	} catch (err) {
		notify(`${id}: cannot reach ${baseUrl} (${(err as Error).message})`, "warning");
		return;
	}
	const state = live?.status?.value;
	if (!live || state !== "unloaded") return; // loaded, sleeping (first request wakes it), loading…

	const { need, measured } = footprint(live);
	const free = freeGpuBytes();
	const cmd = loadCommand(baseUrl, id);
	if (free === undefined) {
		notify(`${id} is not loaded and free GPU memory cannot be read here. Load it by hand: ${cmd}`, "warning");
		return;
	}
	if (need > free) {
		notify(
			`${id} is not loaded and needs ~${gib(need)}${measured ? "" : " (weights only, more with KV)"} ` +
				`but only ${gib(free)} GPU memory is free. Free some (los → drain/unload) then run: ${cmd}`,
			"warning",
		);
		return;
	}

	notify(`Loading ${id} (~${gib(need)}, ${gib(free)} free)…`, "info");
	await requestLoad(baseUrl, id);
	await waitForLoaded(baseUrl, id, cmd, notify);
}

/** Ask the router to load `id`. The HTTP status is not the verdict; the poll is. */
async function requestLoad(baseUrl: string, id: string): Promise<void> {
	// why: the router answers non-2xx (or hangs past the timeout) for a model that is
	// already loading, and that load still completes — so the result is ignored and
	// waitForLoaded decides.
	try {
		await fetch(`${routerRoot(baseUrl)}/models/load`, {
			method: "POST",
			headers: { "content-type": "application/json" },
			body: JSON.stringify({ model: id }),
			signal: AbortSignal.timeout(LOAD_POST_TIMEOUT_MS),
		});
	} catch {}
}

/** Poll the router until `id` is loaded, failed, or LOAD_TIMEOUT_MS has passed; notify the outcome. */
async function waitForLoaded(baseUrl: string, id: string, cmd: string, notify: Notify): Promise<void> {
	const deadline = Date.now() + LOAD_TIMEOUT_MS;
	let polls = 0;
	while (Date.now() < deadline) {
		await new Promise((r) => setTimeout(r, LOAD_POLL_MS));
		polls++;
		const now = (await routerStatus(baseUrl, id).catch(() => undefined))?.status?.value;
		if (now === "loaded" || now === "sleeping") {
			notify(`${id} loaded`, "info");
			return;
		}
		if ((now === "failed" || now === "unloaded") && polls > LOAD_GRACE_POLLS) {
			notify(`${id} failed to load (status ${now}) — usually memory. Check the router log, or run: ${cmd}`, "error");
			return;
		}
	}
	notify(`${id}: timed out waiting for the load. Check with: ${cmd}`, "error");
}

type Router = (typeof ROUTERS)[number] & { fallback: ModelDef[] };
type Register = (provider: string, baseUrl: string, models: ModelDef[]) => void;

/** Re-register one provider from what its router serves now; returns a one-line note. */
async function refreshRouter({ provider, baseUrl, fallback }: Router, register: Register): Promise<string> {
	let live: LiveModel[];
	try {
		live = await fetchLive(baseUrl);
	} catch (err) {
		if (isRefused(err)) {
			// Nothing listens on that port: this box does not run the tier at all
			// (e.g. no heavy router), so do not offer models that cannot answer.
			register(provider, baseUrl, []);
			return `${provider}: no router on ${baseUrl}; provider emptied`;
		}
		// Transient (timeout, 5xx, bad JSON): keep what models.json says.
		return `${provider}: ${baseUrl} failed (${(err as Error).message}); keeping models.json`;
	}
	const models = discoverModels(fallback, live);
	if (!models.length) return `${provider}: ${baseUrl} failed (no chat models); keeping models.json`;
	register(provider, baseUrl, models);
	return `${provider}: ${models.length} models from ${baseUrl}`;
}

export default function (pi: ExtensionAPI) {
	const register: Register = (provider, baseUrl, models) =>
		pi.registerProvider(provider, {
			name: `${provider} (${baseUrl})`,
			baseUrl,
			apiKey: "llamacpp",
			api: "openai-completions",
			models,
		});

	const routers = ROUTERS.map((r) => ({ ...r, fallback: readStaticModels(r.provider) }));

	// Instant: the static list, so startup never waits on the router.
	for (const { provider, baseUrl, fallback } of routers) register(provider, baseUrl, fallback);

	const refresh = () => Promise.all(routers.map((r) => refreshRouter(r, register)));

	// Background, after the session is up; never awaited by pi.
	pi.on("session_start", () => {
		void refresh();
	});

	const routerOf = (provider: string) => routers.find((r) => r.provider === provider);

	pi.on("model_select", (event, ctx) => {
		const r = routerOf(event.model.provider);
		if (r) void ensureLoaded(r.baseUrl, event.model.id, (m, level) => ctx.ui.notify(m, level));
	});

	pi.registerCommand("llamacpp-load", {
		description: "Load the current llamacpp model on its router if it fits in GPU memory",
		handler: async (_args, ctx) => {
			const r = ctx.model ? routerOf(ctx.model.provider) : undefined;
			if (!ctx.model || !r) return ctx.ui.notify("Current model is not a local llamacpp model", "warning");
			await ensureLoaded(r.baseUrl, ctx.model.id, (m, level) => ctx.ui.notify(m, level));
		},
	});

	pi.registerCommand("llamacpp-refresh", {
		description: "Re-read the local llama.cpp router's model list now",
		handler: async (_args, ctx) => {
			for (const note of await refresh()) ctx.ui.notify(note, "info");
		},
	});
}
