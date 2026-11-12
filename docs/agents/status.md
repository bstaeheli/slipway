# Status

## Active

- [ ] repo-external-state/S1: External state resolution and guard (PR #1, awaiting CI and merge).
  - Unresolvable home directories deny commands in Git repositories: external
    opt-in cannot be ruled out safely.
- [ ] repo-external-state/S2: External bootstrap and workflow (PR #2, stacked on #1, awaiting CI and merge).
  - Tests: Python suite 126 passed on Windows and Linux; PowerShell 7 installer
    187 assertions passed; Linux installer 143 assertions passed.

## Done

## Parked

## Blockers for the user

- macOS CI jobs are queued; merge #1 after checks pass, then retarget #2 to
  main and merge after its checks pass.
