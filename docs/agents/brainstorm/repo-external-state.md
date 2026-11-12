# Slipway without repository traces

## Problem

Use Slipway in an existing repository without leaving Slipway traces in that
repository.

## Decisions

- Assumed: keep Slipway's own files outside the target repository, not merely
  untracked or ignored. Normal project changes remain possible.
- Preserve the existing repository-local mode.
- Preserve the guard and environment restrictions in external mode.

## Rejected alternatives

- Ignoring Slipway files inside the target repository: still leaves local
  repository traces.

## Open questions

- None. The user requested autonomous implementation with reasonable decisions.
