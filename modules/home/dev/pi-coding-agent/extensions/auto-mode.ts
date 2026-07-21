/**
 * Auto Mode — autonomous operation toggle.
 *
 * Three levels, cycled by /auto (Ctrl+Alt+A, --auto CLI flag forces safe):
 * - off:     normal interactive mode
 * - auto:    autonomous; destructive ops BLOCKED silently by
 *            confirm-destructive.ts
 * - danger:  fully autonomous; ALL commands allowed, no guardrail
 *
 * Shared global __autoModeRef.mode is read by confirm-destructive.ts.
 */

import type { ExtensionAPI } from "@earendil-works/pi-coding-agent";
import { Key } from "@earendil-works/pi-tui";

type Mode = "off" | "auto" | "danger";

(globalThis as any).__autoModeRef ??= { mode: "off" as Mode };
const ref = (globalThis as any).__autoModeRef as { mode: Mode };

const ORDER: Mode[] = ["off", "auto", "danger"];

const FRAMING: Record<Exclude<Mode, "off">, string> = {
	auto: `[AUTO MODE] Work autonomously without asking. Destructive ops are blocked; surface any required destructive action to the user.`,
	danger: `[AUTO MODE — DANGER] Work autonomously without asking. Destructive ops are authorized and unguarded; state intent before irreversible actions.`,
};

function render(ctx: any): void {
	const t = ctx.ui.theme;
	ctx.ui.setStatus(
		"auto-mode",
		ref.mode === "auto" ? t.fg("success", "▶ auto")
			: ref.mode === "danger" ? t.fg("error", "⚠ danger")
			: undefined,
	);
}

export default function (pi: ExtensionAPI) {
	pi.registerFlag("auto", {
		description: "Start in safe auto mode (autonomous, destructive blocked)",
		type: "boolean",
		default: false,
	});

	function cycle(ctx: any): void {
		ref.mode = ORDER[(ORDER.indexOf(ref.mode) + 1) % ORDER.length];
		ctx.ui.notify(
			ref.mode === "off" ? "Auto mode OFF"
				: ref.mode === "auto" ? "Auto mode: autonomous, destructive BLOCKED"
				: "⚠ Auto mode: DANGER — all commands allowed",
			ref.mode === "danger" ? "error" : "info",
		);
		render(ctx);
		pi.appendEntry("auto-mode", { mode: ref.mode });
	}

	pi.registerCommand("auto", {
		description: "Cycle auto mode: off → auto (safe) → danger (allow all) → off",
		handler: async (_args, ctx) => cycle(ctx),
	});

	pi.registerShortcut(Key.ctrlAlt("a"), {
		description: "Cycle auto mode (off → auto → danger)",
		handler: async (ctx) => cycle(ctx),
	});

	// Inject autonomous framing
	pi.on("before_agent_start", async () => {
		if (ref.mode === "off") return;
		return {
			message: {
				customType: "auto-mode-context",
				content: FRAMING[ref.mode],
				display: false,
			},
		};
	});

	// Restore state on session start. --auto flag forces safe; otherwise
	// replay the last mode from session history (covers /compact, reload).
	pi.on("session_start", async (_event, ctx) => {
		if (pi.getFlag("auto") === true) {
			ref.mode = "auto";
		} else {
			const prev = ctx.sessionManager
				.getEntries()
				.filter((e: any) => e.type === "custom" && e.customType === "auto-mode")
				.pop() as { data?: { mode?: Mode } } | undefined;
			// Back-compat: old entries stored { enabled: boolean }; those
			// lack .mode, so the truthiness guard falls through to "off".
			ref.mode = prev?.data?.mode ?? "off";
		}
		render(ctx);
	});
}
