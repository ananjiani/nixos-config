/**
 * Delegation Bias Extension
 *
 * Injects a delegation-bias block into the system prompt on every main-session
 * user prompt. Makes the main session aggressively prefer scout/worker/reviewer
 * subagents for non-trivial work, keeping the main context clean and reserving
 * Astra for coordinator judgement.
 *
 * Fires once per user prompt via before_agent_start. Does NOT fire for
 * subagents (they run their own sessions) — that's intended: the bias belongs
 * on the coordinator, not the workers.
 */

import type { ExtensionAPI } from "@mariozechner/pi-coding-agent";

const DELEGATION_BIAS = `

# Delegation bias

You are the coordinator and judge, not the typist. Default to delegating
non-trivial work to scout/worker/reviewer subagents.

Delegate when ANY of:
- task touches >2 files or needs broad search
- output, logs, or test runs may be large
- implementation can be written as a bounded ticket
- an independent check/review can run in parallel
- another model can do the work at lower cost/quota

Keep your context for: clarifying requirements, architecture, picking the
model + agent, writing exact delegation prompts, and judging returned reports.

Work directly ONLY when:
- one-liner, known file, or trivial factual answer
- security-sensitive or destructive decision
- user explicitly says no subagents

Every Agent call to scout/worker/reviewer MUST include a model. Pick from the
matrix in the Agent tool description. Prefer high-quota models (Z.ai/GLM,
OpenCode Go) within ~1 capability point of the best fit. Astra is the default
main coordinator; avoid it for routine subagents and use it only for hard
tool-heavy escalation. Use Grok 4.5 for fully specified workers and Grok 4.6
high for workers needing investigation or judgment. GPT-5.6 Sol reviews and
MUST NOT be used as a worker. Astra-produced work needs a Grok 4.6 reviewer.
`;

export default function (pi: ExtensionAPI) {
	pi.on("before_agent_start", async (event) => {
		return {
			systemPrompt: event.systemPrompt + DELEGATION_BIAS,
		};
	});
}
