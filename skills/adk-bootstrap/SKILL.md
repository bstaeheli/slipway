---
name: adk-bootstrap
description: Bootstrap a project into the agent development kit. Opts the project in by creating docs/agents/ from templates. Use only when the user asks to bootstrap or opt in.
disable-model-invocation: true
---

# adk-bootstrap

Opt this repo into the kit. Follow `~/.claude/rules/adk.md` (`## Opt-in`, `## Permissions and environments`, `## Git platforms`) by name; do not restate it.

## Steps

1. If `docs/agents/` exists, stop and tell the user. Never overwrite files.
2. Create `docs/agents/` from the `templates/` next to this file:
   - `AGENTS.md` at the repo root (append the kit section if the file exists).
   - `constitution/{brief,tech-stack,invariants,vocabulary,environments}.md`
   - `status.md`, `lessons.md`
   - empty `specs/` and `brainstorm/` (add `.gitkeep`).
3. Existing project (it has code or history): draft the constitution yourself from the repo. Read README, manifests (`app.json`, `Cargo.toml`, `package.json` and similar), CI config, tests, and `git log`. Fill brief, tech-stack (including real build, test and local publish commands), invariants and vocabulary. Mark guesses as `(unconfirmed)`.
4. New project: ask the user for one-line answers to what the project is, for whom, and the stack. Keep the rest as skeleton.
5. `environments.md`: list no target unless the user names it. Unlisted targets count as customer environments.
6. Ask the user only to confirm the draft, as one summary. Apply corrections, then commit.

## Do not

- Never create `CLAUDE.md`. `AGENTS.md` is read by Claude Code and Copilot.
- Never create `roadmap.md` or `personas.md` by default. Their templates say when to create them; copy one only when that condition holds.
- Invent facts. Leave a heading empty rather than guess.
