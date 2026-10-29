---
name: adk-do-it
description: Implement a small, clear change directly with no spec, test it, and ship it. Applies only in projects that have docs/agents/.
---

# adk-do-it

Follow `rules/adk.md` by heading. Run on the mid tier; escalate per `## Model and context economy`. The user is not present: stop only for blockers per `## Stopping and blockers`.

## Steps

1. Read `docs/agents/constitution/` and `docs/agents/lessons.md`, and the brainstorm file if one exists. There is no spec: the brainstorm result is the brief.
2. Implement. Add or update tests for the change.
3. Run the build and test commands from `docs/agents/constitution/tech-stack.md`. Fix failures. After 3 attempts at the same problem, stop, record it as a blocker in `docs/agents/status.md`, and say so in the summary.
4. Open one PR and merge it per `## Git platforms` and `## Permissions and environments`, unless `AGENTS.md` says `merge: human`.
5. Summarize for the user: what changed, tests run and result, decisions you made, any tier escalation.
