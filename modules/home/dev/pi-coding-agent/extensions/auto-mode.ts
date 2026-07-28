/**
 * Auto Mode — autonomous operation toggle.
 *
 * Three levels. Set via `/auto safe|danger|off` or cycle with Ctrl+Alt+A.
 * `--auto` CLI flag forces safe (internal mode `auto`).
 * - off:     normal interactive mode
 * - auto:    autonomous; destructive ops BLOCKED silently by
 *            confirm-destructive.ts  (slash arg: `safe`)
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
const ARGS = ["safe", "danger", "off"] as const;
const ARG_TO_MODE: Record<(typeof ARGS)[number], Mode> = {
	safe: "auto",
	danger: "danger",
	off: "off",
};

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

	function setMode(ctx: any, mode: Mode): void {
		ref.mode = mode;
		ctx.ui.notify(
			mode === "off" ? "Auto mode OFF"
				: mode === "auto" ? "Auto mode: autonomous, destructive BLOCKED"
				: "⚠ Auto mode: DANGER — all commands allowed",
			mode === "danger" ? "error" : "info",
		);
		render(ctx);
		pi.appendEntry("auto-mode", { mode });
	}

	function cycle(ctx: any): void {
		setMode(ctx, ORDER[(ORDER.indexOf(ref.mode) + 1) % ORDER.length]);
	}

	pi.registerCommand("auto", {
		description: "Set auto mode: /auto safe | danger | off",
		getArgumentCompletions: (prefix) => {
			const filtered = ARGS.filter((a) => a.startsWith(prefix.toLowerCase()));
			return filtered.length > 0 ? filtered.map((a) => ({ value: a, label: a })) : null;
		},
		handler: async (args, ctx) => {
			const arg = args.trim().toLowerCase();
			if (!(ARGS as readonly string[]).includes(arg)) {
				ctx.ui.notify("Usage: /auto safe | danger | off", "error");
				return;
			}
			setMode(ctx, ARG_TO_MODE[arg as keyof typeof ARG_TO_MODE]);
		},
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
