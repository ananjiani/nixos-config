/**
 * Auto Mode — toggle for autonomous operation.
 *
 * When active:
 * - Inject "you are operating autonomously" into system prompt
 * - confirm-destructive blocks dangerous commands silently (no prompt)
 * - Compaction runs on cheap model (custom-compaction.ts)
 *
 * Toggle: /mode auto, Ctrl+Alt+A, --auto CLI flag
 */

import type { ExtensionAPI } from "@earendil-works/pi-coding-agent";
import { Key } from "@earendil-works/pi-tui";
import { autoModeRef } from "./auto-mode-shared.js";

export default function (pi: ExtensionAPI) {
	pi.registerFlag("auto", {
		description: "Start in auto mode (autonomous operation)",
		type: "boolean",
		default: false,
	});

	function updateStatus(ctx: { ui: { setStatus: (id: string, val: string | undefined) => void; notify: (msg: string) => void; theme: { fg: (style: string, text: string) => string } } }): void {
		if (autoModeRef.enabled) {
			ctx.ui.setStatus("auto-mode", ctx.ui.theme.fg("green", "▶ auto"));
		} else {
			ctx.ui.setStatus("auto-mode", undefined);
		}
	}

	function toggle(ctx: { ui: { notify: (msg: string) => void; setStatus: (id: string, val: string | undefined) => void; theme: { fg: (style: string, text: string) => string } } }): void {
		autoModeRef.enabled = !autoModeRef.enabled;
		ctx.ui.notify(autoModeRef.enabled ? "Auto mode ON — autonomous, destructive blocked" : "Auto mode OFF");
		updateStatus(ctx);
		pi.appendEntry("auto-mode", { enabled: autoModeRef.enabled });
	}

	pi.registerCommand("mode", {
		description: "Toggle auto mode",
		handler: async (_args, ctx) => toggle(ctx),
	});

	pi.registerShortcut(Key.ctrlAlt("a"), {
		description: "Toggle auto mode",
		handler: async (ctx) => toggle(ctx),
	});

	// Inject autonomous framing
	pi.on("before_agent_start", async () => {
		if (!autoModeRef.enabled) return;

		return {
			message: {
				customType: "auto-mode-context",
				content: `[AUTO MODE ACTIVE]
You are operating autonomously. Work independently — explore, make decisions, implement changes.

Guidelines:
- Read files to understand context before making changes
- Use bash commands safely for research and execution
- Prefer surgical edits over rewrites
- Run tests or type checks after changes when applicable
- Use /compact instructions to pin context when you hit the limit
- If stuck or uncertain, ask the user

Destructive system operations (rm -rf, system rebuilds, infra changes, force pushes, sops decrypt) are blocked by guardrail — don't attempt them.`,
				display: false,
			},
		};
	});

	// Restore state on session start
	pi.on("session_start", async (_event, ctx) => {
		if (pi.getFlag("auto") === true) {
			autoModeRef.enabled = true;
		}

		const entries = ctx.sessionManager.getEntries();
		const prev = entries
			.filter((e: any) => e.type === "custom" && e.customType === "auto-mode")
			.pop() as { data?: { enabled: boolean } } | undefined;
		if (prev?.data) {
			autoModeRef.enabled = prev.data.enabled;
		}

		updateStatus(ctx);
	});
}
