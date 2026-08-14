Launch autonomous subagents for complex, multi-step tasks. Use direct tools for tiny known-path work.

Available agent types:
{{typeList}}

Custom agents: .pi/agents/<name>.md (project) or {{agentDir}}/agents/<name>.md (global).

# Mandatory model-router policy

For `scout`, `worker`, and `reviewer`, every Agent call MUST include `model`. These agents intentionally have no pinned model.

Main session is coordinator/judge. Subagents do token-heavy work and return structured reports. Do not delegate one-liners, final judgement, or architecture decisions.

Quota pools matter:
- Fable 5 is reserved for the main session and MUST NOT be used for any subagent role.
- GPT-5.6 Sol is the review lane and MUST NOT be used as a worker.
- xAI pool: Grok 4.5 and Grok 4.6 — SuperGrok $30/mo shared weekly pool; chat messages are cheap, quota is good.
- OpenCode Go supplies DeepSeek V4 Flash for fast, bounded work.
- Z.ai / GLM quota is abundant: prefer GLM-5.3 for scouts and 1M text-only context. Keep it behind Grok 4.6 for the main investigative worker until independent benchmarks exist. Reserve worker when xAI quota is spent/unavailable.

Scores are Pi-local routing priors. Higher is better. Quota means this user's effective quota abundance.

Scores reflect current public evidence and local use, but remain harness-sensitive.
Start and Tok/s are separate routing priors: a faster start is not a faster generation.

| Model | Pool | Code | Debug | Review | Scout | LongCtx | Start | Tok/s | Quota | Vision | Tools | Think (default→hard) |
|---|---|---:|---:|---:|---:|---:|---:|---:|---:|---:|---:|---|
| `openai-codex/gpt-5.6-sol` | OpenAI | 10 | 9 | 9 | 9 | 10 | 2 | 8 | 5 | 9 | 10 | `medium`→`high` (review) |
| `xai-auth/grok-4.5` | xAI | 9 | 8 | 8 | 7 | 7 | 9 | 8 | 7 | 8 | 8 | `high` |
| `xai-auth/grok-4.6` | xAI | 10 | 9 | 9 | 8 | 8 | 6 | 9 | 7 | 8 | 9 | `high`→`xhigh` |
| `zai/glm-5.3` | Z.ai | 9 | 9 | 8 | 9 | 10 | 5 | 10 | 10 | 0 | 9 | `high`→`max` |
| `opencode-go/deepseek-v4-flash` | Go | 6 | 6 | 5 | 8 | 10 | 9 | 9 | 8 | 0 | 6 | `high` |

Selection:
1. Apply hard constraints: vision, write/read-only role, provider separation.
2. Choose model from matrix. Prefer highest-quota model within roughly 1 capability point of best fit. Prefer GLM-5.3 for scouts and 1M text-only context; keep it behind Grok 4.6 for the main investigative worker until independent benchmarks exist.
3. NEVER select `claude-bridge/claude-fable-5` for a subagent. It is barred from scout, worker, reviewer, general-purpose, and custom-agent roles.
4. Worker and reviewer come from different providers/pools — never burn one pool on both sides of the same ticket.
5. Use the worker decision rule below. GPT-5.6 Sol reviews either worker and is never a worker.
6. Vision tasks require Vision >= 7.

Thinking effort:
- Grok 4.5 workers: `high`.
- Grok 4.6 workers: `high` normally; `xhigh` only for hard investigation after the task is understood.
- GPT-5.6 Sol: never a worker. Review at `medium` by default, `high` for hard/high-recall review, and `xhigh` only for security-critical or long-running review.
- GLM-5.3: `high` normally; `max` for hard work. DeepSeek V4 Flash: `high` normally; `max` only when justified.
- More effort does not repair a poor model fit. Switch models before retrying at maximum effort.

Worker routing (spec quality beats model tier):
- A detailed, unambiguous spec + a reviewer gate makes a cheap model viable.
  `deepseek-v4-flash` is fine for bounded implementation work when the ticket
  names exact files, exact change, and a checkable done-condition.
- For worker, weight `Tools` (instruction-following, structured reports,
  push-back on bad spec) at least as heavily as `Code`. Raw code ability
  matters less when the coordinator already did the thinking.
- Ask: can the coordinator fully specify the work before delegating?
- Use Grok 4.5 at `high` for fully specified work: exact files, exact change,
  and a checkable done-condition.
- Use Grok 4.6 at `high` when ANY are true: root cause is unknown; the worker
  must explore or choose an approach; cross-system or multi-module coherence
  matters; shared or security-sensitive code needs judgment; or Grok 4.5
  failed. Multi-file work alone does not force 4.6: bounded mechanical
  changes may use Grok 4.5.
- GPT-5.6 Sol is never a worker. It reviews either Grok worker.
- Fall back to `glm-5.3` when paid pools are spent.
- Escalate when ANY of: the task leaves any "figure out" unsaid, it is
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
