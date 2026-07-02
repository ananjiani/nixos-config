---
name: model-router
description: Route Pi subagent work across scout, worker, and reviewer agents using the user's real model pools, quotas, speed, vision, and capability matrix. Use when delegating work, saving Claude/Fable usage, choosing a model for subagents, or doing multi-model coding workflows.
---

# Model Router

Use the main session as coordinator/judge. Subagents do token-heavy work and return structured reports.

## Hard rules

- Do not delegate one-liners or known-path tiny edits.
- Do not delegate architecture/final judgement. Main session decides.
- `scout`, `worker`, and `reviewer` have no pinned model. Every `Agent` call to them MUST include `model`.
- Claude pool is shared: Fable, Opus, and Sonnet compete. Preserve it for main judgement and hard escalations.
- OpenCode Go pool is shared: Kimi, DeepSeek, and MiniMax compete. Use it, but do not spam wastefully.
- Z.ai/GLM has abundant quota for this user. Prefer `zai/glm-5.2` when fit is close.
- Builder and reviewer should use different providers/pools when possible.
- Vision tasks require `Vision >= 7`.
- After two failed cheap attempts, escalate to stronger model or main session.

## Model scorecard

Scores are Pi-local routing priors. Higher is better. `Quota` means user's effective quota abundance, not list price.

| Model | Pool | Code | Debug | Review | Scout | LongCtx | Speed | Quota | Vision | Tools |
|---|---|---:|---:|---:|---:|---:|---:|---:|---:|---:|
| `claude-bridge/claude-fable-5` | Claude | 10 | 10 | 10 | 9 | 10 | 3 | 1 | 10 | 10 |
| `claude-bridge/claude-opus-4-8` | Claude | 9 | 9 | 9 | 8 | 10 | 4 | 2 | 8 | 9 |
| `claude-bridge/claude-sonnet-5` | Claude | 8 | 8 | 9 | 8 | 10 | 7 | 3 | 8 | 8 |
| `openai-codex/gpt-5.5` | OpenAI | 10 | 9 | 9 | 8 | 7 | 6 | 6 | 8 | 9 |
| `zai/glm-5.2` | Z.ai | 8 | 8 | 8 | 8 | 10 | 6 | 10 | 0 | 7 |
| `opencode-go/kimi-k2.7-code` | Go | 9 | 7 | 7 | 6 | 7 | 7 | 7 | 7 | 8 |
| `opencode-go/deepseek-v4-pro` | Go | 8 | 9 | 8 | 7 | 10 | 5 | 7 | 0 | 7 |
| `opencode-go/deepseek-v4-flash` | Go | 6 | 6 | 5 | 8 | 10 | 9 | 8 | 0 | 6 |
| `opencode-go/minimax-m3` | Go | 7 | 6 | 7 | 8 | 8 | 8 | 7 | 8 | 7 |

## Selection algorithm

1. Apply hard constraints: vision, write access, read-only review, provider separation.
2. Score candidates using task weights below.
3. Prefer highest `Quota` model within about 1 point of best capability fit.
4. Avoid Claude subagents unless quality/stakes require it.
5. Always include a clear report contract.

## Delegation template

Every delegation should be self-contained:

```text
Context: what larger task is and why.
Task: exact work for this agent.
Files: known paths / where to start.
Constraints: what not to touch, style, no new deps, security constraints.
Done means: exact behavior or checks.
Report back: files changed + line ranges, commands run + output summary, risks/open questions.
```

## Example calls

```text
Agent({
  subagent_type: "scout",
  model: "zai/glm-5.2",
  thinking: "low",
  description: "Map auth flow",
  prompt: "Context: ... Task: map auth flow only. No edits. Return path:line evidence and gaps."
})
```

```text
Agent({
  subagent_type: "worker",
  model: "opencode-go/kimi-k2.7-code",
  thinking: "medium",
  description: "Implement token fix",
  prompt: "Context: ... Task: implement exactly this fix. Files: ... Constraints: no new deps. Done means: ... Report back: ..."
})
```

```text
Agent({
  subagent_type: "reviewer",
  model: "openai-codex/gpt-5.5",
  thinking: "high",
  description: "Review auth diff",
  prompt: "Review git diff for correctness/security regressions. Do not edit. Return verdict + findings with path:line + checks run."
})
```
