import { readFile } from "node:fs/promises";
import { homedir } from "node:os";
import { join } from "node:path";
import type { ExtensionAPI } from "@earendil-works/pi-coding-agent";

export default async function (pi: ExtensionAPI) {
	const instructions = await readFile(
		join(homedir(), ".pi/agent/skills/i-have-adhd/SKILL.md"),
		"utf8",
	);
	let enabled = false;

	pi.on("session_start", (_event, ctx) => {
		for (const entry of ctx.sessionManager.getEntries()) {
			if (entry.type === "custom" && entry.customType === "i-have-adhd-enabled") {
				enabled = (entry.data as { enabled?: boolean })?.enabled === true;
			}
		}
		ctx.ui.setStatus("i-have-adhd", enabled ? "ADHD" : undefined);
	});

	pi.registerCommand("adhd", {
		description: "Toggle ADHD-friendly output, or use on/off",
		handler: async (args, ctx) => {
			const arg = args.trim().toLowerCase();
			if (!arg) enabled = !enabled;
			else if (arg === "on") enabled = true;
			else if (arg === "off" || arg === "stop") enabled = false;
			else {
				ctx.ui.notify('Use "/adhd", "/adhd on", or "/adhd off".', "error");
				return;
			}

			pi.appendEntry("i-have-adhd-enabled", { enabled });
			ctx.ui.setStatus("i-have-adhd", enabled ? "ADHD" : undefined);
			ctx.ui.notify(`ADHD output ${enabled ? "on" : "off"}.`, "info");
		},
	});

	pi.on("before_agent_start", (event) => {
		if (!enabled) return;
		return { systemPrompt: `${event.systemPrompt}\n\n${instructions}` };
	});
}
