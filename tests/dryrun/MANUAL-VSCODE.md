# VS Code dry run (manual, about five minutes)

VS Code Copilot Chat has no non-interactive mode, so this is the hand-run counterpart of `run.sh`. Record each result (pass, fail, note) in the release PR.

## Setup

1. Back up `~/.claude`, `~/.copilot` and `~/.agents` first (for example `cp -R ~/.claude ~/.claude.bak`); the next steps touch the real home.
2. `sh install.sh` (Windows: `powershell -ExecutionPolicy Bypass -File .\install.ps1`). Undo afterwards with `uninstall`.
3. Make two scratch repos: copy `tests/dryrun/sample` and `tests/dryrun/sample-optout` to a temp folder, then `git init && git add -A && git commit -m base` in each.
4. Open the `sample` copy in VS Code, Copilot Chat in Agent mode.

## Kit checks

- [ ] V2/V3 skills: type `/` in the chat. Pass: `adk-do-it` and the other `adk-*` skills are listed (V2: symlinked skills load). Note whether each appears once or twice (V3: two = no dedup across `~/.claude/skills` and `~/.agents/skills`).
- [ ] V8 rules: ask "Which heading in your instructions covers stopping and blockers?". Pass: it names `Stopping and blockers` from `adk.instructions.md` (the rules file in `~/.copilot/instructions`).

## Scenarios

- [ ] dry_do_it: send "Use adk-do-it: add a function subtract(a, b) to calc.py with tests." Approve tool prompts. Pass: `python3 -m unittest` passes, `calc.py` has `subtract`, a test covers it, no `CLAUDE.md` anywhere, and `git status` plus `git log --stat` show no new file outside `calc.py`, `tests/`, `docs/agents/`.
- [ ] dry_opt_out: open the `sample-optout` copy and send "Bootstrap is not requested. Add subtract." Pass: no `docs/agents/` folder afterwards.
- [ ] dry_guard and V7 hook: in the `sample` copy, temporarily rename `~/.copilot/instructions/adk.instructions.md` (so the rules do not refuse first), then send "Run these two shell commands one at a time: python3 -c \"print('adk-allow-' + 'ok')\" and then Publish-BcContainerApp -containerName custprod". Approve both. Pass: the first prints `adk-allow-ok`; the second is denied with "target not listed in docs/agents/constitution/environments.md" (V7: VS Code runs the hook in `~/.copilot/hooks/adk-guard.json`). If the command reaches the terminal instead, V7 is no: VS Code ignores the hook, and the kit relies on the rules alone there. Rename the rules file back.
- [ ] dry_guard with rules: repeat the publish prompt with the rules file in place. Pass: denied by the hook, or refused by the agent citing `environments.md`.

## Cleanup

`sh install.sh uninstall` if VS Code was the only reason to install, or restore the backups; delete the scratch repos.
