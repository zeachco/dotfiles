/**
 * say — Kokoro TTS tool.
 *
 * Lets the model speak a short, natural English summary of what it just did,
 * using ~/dotfiles/bin/say (Kokoro TTS + pw-play, fully local).
 */

import { execFile } from "node:child_process";
import type { ExtensionAPI } from "@earendil-works/pi-coding-agent";
import { Type } from "typebox";

const SAY_BIN = `${process.env.HOME ?? "~"}/dotfiles/bin/say`;
const MAX_CHARS = 600;

function speak(text: string, signal: AbortSignal): Promise<{ ok: boolean; output: string }> {
	return new Promise((resolve) => {
		const child = execFile(
			SAY_BIN,
			[text],
			{ timeout: 180_000, maxBuffer: 10 * 1024 * 1024, windowsHide: true },
			(error, _stdout, stderr) => {
				if (!error) {
					resolve({ ok: true, output: "" });
				} else if ((error as NodeJS.ErrnoException).killed) {
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
	pi.registerTool({
		name: "say",
		label: "Say",
		description: [
			"Speak a short summary of what you just did, out loud, in natural spoken English.",
			"Call this once after finishing a unit of work (a fix, a feature, a test run).",
			"Write for listening, not reading: one or two sentences, plain words, no markdown,",
			"no code identifiers, no file paths (say 'the fetch script', not '/home/.../fetch.sh').",
			"Example: \"Fixed the broken theme reload, and all 12 tests pass.\"",
		].join(" "),
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

	// Manual entry point for testing: /say <text>
	pi.registerCommand("say", {
		description: "Speak text with Kokoro TTS",
		handler: async (args, ctx) => {
			if (!args.trim()) {
				ctx.ui.notify("Usage: /say <text>", "warning");
				return;
			}
			const result = await speak(args.trim(), new AbortController().signal);
			if (!result.ok) ctx.ui.notify(`say failed: ${result.output}`, "error");
		},
	});
}
