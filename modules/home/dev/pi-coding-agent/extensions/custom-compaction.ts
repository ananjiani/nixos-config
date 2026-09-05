/**
 * Custom Compaction — delegate summarization to a cheap model.
 *
 * Hooks session_before_compact and routes the summary call to
 * deepseek-v4-flash (opencode-go) with fallback to glm-5.3 (zai)
 * when the first model fails. Falls back to default compaction
 * only when both fail. Abort does not start the next model.
 */

import { uuidv7, type Usage } from "@earendil-works/pi-ai";
import type { ExtensionAPI, ExtensionContext } from "@earendil-works/pi-coding-agent";
import { convertToLlm, serializeConversation } from "@earendil-works/pi-coding-agent";

type SummaryOk = { text: string; usage: Usage; modelName: string };
type SummaryAttempt = SummaryOk | "aborted" | null;

function maxOutputTokens(model: { maxTokens?: number }): number {
	const cap = model.maxTokens;
	if (typeof cap === "number" && cap > 0) return Math.min(8192, cap);
	return 8192;
}

function summaryText(content: Array<{ type: string; text?: string }>): string {
	return content
		.filter((c): c is { type: "text"; text: string } => c.type === "text")
		.map((c) => c.text)
		.join("\n");
}

function buildPrompt(
	conversationText: string,
	previousSummary: string | undefined,
	customInstructions: string | undefined,
): string {
	const prev = previousSummary ? `\n\nPrevious session summary:\n${previousSummary}` : "";
	const extra = customInstructions ? `\n\nAdditional focus:\n${customInstructions}` : "";
	return `Summarize the older conversation below so work can continue. Recent turns stay in context after this summary; do not treat this as a replacement for the full history.

Capture:
- Goals and objectives
- User constraints and preferences
- Key decisions and rationale
- Code/file changes with exact paths, function names, and error messages
- Progress: distinguish completed work from planned or in-progress work
- Blockers and open questions
- Next steps

Thorough but concise.${prev}${extra}

<conversation>
${conversationText}
</conversation>`;
}

async function tryCompactionModel(
	provider: string,
	modelId: string,
	prompt: string,
	signal: AbortSignal,
	ctx: ExtensionContext,
	reasoningEffort?: "low",
): Promise<SummaryAttempt> {
	if (signal.aborted) return "aborted";

	const model = ctx.modelRegistry.find(provider, modelId);
	if (!model) return null;

	const summaryMessages = [
		{
			role: "user" as const,
			content: [{ type: "text" as const, text: prompt }],
			timestamp: Date.now(),
		},
	];

	try {
		const response = await ctx.modelRegistry.complete(
			model,
			{ messages: summaryMessages },
			{
				maxTokens: maxOutputTokens(model),
				signal,
				cacheRetention: "none",
				sessionId: uuidv7(),
				...(reasoningEffort ? { reasoningEffort } : {}),
			},
		);

		if (signal.aborted || response.stopReason === "aborted") return "aborted";
		if (response.stopReason !== "stop") return null;
		if (response.content.some((block: { type: string }) => block.type === "toolCall")) return null;

		const text = summaryText(response.content);
		if (!text.trim()) return null;
		return { text, usage: response.usage, modelName: modelId };
	} catch (error) {
		if (signal.aborted || (error instanceof Error && error.name === "AbortError")) return "aborted";
		return null;
	}
}

export default function (pi: ExtensionAPI) {
	pi.on("session_before_compact", async (event, ctx) => {
		const { preparation, customInstructions, signal } = event;
		const { messagesToSummarize, turnPrefixMessages, tokensBefore, firstKeptEntryId, previousSummary } =
			preparation;

		const conversationText = serializeConversation(
			convertToLlm([...messagesToSummarize, ...turnPrefixMessages]),
		);
		const prompt = buildPrompt(conversationText, previousSummary, customInstructions);

		const attempts: Array<{ provider: string; modelId: string; reasoningEffort?: "low" }> = [
			{ provider: "opencode-go", modelId: "deepseek-v4-flash" },
			{ provider: "zai", modelId: "glm-5.3", reasoningEffort: "low" },
		];

		for (const attempt of attempts) {
			const result = await tryCompactionModel(
				attempt.provider,
				attempt.modelId,
				prompt,
				signal,
				ctx,
				attempt.reasoningEffort,
			);
			if (result === "aborted") return { cancel: true };
			if (!result) continue;

			ctx.ui.notify(`Compacted ${tokensBefore.toLocaleString()} tokens via ${result.modelName}`, "info");
			return {
				compaction: {
					summary: result.text,
					firstKeptEntryId,
					tokensBefore,
					usage: result.usage,
				},
			};
		}
	});
}
