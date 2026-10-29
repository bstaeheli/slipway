---
name: adk-build
description: Build a spec slice by slice after adk-spec, with contracts, code and test lanes, test runs, cross-review and one PR per slice, then the summary. Applies only in projects that have docs/agents/.
---

# adk-build

Follow `rules/adk.md` by heading. The user is not present: stop only for blockers per `## Stopping and blockers`. Input: `docs/agents/specs/<slug>.md` and the slice lines in `docs/agents/status.md`.

## Steps

1. **Resume.** First check each slice marked awaiting human merge via the platform MCP server. Merged: tick it and move it to `## Done`; if that completes a spec, run step 10's wrap-up for it. Closed without merging: add a blocker to `## Blockers for the user`. Then pick the first unchecked slice under `## Active` in `docs/agents/status.md` that is not awaiting merge. Never build slices under `## Parked`. If none is left and blockers exist, stop and present `## Blockers for the user` as one batch.
2. **Fresh subagent per slice.** Give it only its slice, the contracts and the relevant constitution parts. You stay a lean orchestrator per `## Model and context economy`: keep summaries and file pointers only.
3. **Contracts.** Derive signatures, data shapes and error cases from the spec. Review them, then turn them into a code skeleton.
4. **Lanes.** Run two separate subagents, in parallel where the tool allows, otherwise sequential:
   - Code lane: implements the skeleton using `### Context` and `### Graph`.
   - Test lane: writes tests from `## Acceptance`, `### Acceptance checks` and the contracts. Tell it to not read the implementation.
   - Review each lane's output before running tests.
5. **Run tests** with the commands from `docs/agents/constitution/tech-stack.md`.
6. **Analyze failure.** Decide who is wrong: code, test or spec. A code or test fault goes back to that lane; never weaken a test to pass (`## Prohibitions`). A spec fault becomes a parked question: move the slice to `## Parked` and add the question to `## Blockers for the user`.
7. **Give up.** In any fix loop (lane review, test failure, cross-review): after 3 attempts at the same problem, stop that slice, record a blocker with an honest note in `docs/agents/status.md`, park it, note it in the summary, and continue with the next slice.
8. **Cross-review.** A separate reviewer checks code vs spec, tests vs spec and code vs tests: do they tell the same story? Fix findings in the owning lane, then rerun step 5.
9. **PR.** One PR per slice, opened and merged per `## Git platforms` and `## Permissions and environments`.
   - Record in the PR description: tests run with results, decisions you made, tier escalations. Add a one-line note of the same under the slice line in `docs/agents/status.md`.
   - When merged, tick the slice to `- [x]` and move it to `## Done`.
   - If `AGENTS.md` says `merge: human`, leave the PR open, keep the line under `## Active` as `- [ ] <slug>/S<n>: <title> (PR <link>, awaiting human merge)`, and move on. While an earlier slice's PR awaits merge, branch the next slice from that PR's branch (stacked) and say so in its PR description.
10. **End of a spec.**
    - Summary: write it when no buildable slice of the spec remains under `## Active` (the last slice is opened or parked). Build it from the PR descriptions and status notes, not from memory. The user reads only this: what was built; tests run with results; open or parked slices; PRs awaiting merge; decisions you made; every "assumed" item from the spec; tier escalations. Never claim a test passed that was not run (`## Prohibitions`).
    - Wrap-up, only when every slice of the spec is merged, possibly on a later run: postmortem, appending lessons to `docs/agents/lessons.md`, then delete the spec file. Git keeps the history.

## Tiers

- Code lane and test lane: mid tier.
- Contracts, reviews and failure analysis: large tier.
- Status updates: small tier.

Escalate only after a failure, per `## Model and context economy`.

## Copilot

Copilot cannot chain sessions: after each slice, tell the user to type "continue" to run the next one.
