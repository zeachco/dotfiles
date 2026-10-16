/**
 * compaction-thinking — cap the reasoning effort of pi's compaction summaries.
 *
 * WHY: pi hands the SESSION's thinking level to the summarization call
 * (createSummarizationOptions: `options.reasoning = thinkingLevel`), and caps the
 * summary at 0.8 × compaction.reserveTokens output tokens. qwen3.8 sessions run at
 * xhigh, so the summary spends that whole budget reasoning about a ~30k-token
 * transcript and the summary itself gets cut off:
 *   "Auto-compaction failed: Summarization failed: generation hit the token cap
 *    and the summary is incomplete"
 * Measured 2026-10-16 (r3000 session, light router journal): 29739-token prompt,
 * then exactly 13107 generated tokens (= floor(0.8 × 16384)) over 40 min at 5.4 tok/s.
 * Two of the three summaries that succeeded that day ended at 13055 and 14464.
 *
 * WHAT: on before_provider_request, when the request is a summarization (its system
 * prompt is pi's SUMMARIZATION_SYSTEM_PROMPT -- also used for turn-prefix and branch
 * summaries), lower `reasoning_effort` to SUMMARY_MAX_EFFORT if it is above it. It
 * never raises, and never touches any other request. Only the OpenAI-style
 * `reasoning_effort` field is handled (llama.cpp and OpenRouter both take it);
 * Anthropic-style `thinking.budget_tokens` is left alone.
 *
 * WHY medium, not high: the qwen3.8 chat template (GET /props?model=qwen3.8) folds
 * `high` into `xhigh` and accepts only xhigh / medium / low, so "high" is literally
 * no cap on this model. medium is the first level that shortens the thinking.
 *
 * Reaches a running pi only after a restart (extensions load at startup).
 */
import type { ExtensionAPI } from "@earendil-works/pi-coding-agent";

export const SUMMARY_MAX_EFFORT = "medium";

const SUMMARIZATION_PROMPT_PREFIX = "You are a context summarization assistant.";

// Effort scale, lowest first. "none" is what llama-server treats as "thinking off";
// anything not listed ranks -1 and is never changed.
const EFFORT_ORDER = ["none", "minimal", "low", "medium", "high", "xhigh", "max"];

function rank(effort: unknown): number {
	return typeof effort === "string" ? EFFORT_ORDER.indexOf(effort) : -1;
}

function textOf(content: unknown): string {
	if (typeof content === "string") return content;
	if (Array.isArray(content)) {
		return content.map((part) => (typeof part?.text === "string" ? part.text : "")).join("");
	}
	return "";
}

/** The system prompt of a request body, whichever wire format it uses. */
function systemText(payload: any): string {
	const first = payload?.messages?.[0];
	if (first && (first.role === "system" || first.role === "developer")) return textOf(first.content);
	return textOf(payload?.system ?? payload?.instructions);
}

/**
 * Returns the payload to send instead, or undefined to leave it untouched.
 * Pure, so it can be tested without pi.
 */
export function clampSummaryEffort(payload: any, maxEffort: string = SUMMARY_MAX_EFFORT): any | undefined {
	if (!systemText(payload).startsWith(SUMMARIZATION_PROMPT_PREFIX)) return undefined;
	if (rank(payload?.reasoning_effort) <= rank(maxEffort)) return undefined;
	return { ...payload, reasoning_effort: maxEffort };
}

export default function compactionThinkingExtension(pi: ExtensionAPI) {
	pi.on("before_provider_request", async (event: any, ctx: any) => {
		const next = clampSummaryEffort(event.payload);
		if (next === undefined) return undefined;
		try {
			ctx?.ui?.notify?.(
				`compaction summary: reasoning ${event.payload.reasoning_effort} → ${SUMMARY_MAX_EFFORT}`,
				"info",
			);
		} catch {
			// a UI without notify must not cost us the clamp
		}
		return next;
	});
}
