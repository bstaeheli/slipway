---
name: adk-build
description: Build a spec slice by slice after adk-spec: contracts, code and test lanes, test runs, cross-review, one PR per slice, then the summary. Applies only in projects that have docs/agents/.
---

# adk-build

Follow `rules/adk.md` by heading. The user is not present: stop only for blockers per `## Stopping and blockers`. Input: `docs/agents/specs/<slug>.md` and the slice lines in `docs/agents/status.md`.

## Steps

1. **Resume.** Pick the first unchecked slice under `## Active` in `docs/agents/status.md`. Never build slices under `## Parked`. If none is left and blockers exist, stop and present `## Blockers for the user` as one batch.
2. **Fresh subagent per slice.** Give it only its slice, the contracts and the relevant constitution parts. You stay a lean orchestrator per `## Model and context economy`: keep summaries and file pointers only.
3. **Contracts.** Derive signatures, data shapes and error cases from the spec. Review them, then turn them into a code skeleton.
4. **Lanes.** Run two separate subagents, in parallel where the tool allows, otherwise sequential:
   - Code lane: implements the skeleton using `### Context` and `### Graph`.
   - Test lane: writes tests from `## Acceptance`, `### Acceptance checks` and the contracts. Tell it to not read the implementation.
   - Review each lane's output before running tests.
5. **Run tests** with the commands from `docs/agents/constitution/tech-stack.md`.
6. **Analyze failure.** Decide who is wrong: code, test or spec. A code or test fault goes back to that lane. A spec fault becomes a parked question: move the slice to `## Parked` and add the question to `## Blockers for the user`.
7. **Give up.** After 3 attempts at the same problem, stop that slice, record a blocker with an honest note in `docs/agents/status.md`, park it, note it in the summary, and continue with the next slice.
8. **Cross-review.** A separate reviewer checks code vs spec, tests vs spec and code vs tests: do they tell the same story? Fix findings in the owning lane.
9. **PR.** One PR per slice, opened and merged per `## Git platforms` and `## Permissions and environments`; leave it open if `AGENTS.md` says `merge: human`. Tick the slice to `- [x]` and move it to `## Done` in `docs/agents/status.md`.
10. **Last slice of a spec.**
    - Write the summary for the user (the user reads only this): what was built; tests run with results; open or parked slices; decisions you made; every "assumed" item from the spec; tier escalations. Never claim a test passed that was not run (`## Prohibitions`).
    - Postmortem: append lessons to `docs/agents/lessons.md`.
    - Delete the spec file. Git keeps the history.

## Tiers

Lanes on the mid tier, contracts, reviews and failure analysis on the large tier, status updates on the small tier. Escalate only after a failure, per `## Model and context economy`.

## Copilot

Copilot cannot chain sessions: after each slice, tell the user to type "continue" to run the next one.
