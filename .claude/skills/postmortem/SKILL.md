---
name: postmortem
description: Write incident postmortems and post-incident reviews for homelab infrastructure. Use when the user asks to document an incident, write a postmortem, analyze what went wrong with their infrastructure, create an incident report, or learn from a failure. Also use when user mentions they fixed something and want to document it, or references past incidents they want to record.
---

# Postmortem Skill

Create blameless, learning-focused incident documentation for homelab infrastructure.

## Core Principles

1. **Construction, not purification** - Build knowledge, don't flagellate
2. **Blameless means systems-focused** - "How did the system allow this?" not "Who did this?"
3. **Contributing factors, not root cause** - Complex failures have multiple causes
4. **Be concrete** - Specific times, commands, errors
5. **Name the mental model** - What assumption was wrong?
6. **Action items must be actionable** - Specific, bounded, completable
7. **Surface what helped and where you got lucky** - Mitigators and near-misses reveal future risks
8. **Keep it simple enough to actually write** - A short postmortem is better than none

## When to Write a Postmortem

Write postmortems for principled matters - issues that reveal something about process, architecture, or mental models. Skip for trivial one-off errors that were immediately caught.

Good candidates:
- Outages or service degradation
- Incidents that took significant time to debug
- Near-misses that could have been worse
- Recurring issues (even if individually minor)
- Situations where assumptions proved wrong

## Template Usage

Copy the template from `template.md` to the user's postmortem location. The template includes:

- **Frontmatter**: Metadata for searchability (date, systems, tags, severity, commit link)
- **Timeline**: Concrete sequence of events with timestamps
- **What Happened**: Narrative description respecting decision context at the time
- **Contributing Factors**: Multiple causes (never singular "root cause")
- **What I Was Wrong About**: Mental models and assumptions that failed
- **What Helped / What Could Have Been Worse**: Mitigators and near-misses
- **Is This a Pattern?**: Distinguishes one-off errors from systemic issues
- **Action Items**: Specific, bounded, completable tasks
- **Lessons**: Key takeaways for future reference

## Writing Guidelines

### Timeline
Use consistent timezone (CST recommended). Include:
- First indication of problem
- When investigation began
- Key discoveries or decision points
- Resolution applied
- Confirmed resolved

### What Happened
Write narrative prose, not bullet points. Describe what the situation looked like at each stage - what information was available, what decisions were made based on that information. Avoid hindsight bias.

### Contributing Factors
List all conditions that combined to cause the incident. Resist the urge to pick a single "root cause." Ask: "If this factor had been different, would the incident still have happened?"

### What I Was Wrong About
This section is often the most valuable. Name specific assumptions or mental models that proved incorrect. Examples:
- "I assumed the config would reload automatically"
- "I thought opt1 mapped to the IoT VLAN"
- "I expected the rollback to be instant"

### Is This a Pattern?
Ask: Is this a one-off mistake within a sound approach, or does the approach itself need to change?
- One-off: Fix and move on
- Pattern: Document what needs to change at a higher level

### Action Items
Each item should be:
- Specific (not "be more careful")
- Bounded (clear scope and completion criteria)
- Actionable (something that can actually be done)

## Example

See `example.md` for a filled-in postmortem demonstrating these principles.
