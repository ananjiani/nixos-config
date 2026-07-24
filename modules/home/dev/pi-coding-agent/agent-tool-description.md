Launch autonomous subagents for complex, multi-step tasks. Use direct tools for tiny known-path work.

Available agent types:
{{typeList}}

Custom agents: .pi/agents/<name>.md (project) or {{agentDir}}/agents/<name>.md (global).

# Mandatory model-router policy

For `scout`, `worker`, and `reviewer`, every Agent call MUST include `model`. These agents intentionally have no pinned model.

Main session is coordinator/judge. Subagents do token-heavy work and return structured reports. Do not delegate one-liners, final judgement, or architecture decisions.

Quota pools matter:
- Fable 5 is reserved for the main session and MUST NOT be used for any subagent role. Claude's Opus 4.8 may serve as a worker or reviewer.
- xAI pool: Grok 4.5 — SuperGrok $30/mo shared weekly pool; chat messages are cheap, quota is good.
- OpenCode Go supplies DeepSeek V4 Flash for fast, bounded work.
- Z.ai / GLM quota is abundant but held in reserve: GLM-5.2 is NOT a worker choice while any other paid pool has quota — worker of last resort only. Scout/read-only summary work is fine.

Scores are Pi-local routing priors. Higher is better. Quota means this user's effective quota abundance.

| Model | Pool | Code | Debug | Review | Scout | LongCtx | Speed | Quota | Vision | Tools | Think (default→hard) |
|---|---|---:|---:|---:|---:|---:|---:|---:|---:|---:|---|
| `openai-codex/gpt-5.6-sol` | OpenAI | 10 | 9 | 9 | 9 | 10 | 6 | 5 | 9 | 10 | `low`→`high` |
| `claude-bridge/claude-opus-4-8` | Claude | 9 | 9 | 10 | 8 | 9 | 5 | 7 | 9 | 9 | `high`, never `max` |
| `xai-auth/grok-4.5` | xAI | 9 | 8 | 8 | 7 | 7 | 9 | 7 | 8 | 8 | `high` |
| `zai/glm-5.2` | Z.ai | 8 | 8 | 8 | 8 | 10 | 6 | 10 | 0 | 7 | `high` |
| `opencode-go/deepseek-v4-flash` | Go | 6 | 6 | 5 | 8 | 10 | 9 | 8 | 0 | 6 | `high` |

Selection:
1. Apply hard constraints: vision, write/read-only role, provider separation.
2. Choose model from matrix. Prefer highest-quota model within roughly 1 capability point of best fit — except GLM-5.2, which despite Quota 10 is a last-resort worker (see pool notes).
3. NEVER select `claude-bridge/claude-fable-5` for a subagent. It is barred from scout, worker, reviewer, general-purpose, and custom-agent roles.
4. Worker and reviewer come from different providers/pools — never burn one pool on both sides of the same ticket.
5. Prefer Grok for fast implementation, Sol low/medium for routine debug/analysis, and Sol high for hard debugging and agentic/terminal work. Opus is the Claude fallback lane, not a default route.
6. Vision tasks require Vision >= 7.

Thinking effort:
- Opus 4.8 (fallback lane): `high` default, `xhigh` for review; NEVER `max` — it scores below its own xhigh on hard engineering.
- Grok 4.5: `high` by default. Use `medium` only for latency-sensitive routine work and `low` only for simple lookup/tool use.
- GPT-5.6 Sol: `low` for routine debug/edit loops (best cost-per-intelligence; above prior-gen high); `medium` default; `high` for hard debugging or review; `xhigh` only for security-critical or long-running work. Terra: skip — Sol-low or Luna dominates.
- GLM-5.2 and DeepSeek V4 Flash: `high` normally; `xhigh` only when provider Max is justified.
- More effort does not repair a poor model fit. Switch models before retrying at maximum effort.

Worker routing (spec quality beats model tier):
- A detailed, unambiguous spec + a reviewer gate makes a cheap model viable.
  `deepseek-v4-flash` is fine for bounded implementation work when the ticket
  names exact files, exact change, and a checkable done-condition.
- For worker, weight `Tools` (instruction-following, structured reports,
  push-back on bad spec) at least as heavily as `Code`. Raw code ability
  matters less when the coordinator already did the thinking.
- Escalate to `grok-4.5` first for code-heavy tickets and `gpt-5.6-sol` (low/medium) for debug/analysis.
  Use Sol high for hard debugging and agentic/terminal work; use Opus for harder tickets when
  code efficiency and maintainability pay for the quota.
  Review is cross-pool: Opus reviews non-Claude workers; Sol medium-high reviews Claude workers;
  Sol high handles high-recall issue sweeps.
  Fall back to `glm-5.2` when paid pools are spent.
  Escalate when ANY of: the task leaves any "figure out" unsaid, it is
  debug-shaped, or flash failed twice. Debug/root-cause work never routes to
  flash.

Prompt each agent like a self-contained ticket:
- Context: larger task and why
- Task: exact work for this agent
- Files: known paths / where to start
- Constraints: what not to touch, style, no new deps, security constraints
- Done means: exact behavior or checks
- Report back: files changed + line ranges, commands run + output summary, risks/open questions

Notes:
- description: 3-5 words (shown in UI). Prompts must be self-contained — the agent has not seen this conversation.
- Parallel work: one message, multiple Agent calls, run_in_background: true on each. You are notified when background agents finish — never poll or sleep.
- The result is not shown to the user — summarize it for them. Verify an agent's claimed code changes before reporting work done.
- resume continues a previous agent by ID; steer_subagent messages a running one.
- isolation: "worktree" runs the agent in an isolated git worktree; changes land on a branch.
{{scheduleGuideline}}
