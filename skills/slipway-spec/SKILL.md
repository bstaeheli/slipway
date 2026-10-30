---
name: slipway-spec
description: Turn a brainstorm result into a spec, design and small runnable slices, then hand off to slipway-build. Applies only in projects that have docs/agents/.
---

# slipway-spec

Follow `~/.claude/rules/slipway.md` by heading. Run producing and reviewing on the large tier per `## Model and context economy`. The user is not present: stop only for blockers per `## Stopping and blockers`.

## Steps

1. Read `docs/agents/constitution/`, `docs/agents/lessons.md` and `docs/agents/brainstorm/<slug>.md`.
2. **Spec.** Write `docs/agents/specs/<slug>.md` from `templates/spec.md`. Fill `## Intent`, `## Must`, `## Must not`, `## Acceptance`. State intent and outcomes only; never how it is built, layout or wording. Anything unsaid is the implementer's call.
3. **Design.** Fill `## Design`: `### Context` (relevant knowledge), `### Graph` (affected code structure), `### Acceptance checks` (concrete checks for each acceptance item).
4. **Plan.** Draft the execution plan in the session. It is transient: the plan is never written to the repo.
5. **Slicing.** Fill `## Slices` in order with ids `S1`, `S2`, ... Each slice is small, independently runnable and testable. Add one line per slice under `## Active` in `docs/agents/status.md`: `- [ ] <slug>/S<n>: <title>`. Slices that depend on an assumption go under `## Parked` instead (see below).
6. Hand off to `slipway-build`.

## Review loop

Run one after each of spec, design, plan and slicing, before moving on.

- The reviewer is a separate subagent with minimal context (the artifact, the brainstorm file, the relevant constitution) where the tool supports it.
- It flags violations only: of the brainstorm result, the constitution, or this skill. It must never invent new obligations and must not re-debate upstream decisions.
- The producer fixes findings and resubmits until the review is clean.
- Limit: 3 rounds. Then park the open findings with a note under `## Parked` in `docs/agents/status.md` and continue.

## Questions and summary

- A spec question only the user can answer goes under `## Blockers for the user` in `docs/agents/status.md`, together with the assumption you make: the most conservative reading. Also write the assumption into the spec under `## Must` or `## Intent`, marked "assumed".
- Park every slice whose behavior depends on an assumption: list it under `## Parked`, not `## Active`, naming the assumption. Slices that do not depend on it proceed.
- Give the user a summary of a few lines, not the spec: intent, the slice list, open questions, and every assumption.
