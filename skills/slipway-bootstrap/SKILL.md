---
name: slipway-bootstrap
description: Bootstrap a project into the agent development kit, using local or external state. Use only when the user asks to bootstrap or opt in.
disable-model-invocation: true
---

# slipway-bootstrap

Opt this repo into the kit. Follow `~/.claude/rules/slipway.md` (`## Opt-in`, `## Permissions and environments`, `## Git platforms`) by name; do not restate it.

## Steps

1. Choose external mode only if the user requests it (for example `/slipway-bootstrap external`); otherwise use the existing local mode. If `docs/agents/` exists or the `state.py resolve` command from `## Opt-in` succeeds, stop and tell the user. Exit 1 without output means not opted in; any other error is a blocker. Never overwrite files.
2. In external mode, use the same launcher and quoted path from `## Opt-in`, replacing `resolve` with `init` to run `state.py init` from the project, and use its output as the state directory. On error stop and report it. In local mode create `docs/agents/` as the state directory. Populate the state directory from the `templates/` next to this file:
   - In local mode, `AGENTS.md` at the repo root (append the kit section if the file exists). In external mode, `AGENTS.md` in the state directory: replace the template's `docs/agents/` references with the absolute state directory; do not create or edit the repo-root file.
   - `constitution/{brief,tech-stack,invariants,vocabulary,environments}.md`
   - `status.md`, `lessons.md`
   - empty `specs/` and `brainstorm/` (add `.gitkeep`).
3. Existing project (it has code or history): draft the constitution yourself from the repo. Read README, manifests (`app.json`, `Cargo.toml`, `package.json` and similar), CI config, tests, and `git log`. Fill brief, tech-stack (including real build, test and local publish commands), invariants and vocabulary. Mark guesses as `(unconfirmed)`.
4. New project: ask the user for one-line answers to what the project is, for whom, and the stack. Keep the rest as skeleton.
5. `environments.md`: list no target unless the user names it. Unlisted targets count as customer environments.
6. Ask the user only to confirm the draft, as one summary. Apply corrections, then commit only in local mode. External state is local to the machine and must not be committed to the project.

## Do not

- Never create `CLAUDE.md`. `AGENTS.md` is read by Claude Code and Copilot.
- Never create `roadmap.md` or `personas.md` by default. Their templates say when to create them; copy one only when that condition holds.
- Invent facts. Leave a heading empty rather than guess.
