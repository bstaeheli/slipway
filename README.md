# Agent development kit

Skills, a rules file and a guard hook that make coding agents (Claude Code, Copilot CLI, VS Code Copilot) work spec-first with contracts, test lanes, review and one PR per slice. Design: [docs/agents/specs/agent-development-kit.md](docs/agents/specs/agent-development-kit.md).

Skills: `adk-bootstrap` (opt a repo in), `adk-brainstorm` (front door), `adk-do-it` (small change), `adk-bugfix` (test-first fix), `adk-spec` (spec and slices), `adk-build` (build slices, PRs, summary).

## Requirements

- Python 3.9+ (stdlib only) on macOS, Linux and Windows: the installer's hook step and the guard need it.
- Git. PR work needs a platform MCP server, see [docs/platforms.md](docs/platforms.md).

## Install, update, uninstall

macOS and Linux:

```sh
git clone <this repo> && cd agent-development-kit
sh install.sh            # also: sh install.sh status | uninstall
```

Windows (PowerShell 5.1+):

```powershell
powershell -ExecutionPolicy Bypass -File .\install.ps1            # also: status | uninstall, -Copy
```

The default execution policy blocks `.\install.ps1`; `-ExecutionPolicy Bypass` applies to this process only and changes no system setting. With PowerShell 7 use `pwsh -ExecutionPolicy Bypass -File .\install.ps1`.

The installer links `skills/*` into `~/.claude/skills` and `~/.agents/skills`, links `rules/adk.md` to `~/.claude/rules/adk.md` and `~/.copilot/instructions/adk.instructions.md`, and registers `hooks/guard.py` as a pre-tool hook in `~/.claude/settings.json` and `~/.copilot/hooks/adk-guard.json`. It never overwrites foreign files: it prints `conflict <path>` and exits 1. Other output lines are `linked`, `copied`, `ok`, `removed`.

- Before its first change it writes `~/.claude/settings.json.adk-backup`. The merge re-indents settings.json, normalizes number spelling and collapses duplicate keys. Values stay equal; the backup has the original.
- Link mode is the default. `--copy` (`install.sh`) or `-Copy` (`install.ps1`) copies instead, marked so it can be removed later; re-run the install after updates.
- Windows: directories are junctions, the rules file is a symbolic link (needs Developer Mode or elevation), else a marked copy, so re-run install after `git pull`. No hard links.
- Moved the kit or changed Python: re-run install. Deleting the kit: run uninstall first.
- Update: `git pull`, then re-run the installer. Uninstall: `sh install.sh uninstall` / `powershell -ExecutionPolicy Bypass -File .\install.ps1 uninstall`.

## Opt in per repo

The kit acts only in repos that have `docs/agents/`. To create it (constitution, status, lessons), type `/adk-bootstrap`; the agent cannot start it by itself. Elsewhere the rules and skills do nothing.

## Guard

In opted-in repos, `hooks/guard.py` denies shell commands that publish to or delete on customer environments (Business Central publish cmdlets, ssh/scp, mutating curl and web requests) and package registry publishes (cargo, npm, PyPI, NuGet, docker push, gem, AppSource) unless the target is listed under `## Allowed targets` in `docs/agents/constitution/environments.md`. It is a second layer on top of the rules file, not a guarantee: it matches shell commands only, so MCP tool calls and obfuscated commands are not caught.

## Permission templates

In `templates/permissions/`: `claude-settings.json` (merge `permissions` into `.claude/settings.json` or `~/.claude/settings.json`), `vscode-settings.json` (merge into `.vscode/settings.json` or user settings), `copilot-cli.md` (flags for `copilot`).

## Git platforms

GitHub, Azure DevOps and Forgejo: MCP server names, registration and token scopes in [docs/platforms.md](docs/platforms.md).

## Known caveats

Not yet verified by hand (checklists in [docs/verification/2026-10-29-tool-behavior.md](docs/verification/2026-10-29-tool-behavior.md)):

- VS Code: whether it follows symlinked skills, reads the hook in `~/.copilot/hooks/`, and applies the rules file. If skills do not appear, use `--copy` / `-Copy`.
- VS Code reads both `~/.claude/skills` and `~/.agents/skills`, so each skill may show twice. Harmless; disable one location in VS Code if it bothers you.
- Windows junctions, the Copilot CLI `powershell` hook key, and whether Claude Code runs hook commands through Git Bash on Windows.
