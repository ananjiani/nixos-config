---
name: product-design
description: Workflow layer for shaping, building, and reviewing user-facing UI — the "how to approach UI work" skill that routes to specialists. Use when designing or changing any user-facing flow, page, form, or multi-step journey; when asked to ship "production-ready"/"polish" a UI; or when about to build a feature beyond the happy path. Resolves the request mode, forces full-state coverage, and adapts to the repo's stack. For VISUAL/aesthetic choices (typography, color, layout polish, escaping "AI-slop") load `frontend-design`.
---

# Product Design

This is the **workflow** layer — borrowed from Vercel's `product-design` method
(not portable upstream: their skill is hardcoded to Geist / `apps/vercel-site`).
It does not duplicate the visual guidance in `frontend-design`; it routes there.

## ⚠️ Stack flag — detect before you impose

Default assumption is the agent-friendly stack: **React/Next.js App Router +
TypeScript strict + Tailwind + shadcn/ui** (shadcn = copy-in components the agent
can read/edit, not an npm black box; TS + Zod = self-checkable contracts).

**Read the target repo first** (`package.json`, existing components, styling).
If it's Svelte/Vue/Solid/vanilla, apply every principle below in that stack's
idioms — don't drag React in. If the repo has a design system or token file,
**it wins over your tastes**; compose from its primitives. The repo's existing
world always beats your defaults.

## Resolve the mode first

Identify the mode from the user's verb before acting — stops audits becoming
silent redesigns and copy passes ballooning:

| Mode | Trigger | Behavior |
|------|---------|----------|
| **Shape** | "design this flow", "how should this work?", unsettled brief | Frame the problem, compare alternatives, define flow + states + acceptance criteria. **Do not edit unless asked.** |
| **Implement** | "build", "fix", "improve" | Resolve product decisions, ship the smallest coherent end-to-end change. Don't absorb unrelated findings. |
| **Review** | "audit", "critique", "what's wrong?" | Inspect source + rendered evidence, report prioritized findings. **Do not edit unless asked.** |
| **Copy** | "fix the copy", "rewrite these errors" | Edit user-facing language + accessible names + required JSX only. Don't broaden scope. |
| **Harden** | "polish", "production-ready", "handle edge cases" | Keep settled direction, fix state/responsive/a11y/finish defects. |

Ambiguous? Take the **narrowest** mode the verb supports. A URL/screenshot/route
sets scope, not authorization to edit.

## Start with the job, not the pixels

Before any surface or component, answer out loud: **who** is acting, **what**
they're trying to accomplish (the job, not the feature), the **product object**
and what the system will **change**, current behavior → desired outcome → success
signal, and **non-goals**. Mark assumptions explicitly — never hide them in
implementation. Consider better defaults/behavior/reuse *before* adding UI; the
smallest coherent intervention usually isn't a new screen. **Decide before
decorating**: information architecture, component semantics, interaction, and
state behavior before styling or copy.

## Design every reachable state — the core cure for happy-path-only

This is the failure mode agents default to. Inventory the states the product can
actually enter and design each — never stop at the populated success case:

- **Loading** — skeleton/progress, not a frozen screen. Long ops need a status
  message, not just a spinner.
- **Empty / first-run** — no data yet. Invitation to act, not a blank mood.
- **Sparse** — 1–2 items (layouts built for 20 often break here).
- **Populated** — the happy path.
- **Validation** — inline, on blur, specific, preserves input.
- **Error** — three-part: what happened, why, how to fix. Plain language, never
  blames the user, preserves entered data.
- **Permission / unauthorized** — what they *can* do, not just "403".
- **Disabled** — why, and how to enable it.
- **Optimistic / stale** — indicate stale data while fresh loads.
- **Destructive** — proportional to impact; prefer undo over "Are you sure?";
  name exact object/scope/consequence.
- **Responsive** — 320px and 1440px+, not just your default viewport.

For AI/agent-driven surfaces add: **thinking/waiting** (LLM latency is seconds,
show progress not silence) and **partial-success / recovery**.

## Verify by rendering, not by reading code

Never claim visual/interaction verification from source alone. The
**chrome-devtools MCP** tool is available — screenshot the changed states
(populated *and* empty *and* error), check narrow + wide viewports, exercise
keyboard order and focus movement, test long content and large values. A
screenshot is the only honest "it works."

## Review output (mode = Review)

Findings ordered by user impact: **P0** blocks primary task / severe a11y
failure / unrecoverable harm · **P1** likely task failure / misleading
consequence / missing critical state · **P2** meaningful friction /
inconsistency · **P3** minor craft. Each: location, verification status, user
consequence, smallest concrete fix.

## Routing

- Visual aesthetic, typography, color, escaping "AI-slop" defaults → **`frontend-design`** (imported).
- Interface *for an autonomous agent* (transparency, override, confidence
  signaling) → apply the four foundations: transparency at the decision,
  step-level override, proactive status, composable blocks; binary confidence
  over fake percentages; progressive delegation.
