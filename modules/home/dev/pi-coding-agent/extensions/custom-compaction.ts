/**
 * Custom Compaction — delegate summarization to a cheap model.
 *
 * Hooks session_before_compact and routes the summary call to
 * deepseek-v4-flash (opencode-go) instead of the primary model.
 * Saves quota — compaction costs ~$0 instead of Fable/Opus output
 * token prices.
 */

import { complete } from "@earendil-works/pi-ai/compat";
import type { ExtensionAPI } from "@earendil-works/pi-coding-agent";
import { convertToLlm, serializeConversation } from "@earendil-works/pi-coding-agent";

export default function (pi: ExtensionAPI) {
	pi.on("session_before_compact", async (event, ctx) => {
		const { preparation, signal } = event;
		const { messagesToSummarize, turnPrefixMessages, tokensBefore, firstKeptEntryId, previousSummary } = preparation;

		const model = ctx.modelRegistry.find("opencode-go", "deepseek-v4-flash");
		if (!model) return; // fall back to default compaction

		const auth = await ctx.modelRegistry.getApiKeyAndHeaders(model);
		if (!auth.ok || !auth.apiKey) return;

		const allMessages = [...messagesToSummarize, ...turnPrefixMessages];
		const conversationText = serializeConversation(convertToLlm(allMessages));
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

			const summary = response.content
				.filter((c): c is { type: "text"; text: string } => c.type === "text")
				.map((c) => c.text)
				.join("\n");

			if (!summary.trim()) return;

			ctx.ui.notify(`Compacted ${tokensBefore.toLocaleString()} tokens via deepseek-v4-flash`, "info");

			return {
				compaction: { summary, firstKeptEntryId, tokensBefore },
			};
		} catch {
			// fall back to default compaction on error
			return;
		}
	});
}
