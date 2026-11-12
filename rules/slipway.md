---
applyTo: "**"
description: Agent development kit rules. Active in opted-in repositories.
---

## Opt-in

Resolve opt-in from the current project directory using a working Python 3 launcher:

- PowerShell: `py -3 "$HOME\.agents\skills\slipway-bootstrap\state.py" resolve`. If `py -3` is unavailable or has no Python 3, use `python "$HOME\.agents\skills\slipway-bootstrap\state.py" resolve` or `python3 "$HOME\.agents\skills\slipway-bootstrap\state.py" resolve` instead.
- POSIX shell: `python3 "$HOME/.agents/skills/slipway-bootstrap/state.py" resolve`.

Select the launcher by checking its Python version before invoking the resolver, not by retrying resolver errors. A successful result is the absolute state directory. Exit 1 with no output means not opted in: do nothing and ignore this whole file. Any other error is a blocker; do not assume the project is not opted in. Exception: the user asks to bootstrap a project (tell the user to type `/slipway-bootstrap`).

The local state directory is `docs/agents/`. An external opt-in stores state outside the repository. In this file and every `slipway-*` skill, interpret paths starting with `docs/agents/` relative to the resolved state directory instead: replace the `docs/agents/` prefix with that directory. Never create or commit external state inside the repository.

## Precedence

In opted-in projects, `slipway-*` skills take precedence over overlapping skills from other plugins (for example Superpowers brainstorming, writing-plans). Kit storage locations under `docs/agents/` win over any other skill's locations.

## Workflow

- Read `docs/agents/constitution/` and `docs/agents/lessons.md` first.
- Route work via `slipway-brainstorm`.
- Resume unfinished work from `docs/agents/status.md`.
- Never read deleted or old specs: code is the truth, git is the history.

## Freedoms

The agent may:

- choose its approach and make technical decisions
- select tools
- refactor
- design tests and verification
- challenge assumptions
- adapt plans

## Prohibitions

The agent must never:

- violate the constitution
- contradict explicit requirements
- break established contracts
- compromise security or privacy
- silently change intended behavior
- weaken, skip or delete tests to make them pass
- conceal failures or uncertainty
- publish to or delete on customer environments
- publish to package registries (crates.io, npm, PyPI, NuGet, AppSource and similar) unless the target is listed in `environments.md`

## Principles

- Constrain the outcomes, not the intelligence.
- Engineer reliability, not predictability.
- Every rule, review and artifact must justify its cost.
- Kit skills take precedence over overlapping skills from other plugins.

## Stopping and blockers

- Stop only when blocked and no other work is left.
- Park a blocked slice and continue with other work.
- Collect blockers as a list in `docs/agents/status.md` so the user gets one batch.
- Never query a password manager (Bitwarden, 1Password) and never bypass a confirmation. Secrets stay with the user. SSH logins to remote machines are blockers.

## Permissions and environments

- Allowed: `git push`, opening pull requests, publishing to local development environments.
- Merge each slice's PR yourself, unless `AGENTS.md` contains `merge: human`.
- Forbidden: publishing to or deleting on customer environments; publishing to package registries (`cargo publish`, `npm publish`, AppSource submissions and similar).
- Allowed publish targets are listed in `docs/agents/constitution/environments.md` under the heading `## Allowed targets`. Each list item's first backtick literal is the target token, for example ``- `bcdev` local Docker container``.
- Any target that is not listed counts as a customer environment and is forbidden. Never judge a target by its name.

## Git platforms

Detect the platform from `git remote get-url origin`:

- `github.com`: GitHub
- `dev.azure.com` or `visualstudio.com`: Azure DevOps
- `codeberg.org`: Forgejo
- any other host: Forgejo only if `AGENTS.md` contains `git-platform: forgejo`; otherwise ask once and record the answer there

For external state, consult the existing repo-root `AGENTS.md` if present and the state directory's `AGENTS.md` for kit overrides; the repo-root file takes precedence. Do not write to the repo-root file for external opt-in.

Open PRs and merge through that platform's MCP server. A missing MCP server is a blocker in `status.md`, not a silent fallback. If the repo has no PR capability at all, merge locally.

## Model and context economy

Use only as large a model and as much context as necessary.

- Lean orchestrator: route and delegate; keep only summaries and file pointers, never file dumps or full transcripts.
- Use the smallest tier that does the job reliably:
  - large: judgment-heavy steps (brainstorm, spec, design, review, failure analysis)
  - mid: well-specified execution (code lane, test lane, mechanical edits)
  - small: trivial tasks (status updates, formatting, searching)
- Escalate to a larger tier only after a failure at the smaller one, and record every escalation in the summary to the user.
- Give each subagent fresh, minimal context: its spec slice, the relevant contracts, the relevant parts of the constitution.

Tier mapping per tool:

| Tool | large | mid | small |
|---|---|---|---|
| Claude Code | `opus` | `sonnet` | `haiku` |
| Copilot CLI | pick per tier from available models (custom agent `model` field) | same | same |
| VS Code Copilot | inherits session model until verified | same | same |
