import { readFile } from "node:fs/promises";
import { homedir } from "node:os";
import { join } from "node:path";
import type { ExtensionAPI } from "@earendil-works/pi-coding-agent";

export default async function (pi: ExtensionAPI) {
	const instructions = await readFile(
		join(
			homedir(),
			".dotfiles/modules/home/dev/agent-prompts/attention-control.md",
		),
		"utf8",
	);
	let enabled = true;

	pi.on("session_start", (_event, ctx) => {
		enabled = true;
		for (const entry of ctx.sessionManager.getEntries()) {
			if (
				entry.type === "custom" &&
				entry.customType === "attention-control-enabled"
			) {
				enabled = (entry.data as { enabled?: boolean })?.enabled === true;
			}
		}
		ctx.ui.setStatus("attention-control", enabled ? "ATTN" : undefined);
	});

	pi.registerCommand("attention-control", {
		description: "Toggle Attention Control, or use on/off",
		handler: async (args, ctx) => {
			const arg = args.trim().toLowerCase();
			if (!arg) enabled = !enabled;
			else if (arg === "on") enabled = true;
			else if (arg === "off" || arg === "stop") enabled = false;
			else {
				ctx.ui.notify(
					'Use "/attention-control", "/attention-control on", or "/attention-control off".',
					"error",
				);
				return;
			}

			pi.appendEntry("attention-control-enabled", { enabled });
			ctx.ui.setStatus("attention-control", enabled ? "ATTN" : undefined);
			ctx.ui.notify(`Attention Control ${enabled ? "on" : "off"}.`, "info");
		},
	});

	pi.on("before_agent_start", (event) => {
		if (!enabled) return;
		return { systemPrompt: `${event.systemPrompt}\n\n${instructions}` };
	});
}
