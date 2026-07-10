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

	pi.registerCommand("save-plan", {
		description: "Save the current plan to file and exit plan mode",
		handler: async (_args, ctx) => {
			if (!planModeEnabled) {
				ctx.ui.notify("Plan mode is not active", "warning");
				return;
			}

			const today = new Date().toISOString().slice(0, 10);
			planModeEnabled = false;
			updateStatus(ctx);
			persistState();

			pi.sendMessage(
				{
					customType: "plan-save",
					content: `Write the plan from our conversation to \`.agents/plans/\` using the \`write\` tool. Name it \`${today}-<descriptive-slug>.md\`. Format as markdown with \`[ ]\` checkboxes for each step.`,
					display: true,
				},
				{ triggerTurn: true },
			);
		},
	});

	pi.registerCommand("create-issue", {
		description: "Create an issue on the current repo's forge and exit plan mode",
		handler: async (_args, ctx) => {
			if (!planModeEnabled) {
				ctx.ui.notify("Plan mode is not active", "warning");
				return;
			}

			planModeEnabled = false;
			updateStatus(ctx);
			persistState();

			pi.sendMessage(
				{
					customType: "plan-issue",
					content: `Create an issue from the plan in our conversation. First determine the target forge by checking \`git remote -v\` in the current directory.

- For **Gitea/Forgejo/Codeberg** remotes (e.g. codeberg.org, git.dimensiondoor.xyz): use \`tea issue create\` with the appropriate \`--repo\` and \`--login\` flags.
- For **GitHub** remotes: use \`gh issue create\`.

Use the full plan body as the description, formatted as markdown with \`[ ]\` checkboxes for each step. After creating it, report the issue URL back to the user.`,
					display: true,
				},
				{ triggerTurn: true },
			);
		},
	});

	pi.registerShortcut(Key.ctrlAlt("p"), {
		description: "Toggle plan mode",
		handler: async (ctx) => togglePlanMode(ctx),
	});

	// Neutralize stale plan mode context when not in plan mode.
	//
	// IMPORTANT: replace content in place, do NOT filter messages out.
	// pi-claude-bridge tracks a message-count cursor into its Claude Code
	// session; a context shorter than the cursor hits its "clean start for
	// shorter context" path (no --resume, priors dropped), so Claude loses
	// all history from before plan mode was toggled off.
	const STALE_STUB = "[stale plan-mode instructions removed — plan mode is off]";
	pi.on("context", async (event) => {
		if (planModeEnabled) return;

		return {
			messages: event.messages.map((m) => {
				const msg = m as AgentMessage & { customType?: string };
				const isPlanContext = msg.customType === "plan-mode-context";
				if (!isPlanContext && msg.role !== "user") return m;

				const content = msg.content;
				if (typeof content === "string") {
					if (isPlanContext || content.includes("[PLAN MODE ACTIVE]")) {
						return { ...msg, content: STALE_STUB };
					}
					return m;
				}
				if (Array.isArray(content)) {
					const hasMarker =
						isPlanContext ||
						content.some(
							(c) => c.type === "text" && (c as TextContent).text?.includes("[PLAN MODE ACTIVE]"),
						);
					if (!hasMarker) return m;
					return {
						...msg,
						content: content.map((c) =>
							c.type === "text" &&
							(isPlanContext || (c as TextContent).text?.includes("[PLAN MODE ACTIVE]"))
								? { ...c, text: STALE_STUB }
								: c,
						),
					};
				}
				return isPlanContext ? { ...msg, content: STALE_STUB } : m;
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

	// Hint when a plan is detected
	pi.on("agent_end", async (event, ctx) => {
		if (!planModeEnabled || !ctx.hasUI) return;

		const lastAssistant = [...event.messages].reverse().find(isAssistantMessage);
		if (!lastAssistant) return;

		const text = getTextContent(lastAssistant);
		const { count } = extractPlanPreview(text);
		if (count === 0) return;

		ctx.ui.notify(`Plan detected (${count} steps). Run /save-plan to save locally, /create-issue to create an issue on the current repo's forge, or Ctrl+Alt+P to toggle off.`);
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
