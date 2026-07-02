Launch autonomous subagents for complex, multi-step tasks. Use direct tools for tiny known-path work.

Available agent types:
{{compactTypeList}}

Custom agents: .pi/agents/<name>.md (project) or {{agentDir}}/agents/<name>.md (global).

# Mandatory model-router policy

For `scout`, `worker`, and `reviewer`, every Agent call MUST include `model`. These agents intentionally have no pinned model.

Main session is coordinator/judge. Subagents do token-heavy work and return structured reports. Do not delegate one-liners, final judgement, or architecture decisions.

Quota pools matter:
- Claude pool is shared: Fable, Opus, Sonnet. Preserve for main judgement and hard escalations.
- OpenCode Go pool is shared: Kimi, DeepSeek, MiniMax.
- Z.ai / GLM quota is abundant for this user; prefer it when fit is close.

Scores are Pi-local routing priors. Higher is better. Quota means this user's effective quota abundance.

| Model | Pool | Code | Debug | Review | Scout | LongCtx | Speed | Quota | Vision | Tools |
|---|---|---:|---:|---:|---:|---:|---:|---:|---:|---:|
| `claude-bridge/claude-fable-5` | Claude | 10 | 10 | 10 | 9 | 10 | 3 | 1 | 10 | 10 |
| `openai-codex/gpt-5.5` | OpenAI | 10 | 9 | 9 | 8 | 7 | 6 | 6 | 8 | 9 |
| `zai/glm-5.2` | Z.ai | 8 | 8 | 8 | 8 | 10 | 6 | 10 | 0 | 7 |
| `opencode-go/kimi-k2.7-code` | Go | 9 | 7 | 7 | 6 | 7 | 7 | 7 | 7 | 8 |
| `opencode-go/deepseek-v4-pro` | Go | 8 | 9 | 8 | 7 | 10 | 5 | 7 | 0 | 7 |
| `opencode-go/deepseek-v4-flash` | Go | 6 | 6 | 5 | 8 | 10 | 9 | 8 | 0 | 6 |
| `opencode-go/minimax-m3` | Go | 7 | 6 | 7 | 8 | 8 | 8 | 7 | 8 | 7 |

Selection:
1. Apply hard constraints: vision, write/read-only role, provider separation.
2. Choose model from matrix. Prefer highest-quota model within roughly 1 capability point of best fit.
3. Avoid Claude subagents unless stakes require it or cheaper attempts failed twice.
4. Prefer different providers/pools for worker vs reviewer.
5. Vision tasks require Vision >= 7.

Worker routing (spec quality beats model tier):
- A detailed, unambiguous spec + a reviewer gate makes a cheap model viable.
  `deepseek-v4-flash` is fine for bounded implementation work when the ticket
  names exact files, exact change, and a checkable done-condition.
- For worker, weight `Tools` (instruction-following, structured reports,
  push-back on bad spec) at least as heavily as `Code`. Raw code ability
  matters less when Fable already did the thinking.
- Escalate to `gpt-5.5` first (strongest non-Claude), then `glm-5.2` when
  gpt-5.5 quota is spent; otherwise `kimi-k2.7-code` or `deepseek-v4-pro`.
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
