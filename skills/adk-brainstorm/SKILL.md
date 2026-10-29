---
name: adk-brainstorm
description: Front door for new work. Talk through the problem with the user, then route to adk-do-it, adk-bugfix or adk-spec. Applies only in projects that have docs/agents/.
---

# adk-brainstorm

Follow `rules/adk.md` (`## Workflow`, `## Model and context economy`). Run on the large tier. This is the only step where the user is present.

## Steps

1. Read `docs/agents/constitution/` and `docs/agents/lessons.md`. Check `docs/agents/brainstorm/` for a matching `<slug>.md` and resume from it.
2. Have the user describe the problem, not the solution. Ask one question at a time. Challenge assumptions, explore alternatives, surface contradictions with the constitution or earlier answers.
3. Record the conversation state in `docs/agents/brainstorm/<slug>.md`: problem, decisions, rejected alternatives, open questions. Update it as you go so a later session can resume.
4. Route:
   - `adk-bugfix`: something that worked or should work is broken.
   - `adk-do-it`: small and clear, no spec needed.
   - `adk-spec`: only when the work binds architecture, carries business logic, or spans parts that must ship in order.
5. Tell the user the route in one line, then invoke the chosen skill. Everything after runs without the user, except blockers per `## Stopping and blockers`.
