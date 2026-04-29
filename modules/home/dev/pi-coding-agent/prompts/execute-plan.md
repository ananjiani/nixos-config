Execute the attached plan. Do not enter plan mode — proceed directly to implementation.

Read the plan file, extract all unchecked `[ ]` items, and execute them in order.

SYNC RULES:
- Do NOT update the spec artifact after every individual task — that is noisy and wastes tokens.
- Only sync completed items back to the spec artifact at MILESTONES:
  * Phase boundaries (when the spec has `## Phase` headers)
  * When you finish a logically coherent chunk of work
  * When the user explicitly asks for a progress update
  * At the very end when all tasks are done
- For markdown specs: use `edit` to batch-change `[ ]` to `[x]` for all completed items since the last sync.
- For issue specs: use `tea issue comment` with a brief progress summary, or `tea issue edit` to update the body. Do not spam comments.
