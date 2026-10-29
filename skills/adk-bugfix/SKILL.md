---
name: adk-bugfix
description: Fix a bug test-first with a reproduction test, then ship it. Applies only in projects that have docs/agents/.
---

# adk-bugfix

Follow `rules/adk.md` by heading. Run on the mid tier; escalate per `## Model and context economy`. The user is not present: stop only for blockers per `## Stopping and blockers`.

## Steps

1. Read `docs/agents/constitution/` and `docs/agents/lessons.md`.
2. Find the root cause, not just the symptom.
3. Write a reproduction test. Run it with the commands from `docs/agents/constitution/tech-stack.md` and show that it fails for the reported reason.
4. Fix the cause. Run it again and show that it passes, then run the full suite.
5. Never alter the reproduction test to make it pass. If the test is wrong, say so and rewrite it, then show that it fails again before the fix.
6. Open one PR and merge it per `## Git platforms` and `## Permissions and environments`, unless `AGENTS.md` says `merge: human`.
7. Summarize: what changed, tests run and result, decisions you made, any tier escalation.
