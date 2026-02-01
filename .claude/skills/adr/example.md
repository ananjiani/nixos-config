---
date: 2026-02-01
title: Use MADR format for architecture decision records
status: accepted
supersedes:
superseded_by:
systems: [documentation, mkdocs]
tags: [documentation, process, adrs]
---

## Context and Problem Statement

The homelab infrastructure has a growing collection of postmortems documenting incidents, but no systematic way to capture the reasoning behind architectural decisions. When revisiting a decision months later — "why did I choose Flux over ArgoCD?" or "why host-gw instead of VXLAN?" — the rationale is lost to memory. An ADR practice needs a template format that balances thoroughness with the reality of being a solo operator who needs low friction to actually write these.

## Decision Drivers

- Single operator — the format must be fast enough to complete in one sitting
- Decisions often involve evaluating 2-4 alternatives, so the format must capture comparison data
- Must integrate with existing mkdocs documentation site alongside postmortems
- Frontmatter metadata needed for tagging and searchability (matching postmortem conventions)
- Should support ADR supersession (decisions evolve over time)

## Considered Options

1. MADR (Markdown Any Decision Records) v3 — full template
2. Nygard Minimal — original ADR format (Context, Decision, Consequences)
3. Hybrid — Nygard core with an Alternatives Considered section added

## Decision Outcome

Chosen option: "MADR v3 full template", because the structured Pros/Cons per option creates a reusable comparison matrix. When context changes (more RAM, different requirements), the detailed option analysis lets you re-evaluate without re-researching. The additional structure over Nygard is worth the effort for decisions that warranted writing an ADR in the first place.

### Consequences

- Good: Complete audit trail of what was evaluated and why each option was accepted or rejected
- Good: Decision Drivers section forces explicit prioritization of constraints
- Good: Confirmation section creates a built-in checkpoint to verify the decision is working
- Bad: Heavier than Nygard — each ADR takes longer to write due to per-option Pros/Cons sections
- Bad: For simple binary decisions, the full template may feel like overkill
- Neutral: Frontmatter additions (supersedes/superseded_by) are custom extensions beyond standard MADR

### Confirmation

First 5 ADRs written using this template without feeling the format is a bottleneck. At least one ADR's Pros/Cons section referenced when revisiting a decision.

## Pros and Cons of the Options

### MADR v3

- Good: Structured Pros/Cons per option creates a reusable comparison matrix
- Good: Decision Drivers section explicitly names what matters most
- Good: Confirmation section adds accountability for decision outcomes
- Good: Widely adopted — familiar to anyone who's encountered ADRs before
- Neutral: More sections to fill out than the other options
- Bad: Per-option analysis can feel repetitive for decisions with many similar alternatives
- Bad: May discourage writing ADRs for smaller decisions due to perceived overhead

### Nygard Minimal

- Good: Fastest to write — three sections total (Context, Decision, Consequences)
- Good: Forces conciseness — no room for unnecessary detail
- Good: Lowest barrier to entry — easy to adopt and maintain
- Bad: No place to document rejected alternatives and why they were rejected
- Bad: Consequences section doesn't distinguish positive from negative outcomes
- Bad: When revisiting a decision, you can't see what else was considered

### Hybrid (Nygard + Alternatives)

- Good: Almost as fast as Nygard with the critical addition of alternatives
- Good: Alternatives section captures "what else was on the table" without full MADR ceremony
- Neutral: Non-standard — would need to explain the format to anyone reading the docs
- Bad: Lacks structured Pros/Cons — alternatives are described in prose without consistent comparison criteria
- Bad: No Decision Drivers section means priorities are implicit rather than explicit
