/**
 * say — Kokoro TTS tool, offered only while Kokoro is already loaded.
 *
 * Lets the model speak a short, natural English summary of what it just did, through
 * ~/dotfiles/bin/say (Kokoro TTS + pw-play, fully local).
 *
 * The gate: Kokoro-82M is ~1 GiB of RAM and a few seconds of every core to load, on a box
 * whose one budget is RAM shared with the llama.cpp router. A summary is not worth that,
 * so nothing in this path ever loads the model:
 *
 *   - the tool is declared only while the daemon (bin/kokoro-serve, kokoro-tts.service)
 *     reports `loaded` — the model is resident because YOU loaded it (los-tts load, the
 *     `kokoro` row in `los`, or KOKORO_PRELOAD=1 on the unit)
 *   - when it is not loaded, the tool is withdrawn from the active set, so the model never
 *     sees it and never spends a call on it
 *   - execute() re-checks and refuses anyway, and runs bin/say with KOKORO_ALLOW_LOAD=0, so
 *     neither the daemon nor the in-process fallback can load the model for us
 *
 * State is re-probed on session_start and before every run (the socket answers in ~1 ms),
 * so loading Kokoro from `los` makes `say` show up on the next message without a /reload.
 * Removing it is safe; it is added back only if this extension was the one that took it
 * away, so a preset that deliberately left `say` out keeps it out.
 */

import { execFile } from "node:child_process";
import { createConnection } from "node:net";
import type { ExtensionAPI } from "@earendil-works/pi-coding-agent";
import { Type } from "typebox";

const SAY_BIN = `${process.env.HOME ?? "~"}/dotfiles/bin/say`;
const MAX_CHARS = 600;
const TOOL = "say";
const SOCKET =
	process.env.KOKORO_SOCKET ||
	`${process.env.XDG_RUNTIME_DIR || "/tmp"}/kokoro-tts.sock`;
/** Status probe timeout: a socket that does not answer is treated as no daemon. */
const PROBE_MS = 1000;
/** Two probes in the same breath (session_start then the first run) are one probe. */
const CACHE_MS = 5000;

const HOW_TO_LOAD = "load it with los-tts load (or the 'kokoro' row in the los menu)";

type TtsState = "loaded" | "unloaded" | "none";

/** Ask the resident daemon whether its model is resident. Never blocks for long. */
function kokoroState(): Promise<TtsState> {
	return new Promise((resolve) => {
		let sock: ReturnType<typeof createConnection>;
		try {
			sock = createConnection({ path: SOCKET });
		} catch {
			resolve("none");
			return;
		}
		let settled = false;
		const done = (state: TtsState) => {
			if (settled) return;
			settled = true;
			sock.destroy();
			resolve(state);
		};
		sock.setTimeout(PROBE_MS, () => done("none"));
		sock.on("error", () => done("none"));
		sock.on("connect", () => sock.write('{"op":"status"}\n'));
		let buf = "";
		sock.on("data", (chunk) => {
			buf += chunk.toString("utf8");
			const nl = buf.indexOf("\n");
			if (nl < 0) return;
			try {
				const reply = JSON.parse(buf.slice(0, nl)) as { ok?: boolean; loaded?: boolean };
				done(reply.ok ? (reply.loaded ? "loaded" : "unloaded") : "none");
			} catch {
				done("none");
			}
		});
	});
}

function speak(text: string, signal: AbortSignal): Promise<{ ok: boolean; output: string }> {
	return new Promise((resolve) => {
		const child = execFile(
			SAY_BIN,
			[text],
			{
				timeout: 180_000,
				maxBuffer: 10 * 1024 * 1024,
				windowsHide: true,
				// The tool's own rule, spelled out rather than inherited: whatever the user's
				// shell has exported, this path may not load the model.
				env: { ...process.env, KOKORO_ALLOW_LOAD: "0" },
			},
			(error, _stdout, stderr) => {
				if (!error) {
					resolve({ ok: true, output: "" });
				} else if ((error as NodeJS.ErrnoException & { killed?: boolean }).killed) {
					resolve({ ok: false, output: "say was cancelled" });
				} else {
					resolve({ ok: false, output: (stderr || error.message).trim() });
				}
			},
		);
		const abort = () => child.kill("SIGTERM");
		signal.addEventListener("abort", abort, { once: true });
		child.once("exit", () => signal.removeEventListener("abort", abort));
	});
}

