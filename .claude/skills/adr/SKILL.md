---
name: adr
description: Write architecture decision records for homelab infrastructure. Proactively invoke when you notice the user choosing between technologies, evaluating alternatives for infrastructure changes, making architectural decisions, or mentioning they "decided to use X over Y." Suggest writing an ADR rather than waiting to be asked.
---

# ADR Skill

Create structured architecture decision records (ADRs) for homelab infrastructure using the MADR format.

## Core Principles

1. **Capture the "why" not the "what"** - The decision itself is obvious from the code; the reasoning is not
2. **Immutability** - Accepted ADRs are never edited, only superseded by new ADRs
3. **Document alternatives seriously** - They may become relevant when context changes
4. **Be concrete** - Specific systems, constraints, and tradeoffs, not vague handwaving
5. **Consequences include negatives** - Be honest about the downsides you're accepting
6. **Keep it completable** - A short ADR is better than none

## When to Write an ADR

Write ADRs for decisions that are architecturally significant - choices that would be hard to reverse, that affect multiple systems, or that future-you will wonder about.

Good candidates:
- Choosing between competing technologies (e.g., Flux vs ArgoCD)
- Infrastructure architecture changes (e.g., switching CNI plugins)
- New patterns or conventions (e.g., adopting GitOps, choosing a secret management approach)
- Significant configuration decisions (e.g., VXLAN vs host-gw for flannel)
- Decisions that required research or evaluation of alternatives
- Changes where the "why" isn't obvious from the code alone

Skip for:
- Trivial configuration tweaks
- Bug fixes (use a postmortem if the bug was interesting)
- Decisions that are easily and cheaply reversible

## File Naming Convention

Use the format: `NNNN-YYYY-MM-DD-slug.md`

- **NNNN**: Zero-padded sequential number (0001, 0002, ...)
- **YYYY-MM-DD**: Date the decision was made
- **slug**: Brief kebab-case description of the decision

Examples:
- `0001-2026-01-15-use-k3s-over-full-k8s.md`
- `0002-2026-01-20-flux-for-gitops.md`
- `0003-2026-01-25-flannel-host-gw-backend.md`

Numbers are monotonically increasing and never reused. If a decision is superseded, the old ADR keeps its number but gets a `superseded_by` field pointing to the new one.

## File Location

ADRs are stored in `docs/adrs/` and served via mkdocs alongside postmortems.

## Template Usage

Copy the template from `template.md` to the ADR location. The template follows MADR v3 and includes:

- **Frontmatter**: Metadata for searchability (date, status, systems, tags, supersession chain)
- **Context and Problem Statement**: What situation prompted this decision
- **Decision Drivers**: The specific forces, constraints, and priorities shaping the choice
- **Considered Options**: All alternatives that were seriously evaluated
- **Decision Outcome**: The chosen option with rationale
  - **Consequences**: Good, bad, and neutral outcomes (be honest)
  - **Confirmation**: How to verify the decision is working as expected
- **Pros and Cons of the Options**: Detailed analysis of each alternative

## Writing Guidelines

### Context and Problem Statement
Write 2-4 sentences describing the situation that requires a decision. Include the specific constraints (hardware, time, expertise, budget) that make this non-trivial. Write as narrative prose — this is the story of why you needed to decide.

### Decision Drivers
List the specific factors that matter most for this decision. These are the criteria you're optimizing for. Order them by priority. Examples:
- "Limited RAM on Proxmox VMs (3 nodes, 8GB each)"
- "Single operator — operational simplicity is critical"
- "Must integrate with existing Flux GitOps workflow"

### Considered Options
List all alternatives you seriously evaluated. Don't include options you dismissed immediately — only those that had genuine merit. Number them for easy reference in the Pros/Cons section.

### Decision Outcome
State the chosen option clearly: "Chosen option: [option name], because [1-2 sentence rationale linking back to decision drivers]."

**Consequences** use the format:
- Good: [positive outcome]
- Bad: [negative outcome you're accepting]
- Neutral: [outcome that's neither positive nor negative]

Be honest about the "Bad" consequences — they're why someone might revisit this decision later.

**Confirmation** describes how you'll know this decision is working. Be specific:
- "Cluster stable for 2 weeks with resource usage under 70%"
- "Flux reconciliation succeeding without manual intervention"

### Pros and Cons of the Options
Give each considered option its own subsection with bullet points. Use the format:
- Good: [advantage]
- Neutral: [observation]
- Bad: [disadvantage]

Be fair to rejected alternatives — document their genuine strengths. The goal is that if context changes (more RAM, more operators, different requirements), you can quickly re-evaluate.

## Superseding an ADR

When a decision needs to change:
1. Create a new ADR with the next sequential number
2. In the new ADR's frontmatter, set `supersedes: NNNN` (the old ADR's number)
3. Update the old ADR's frontmatter to add `superseded_by: NNNN` (the only edit allowed to an accepted ADR)
4. In the new ADR's Context section, explain what changed to warrant revisiting the decision

## Example

See `example.md` for a filled-in ADR demonstrating these principles.
