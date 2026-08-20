# Project Supervisor

Optional per-repo supervision of visible Pi agents in Herdr. One Project may have one Project Supervisor.

## Language

**Project**:
A Git repository treated as one unit of optional supervision.
_Avoid_: workspace, fleet

**Project Supervisor**:
The optional Pi agent assigned to one Project to coordinate its Workers.
_Avoid_: Orchestrator, manager, parent agent, fleet supervisor

**Operator**:
The person directing Project work and owning final direction and approval.
_Avoid_: User

**Worker**:
A visible Herdr Pi agent, with its worktree, that does Project work at the top level.
_Avoid_: Pane, Subagent, child, slot

**Child Agent**:
A private Pi subagent that a Worker starts for its own work. The Worker remains responsible for the Child Agent's result.
_Avoid_: Worker, Subagent (as a top-level role)

**Goal**:
An operator-owned outcome for a Project. One Goal may include several Deliverables.
_Avoid_: task, ticket, job

**Deliverable**:
One unit of shippable work: one branch, one worktree, and one pull request.
_Avoid_: task, commit, patch

**Current Scope**:
The Goal and Deliverable a Worker is already pursuing.
_Avoid_: context, assignment

**Plan**:
A proposed arrangement of Deliverables, dependencies, and Worker ownership for a Goal.
_Avoid_: spec, ticket, prompt

**Adoption**:
The relationship in which a Project Supervisor coordinates a Worker it did not create.
_Avoid_: attach, import, takeover

**Ready for Review**:
A Deliverable whose pull request is open and whose required CI and independent review have passed.
_Avoid_: done, complete, merged