export default function (pi: ExtensionAPI) {
	let state: TtsState = "none";
	let probedAt = 0;
	/** True while `say` is out of the active set because we took it out (unloaded kokoro). */
	let withheld = false;

	async function probe(force = false): Promise<TtsState> {
		if (!force && Date.now() - probedAt < CACHE_MS) return state;
		state = await kokoroState();
		probedAt = Date.now();
		return state;
	}

	/** Declare `say` iff kokoro is loaded; put back only what this function took away. */
	async function sync(force = false): Promise<TtsState> {
		const now = await probe(force);
		const active = pi.getActiveTools();
		if (now === "loaded") {
			if (withheld) {
				if (!active.includes(TOOL)) pi.setActiveTools([...active, TOOL]);
				withheld = false;
			}
		} else if (active.includes(TOOL)) {
			pi.setActiveTools(active.filter((name) => name !== TOOL));
			withheld = true;
		}
		return now;
	}

	// Only the two ui members mark() needs; pi's own context type is not importable here
	// (the extension runs from a bundled pi, with no type declarations on disk).
	type Ui = { setStatus(key: string, value: string | undefined): void; theme: { fg(color: string, text: string): string } };

	/** What the gate decided, for the footer: shown only when speech is armed. */
	function mark(ui: Ui) {
		ui.setStatus("say", state === "loaded" ? ui.theme.fg("dim", "say:ready") : undefined);
	}

	pi.on("session_start", async (_event, ctx) => {
		await sync(true);
		mark(ctx.ui);
	});

	// Fires once per run: picks up `los-tts load` (and los-drain) in a session that is
	// already open, without a /reload. Subagents load this extension too, so the probe
	// stays cheap and cached (CACHE_MS) unless something actually asks.
	pi.on("before_agent_start", async (_event, ctx) => {
		await sync();
		mark(ctx.ui);
	});

	pi.registerTool({
		name: TOOL,
		label: "Say",
		description: [
			"Speak a short summary of what you just did, out loud, in natural spoken English.",
			"Call this once after finishing a unit of work (a fix, a feature, a test run).",
			"Write for listening, not reading: one or two sentences, plain words, no markdown,",
			"no code identifiers, no file paths (say 'the fetch script', not '/home/.../fetch.sh').",
			"Example: \"Fixed the broken theme reload, and all 12 tests pass.\"",
		].join(" "),
		promptGuidelines: [
			"say speaks only while the local Kokoro TTS model is loaded; if it reports the model is not loaded, stop calling it and say nothing out loud.",
		],
		parameters: Type.Object({
			text: Type.String({
				description:
					"The summary to speak. Short natural English, 1-2 sentences, max 600 characters.",
			}),
		}),
		async execute(_id, params, signal) {
			const text = params.text.trim();
			if (!text) {
				return {
					content: [{ type: "text" as const, text: "say: empty text, nothing spoken." }],
					details: {},
				};
			}
			if (text.length > MAX_CHARS) {
				return {
					content: [
						{
							type: "text" as const,
							text: `say: text is ${text.length} characters; keep it under ${MAX_CHARS} and call again with a shorter summary.`,
						},
					],
					details: {},
				};
			}

			// The tool is only declared while loaded, but a drain can land between the
			// declaration and this call; never let the speak below load the model instead.
			if ((await sync(true)) !== "loaded") {
				return {
					content: [
						{
							type: "text" as const,
							text: `say: kokoro is not loaded, so nothing was spoken (it does not load itself). ${HOW_TO_LOAD}.`,
						},
					],
					details: {},
				};
			}

			const result = await speak(text, signal);
			return {
				content: [
					{
						type: "text" as const,
						text: result.ok ? `Spoken: "${text}"` : `say failed: ${result.output}`,
					},
				],
				details: {},
			};
		},
	});

	// Manual entry point for testing: /say <text>. Always available, so the message it
	// gives when kokoro is down is the answer to "why is my agent mute?".
	pi.registerCommand("say", {
		description: "Speak text with Kokoro TTS (only while the model is loaded)",
		handler: async (args, ctx) => {
			if (!args.trim()) {
				ctx.ui.notify("Usage: /say <text>", "warning");
				return;
			}
			if ((await sync(true)) !== "loaded") {
				ctx.ui.notify(`say: kokoro is not loaded, and it is not loaded here. ${HOW_TO_LOAD}`, "warning");
				return;
			}
			const result = await speak(args.trim(), new AbortController().signal);
			if (!result.ok) ctx.ui.notify(`say failed: ${result.output}`, "error");
		},
	});

}
