# Slipway without repository traces

## Intent

Use the Slipway workflow in an existing repository without leaving Slipway
artifacts there.

## Must

- Assumed: keep Slipway's own state and configuration outside the target
  repository, including untracked and ignored files.
- Support the existing repository-local mode without changing its behavior.
- Apply the existing environment restrictions and guard in external mode.

## Must not

- Create or modify target-repository files or Git metadata for Slipway's own
  configuration or workflow state.
- Treat normal project changes as forbidden.

## Acceptance

- A repository can opt in and run the workflow with all Slipway state outside
  the repository.
- The guard enforces allowed targets in both modes.
- Existing local-mode and non-opted-in behavior remains unchanged.
- The target repository contains no Slipway artifacts or Git metadata changes
  caused by opting in or maintaining workflow state.

## Design

### Context

- The current opt-in, bootstrap, workflow skills and guard rely on
  `docs/agents/` inside the repository.
- Bootstrap also changes root `AGENTS.md`; external mode cannot.
- The guard treats a missing environments file as having no allowed targets.
- The current repository has no constitution or lessons file.

### Graph

- Bootstrap must provide a user-selected external opt-in and maintain its state.
- Rules and all workflow skills must resolve the same state location.
- The guard must resolve that location and use its environments file.
- Tests and README must cover the external mode and unchanged local mode.

### Acceptance checks

- Bootstrap and exercise the workflow against a temporary Git repository;
  compare its files and Git metadata before and after creating and updating
  Slipway state.
- Verify state is reusable in a subsequent session.
- Check listed and unlisted targets from the repository root and a
  subdirectory in both modes.
- Run existing local-mode bootstrap, workflow, guard, content and installer
  checks, including non-opted-in cases.

## Slices

- S1: External state resolution and guard. Covers guard enforcement and
  unchanged guard behavior.
- S2: External bootstrap and workflow. Covers opt-in, workflow use, unchanged
  local behavior and repository cleanliness. Depends on S1.
