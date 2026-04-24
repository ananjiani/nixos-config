/**
 * Plan Mode Extension
 *
 * File-based planning mode.
 * - Ideation: prompt-based read-only exploration
 * - Finalization: agent writes plan to .agents/plans/YYYY-MM-DD-<slug>.md
 */

import type { AgentMessage } from "@mariozechner/pi-agent-core";
import type { AssistantMessage, TextContent } from "@mariozechner/pi-ai";
import type { ExtensionAPI, ExtensionContext } from "@mariozechner/pi-coding-agent";
import { Key } from "@mariozechner/pi-tui";

function isAssistantMessage(m: AgentMessage): m is AssistantMessage {
	return m.role === "assistant" && Array.isArray(m.content);
}

function getTextContent(message: AssistantMessage): string {
	return message.content
		.filter((block): block is TextContent => block.type === "text")
		.map((block) => block.text)
		.join("\n");
}

function extractPlanPreview(text: string): { count: number; preview: string } {
	const lines = text.split("\n");
	const planLines: string[] = [];
	let inPlan = false;
	let count = 0;
	for (const line of lines) {
		if (/^\s*\*?\*?Plan:\*?\*?\s*$/i.test(line)) {
			inPlan = true;
			continue;
		}
		if (inPlan) {
			if (/^\s*(\d+)[.)]\s+/.test(line)) {
				count++;
				if (planLines.length < 5) {
					planLines.push(line.trim());
				}
			} else if (line.trim() === "" || /^\s*#{1,6}\s/.test(line)) {
				break;
			}
		}
	}
	return { count, preview: planLines.join("\n") };
}

export default function planModeExtension(pi: ExtensionAPI): void {
	let planModeEnabled = false;

	pi.registerFlag("plan", {
		description: "Start in plan mode (read-only exploration)",
		type: "boolean",
		default: false,
	});

	function updateStatus(ctx: ExtensionContext): void {
		if (planModeEnabled) {
			ctx.ui.setStatus("plan-mode", ctx.ui.theme.fg("warning", "⏸ plan"));
		} else {
			ctx.ui.setStatus("plan-mode", undefined);
		}
	}

	function togglePlanMode(ctx: ExtensionContext): void {
		planModeEnabled = !planModeEnabled;
		if (planModeEnabled) {
			ctx.ui.notify("Plan mode enabled - read-only exploration. Do not make edits.");
		} else {
			ctx.ui.notify("Plan mode disabled.");
		}
		updateStatus(ctx);
	}

	function persistState(): void {
		pi.appendEntry("plan-mode", { enabled: planModeEnabled });
	}

	pi.registerCommand("plan", {
		description: "Toggle plan mode (read-only exploration)",
		handler: async (_args, ctx) => togglePlanMode(ctx),
	});

	pi.registerShortcut(Key.ctrlAlt("p"), {
		description: "Toggle plan mode",
		handler: async (ctx) => togglePlanMode(ctx),
	});

	// Filter out stale plan mode context when not in plan mode
	pi.on("context", async (event) => {
		if (planModeEnabled) return;

		return {
			messages: event.messages.filter((m) => {
				const msg = m as AgentMessage & { customType?: string };
				if (msg.customType === "plan-mode-context") return false;
				if (msg.role !== "user") return true;

				const content = msg.content;
				if (typeof content === "string") {
					return !content.includes("[PLAN MODE ACTIVE]");
				}
				if (Array.isArray(content)) {
					return !content.some(
						(c) => c.type === "text" && (c as TextContent).text?.includes("[PLAN MODE ACTIVE]"),
					);
				}
				return true;
			}),
		};
	});

	// Notify when a plan file is written
	pi.on("tool_result", async (event, ctx) => {
		if (event.toolName !== "write") return;
		const path = (event.input.path as string) || "";
		if (path.includes(".agents/plans/") || path.includes("agents/plans/")) {
			ctx.ui.notify(`📋 Plan saved to ${path}`, "success");
		}
	});

	// Inject plan mode context before agent starts
	pi.on("before_agent_start", async () => {
		if (!planModeEnabled) return;

		return {
			message: {
				customType: "plan-mode-context",
				content: `[PLAN MODE ACTIVE]
You are in plan mode - a read-only exploration mode for safe code analysis.

You have full access to all tools for research and exploration, but you MUST NOT:
- Edit any existing files
- Create any new files
- Run destructive commands (rm, mv, git operations that modify history, etc.)

Focus on understanding the codebase, gathering information, and asking clarifying questions.
Use the questionnaire tool at decision points when multiple valid approaches exist or requirements are ambiguous.
Use bash freely for research (grep, find, npm/pip/nix queries, curl, git log/status, etc.).

Create a detailed numbered plan under a "Plan:" header:

Plan:
1. First step description
2. Second step description
...

Do NOT attempt to make changes - just describe what you would do.`,
				display: false,
			},
		};
	});

	// Handle plan finalization
	pi.on("agent_end", async (event, ctx) => {
		if (!planModeEnabled || !ctx.hasUI) return;

		// Extract plan preview from last assistant message
		const lastAssistant = [...event.messages].reverse().find(isAssistantMessage);
		if (!lastAssistant) return;

		const text = getTextContent(lastAssistant);
		const { count, preview } = extractPlanPreview(text);
		if (count === 0) return;

		let displayText = `**Plan: ${count} step${count > 1 ? "s" : ""} found**\n\n${preview}`;
		if (count > 5) {
			displayText += `\n... and ${count - 5} more`;
		}

		pi.sendMessage(
			{ customType: "plan-preview", content: displayText, display: true },
			{ triggerTurn: false },
		);

		const choice = await ctx.ui.select("Plan finalized - what next?", [
			"Save plan to file",
			"Continue planning",
			"Discard",
		]);

		if (choice === "Save plan to file") {
			const today = new Date().toISOString().slice(0, 10);
			planModeEnabled = false;
			updateStatus(ctx);
			persistState();

			pi.sendMessage(
				{
					customType: "plan-save",
					content: `Write the plan you created above to \`.agents/plans/\` using the \`write\` tool. Name the file with today's date and a short descriptive slug, like \`${today}-<slug>.md\` (e.g. \`${today}-oauth-refactor.md\`). Format as markdown with \`[ ]\` checkboxes for each step.`,
					display: true,
				},
				{ triggerTurn: true },
			);
		} else if (choice === "Discard") {
			planModeEnabled = false;
			updateStatus(ctx);
			persistState();
		}
		// "Continue planning" - do nothing, plan mode stays active
	});

	// Restore state on session start/resume
	pi.on("session_start", async (_event, ctx) => {
		if (pi.getFlag("plan") === true) {
			planModeEnabled = true;
		}

		const entries = ctx.sessionManager.getEntries();
		const planModeEntry = entries
			.filter((e: { type: string; customType?: string }) => e.type === "custom" && e.customType === "plan-mode")
			.pop() as { data?: { enabled: boolean } } | undefined;

		if (planModeEntry?.data) {
			planModeEnabled = planModeEntry.data.enabled ?? planModeEnabled;
		}

		updateStatus(ctx);
	});
}
