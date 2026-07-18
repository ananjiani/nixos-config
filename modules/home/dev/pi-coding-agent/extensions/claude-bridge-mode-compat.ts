import type { ExtensionAPI } from "@earendil-works/pi-coding-agent";

const PROVIDER = "claude-bridge";
const MARKERS = [
	"PONYTAIL MODE ACTIVE",
	"IMPORTANT: You are in CAVEMAN MODE",
	"# Token efficiency\nRespond like smart caveman",
];
const DELIMITER = "\n\n---[pi mode instructions]---\n";

let instructions: string | undefined;

export default function (pi: ExtensionAPI) {
	// Claude Bridge forwards AGENTS.md and skills, but not system-prompt changes
	// made by extensions. Capture Ponytail/Caveman's exact active rules.
	pi.on("before_agent_start", (event, ctx) => {
		if (ctx.model?.provider !== PROVIDER) {
			instructions = undefined;
			return;
		}

		const starts = MARKERS.map((marker) => event.systemPrompt.indexOf(marker)).filter(
			(index) => index >= 0,
		);
		instructions = starts.length ? event.systemPrompt.slice(Math.min(...starts)) : undefined;
	});

	// Context is a disposable deep copy. Altering its latest user message keeps
	// Pi's session history and Claude Bridge's message-count cursor unchanged.
	pi.on("context", (event, ctx) => {
		if (!instructions || ctx.model?.provider !== PROVIDER) return;

		for (let i = event.messages.length - 1; i >= 0; i--) {
			const message = event.messages[i];
			if (message.role !== "user") continue;

			if (typeof message.content === "string") {
				message.content += DELIMITER + instructions;
			} else {
				message.content = [
					...message.content,
					{ type: "text", text: DELIMITER + instructions },
				];
			}
			return;
		}
	});
}
