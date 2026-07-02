/**
 * Custom Compaction — delegate summarization to a cheap model.
 *
 * Hooks session_before_compact and routes the summary call to
 * deepseek-v4-flash (opencode-go) with fallback to glm-5.2 (zai)
 * when opencode usage is exhausted. Falls back to default compaction
 * only when both fail.
 */

import { complete } from "@earendil-works/pi-ai/compat";
import type { Api, ExtensionAPI, Model } from "@earendil-works/pi-coding-agent";
import { convertToLlm, serializeConversation } from "@earendil-works/pi-coding-agent";

type SummaryResult = { text: string; modelName: string } | null;

async function tryCompactionModel(
	provider: string,
	modelId: string,
	conversationText: string,
	previousSummary: string | undefined,
	signal: AbortSignal | undefined,
	ctx: {
		modelRegistry: { find: (p: string, m: string) => Model<Api> | undefined; getApiKeyAndHeaders: (m: Model<Api>) => Promise<any> };
		ui: { notify: (msg: string, level?: string) => void };
	},
): Promise<SummaryResult> {
	const model = ctx.modelRegistry.find(provider, modelId);
	if (!model) return null;

	const auth = await ctx.modelRegistry.getApiKeyAndHeaders(model);
	if (!auth.ok || !auth.apiKey) {
		ctx.ui.notify(`Compaction: ${modelId} not available, trying fallback`, "info");
		return null;
	}

	const prevCtx = previousSummary ? `\n\nPrevious session summary:\n${previousSummary}` : "";

	const summaryMessages = [
		{
			role: "user" as const,
			content: [
				{
					type: "text" as const,
					text: `Summarize this conversation for continuation. Capture:
- Goals and objectives
- Key decisions and rationale
- Code/file changes and technical details
- Current state of ongoing work
- Blockers and open questions
- Next steps

Thorough but concise — this replaces the full history.${prevCtx}

<conversation>
${conversationText}
</conversation>`,
				},
			],
			timestamp: Date.now(),
		},
	];

	try {
		const response = await complete(model, { messages: summaryMessages }, {
			apiKey: auth.apiKey,
			headers: auth.headers,
			env: auth.env,
			maxTokens: 8192,
			signal,
		});

		const text = response.content
			.filter((c): c is { type: "text"; text: string } => c.type === "text")
			.map((c) => c.text)
			.join("\n");

		if (!text.trim()) return null;
		return { text, modelName: modelId };
	} catch {
		return null;
	}
}

export default function (pi: ExtensionAPI) {
	pi.on("session_before_compact", async (event, ctx) => {
		const { preparation, signal } = event;
		const { messagesToSummarize, turnPrefixMessages, tokensBefore, firstKeptEntryId, previousSummary } = preparation;

		const allMessages = [...messagesToSummarize, ...turnPrefixMessages];
		const conversationText = serializeConversation(convertToLlm(allMessages));

		// Try cheapest first, then fallback, then default compaction
		const result = await tryCompactionModel("opencode-go", "deepseek-v4-flash", conversationText, previousSummary, signal, ctx)
			?? await tryCompactionModel("zai", "glm-5.2", conversationText, previousSummary, signal, ctx);

		if (!result) return; // both failed → default compaction

		ctx.ui.notify(`Compacted ${tokensBefore.toLocaleString()} tokens via ${result.modelName}`, "info");

		return {
			compaction: { summary: result.text, firstKeptEntryId, tokensBefore },
		};
	});
}
