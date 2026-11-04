/**
 * llamacpp-discover — refresh the local llama.cpp router's models after pi starts.
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
 * When the router is unreachable the models.json definitions stay in place, so an
 * offline box behaves exactly as before. models.json is still rewritten by
 * `llamacpp-sync` for opencode and as the offline fallback; this extension only makes
 * pi stop needing a sync run after a router change.
 */

import { existsSync, readFileSync } from "node:fs";
import { join } from "node:path";
import type { ExtensionAPI } from "@earendil-works/pi-coding-agent";
import { getAgentDir } from "@earendil-works/pi-coding-agent";

const ROUTERS = [{ provider: "llamacpp", baseUrl: "http://127.0.0.1:7070/v1" }];

const FETCH_TIMEOUT_MS = 3000;
const DEFAULT_CONTEXT = 131072;
const DEFAULT_MAX_TOKENS = 16384;
const PI_HIDDEN = /^gemma-4-/i;
const REASONING_HINT = /(qwen3|deepseek|glm-[45]|gpt-oss|ministral|mistral|kimi|reasoning|think)/i;
const KEPT_TUNING = ["thinkingLevelMap", "compat", "cost", "samplingParams", "inputLimits"] as const;
const ZERO_COST = { input: 0, output: 0, cacheRead: 0, cacheWrite: 0 };

type ModelDef = Record<string, unknown> & { id: string };

interface LiveModel {
	id: string;
	name?: string;
	status?: { args?: string[] };
	architecture?: { input_modalities?: string[]; output_modalities?: string[] };
}

function readStaticModels(provider: string): ModelDef[] {
	const path = join(getAgentDir(), "models.json");
	if (!existsSync(path)) return [];
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

async function fetchLive(baseUrl: string, signal: AbortSignal): Promise<LiveModel[]> {
	const response = await fetch(`${baseUrl.replace(/\/$/, "")}/models`, {
		headers: { Accept: "application/json" },
		signal: AbortSignal.any([signal, AbortSignal.timeout(FETCH_TIMEOUT_MS)]),
	});
	if (!response.ok) throw new Error(`HTTP ${response.status}`);
	const payload = (await response.json()) as { data?: unknown };
	if (!Array.isArray(payload.data)) throw new Error("response has no data[] array");
	return payload.data.filter((m): m is LiveModel => !!m && typeof m.id === "string");
}

function discoverModels(fallback: ModelDef[], live: LiveModel[]): ModelDef[] {
	const existing = new Map(fallback.map((m) => [m.id, m]));
	return live
		.filter((m) => isChat(m) && !PI_HIDDEN.test(m.id))
		.map((m) => buildModel(m, existing.get(m.id)));
}

export default function (pi: ExtensionAPI) {
	const register = (provider: string, baseUrl: string, models: ModelDef[]) =>
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

	const refresh = async (signal: AbortSignal): Promise<string[]> => {
		const notes: string[] = [];
		await Promise.all(
			routers.map(async ({ provider, baseUrl, fallback }) => {
				try {
					const live = await fetchLive(baseUrl, signal);
					const models = discoverModels(fallback, live);
					if (!models.length) throw new Error("no chat models");
					register(provider, baseUrl, models);
					notes.push(`${provider}: ${models.length} models from ${baseUrl}`);
				} catch (err) {
					// router down: the models.json defs registered at load time stay in place
					notes.push(`${provider}: ${baseUrl} unreachable (${(err as Error).message}); keeping models.json`);
				}
			}),
		);
		return notes;
	};

	// Background, after the session is up; never awaited by pi.
	pi.on("session_start", (_e, ctx) => {
		void refresh(new AbortController().signal).then((notes) => {
			const ids = ctx.modelRegistry.getAvailable().filter((m) => m.provider === "llamacpp").map((m) => m.id);
			require("node:fs").appendFileSync("/tmp/claude-1000/-home-olivier-dotfiles/c28f6eca-412d-4a11-81be-0bd2f29f2b28/scratchpad/trace.log", JSON.stringify({ notes, ids }) + "
");
		});
	});

	pi.registerCommand("llamacpp-refresh", {
		description: "Re-read the local llama.cpp router's model list now",
		handler: async (_args, ctx) => {
			for (const note of await refresh(new AbortController().signal)) ctx.ui.notify(note, "info");
		},
	});
}
