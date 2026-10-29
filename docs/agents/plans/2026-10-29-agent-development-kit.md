# Agent Development Kit Implementation Plan

> **For agentic workers:** REQUIRED SUB-SKILL: Use superpowers:subagent-driven-development (recommended) or superpowers:executing-plans to implement this plan task-by-task. Steps use checkbox (`- [ ]`) syntax for tracking.

**Goal:** Build a tool-neutral, spec-driven agent workflow kit (rules, skills, installer, customer-environment guard) that is installed once per machine and serves Claude Code, Copilot in VS Code and Copilot CLI.

**Architecture:** This repo is the single source. Installers link `skills/<name>/` and `rules/adk.md` into user-level tool folders and write two small hook entries that call one guard script. All behavior lives in Markdown (rules and `SKILL.md` files) that every tool reads; the only executable logic is the installers and the guard.

**Tech Stack:** POSIX sh, PowerShell 5.1/7, Python 3.9+ stdlib only (guard, lint, content tests, JSON merge on POSIX), GitHub Actions matrix (ubuntu, macos, windows).

**Spec:** `docs/agents/specs/agent-development-kit.md`

## Global Constraints

- All files in this repo and all files the kit creates in projects are in English. No em dashes. No AI attribution in files, commits or PRs.
- Kit is active only in projects that contain `docs/agents/`; elsewhere it does nothing.
- Never copied into projects; projects receive only outputs under `docs/agents/` plus `AGENTS.md`. No `CLAUDE.md` in projects.
- Skills: `skills/<name>/SKILL.md`, linked into `~/.claude/skills/<name>` and `~/.agents/skills/<name>`. Never into `~/.copilot/skills`.
- Rules: `rules/adk.md`, linked to `~/.claude/rules/adk.md` and `~/.copilot/instructions/adk.instructions.md`. Never modify `~/.claude/CLAUDE.md` or other instruction files.
- Frontmatter: only `name`, `description`, `disable-model-invocation` in `SKILL.md`. No `!cmd` injection, no `context: fork`.
- Windows user-level paths: `%USERPROFILE%\.claude`, `%USERPROFILE%\.copilot`, `%USERPROFILE%\.agents`. Directories via junctions; files via symlink, else hard link, else copy with warning.
- Installers are idempotent, touch only kit-owned entries, and report every change.
- Allowed: `git push`, opening PRs, publishing to local dev environments, agent self-merge (overridable in `AGENTS.md`). Strictly forbidden: publish to or delete on customer environments, and publishing to package registries (`cargo publish`, `npm publish`, AppSource and similar). Any target not in `environments.md` counts as customer.
- Python 3 (stdlib only) is an accepted prerequisite on macOS, Linux and Windows (user decision).
- Model tiers are abstract: large, mid, small. Escalate only after failure; record escalations in the summary.
- Every change ships with tests, validated against the spec before shipping.

## Review Focus

1. A non-kit file or directory already exists at a link target (for example the user's own `~/.claude/skills/adk-spec`): the installer must skip it, report `conflict`, never overwrite, and exit 1. Test: `test_conflict_not_overwritten` (Tasks 3 and 4).
2. A skill is removed or renamed in the repo, or the user uninstalls: stale kit links are pruned, and the 21 third-party skills in `~/.agents/skills` stay untouched. Tests: `test_prune_stale_link`, `test_uninstall_keeps_foreign` (Tasks 3 and 4).
3. Paths with spaces (Windows user names, `Application Support`): installers and guard must work. Tests: `test_home_with_spaces` (Tasks 3 and 4), `test_project_path_with_spaces` (Task 5).
4. Guard receives malformed stdin, or `environments.md` is missing or empty: publish-class commands are denied (fail closed), everything else is allowed. Tests: `test_malformed_input_denies`, `test_missing_environments_denies_publish` (Task 5).
5. Target folders `~/.claude/rules`, `~/.copilot/instructions`, `~/.agents/skills`, `~/.copilot/hooks` do not exist yet: the installer creates them. Test: `test_creates_missing_dirs` (Tasks 3 and 4).

## Scope and phases

The spec covers several subsystems, but they ship as one sequence where each phase is usable on its own:

- **Phase A, verify (Task 1):** record the unverified tool behaviors. Later tasks branch on these results.
- **Phase B, install + rules (Tasks 2 to 4):** after this, the opt-in rules are live in all three tools.
- **Phase C, guard + permissions (Tasks 5 and 6):** customer-environment ban is technically enforced where possible.
- **Phase D, skills (Tasks 7 to 10):** the full workflow.
- **Phase E, platforms, docs, dry run (Tasks 11 and 12).**

Out of this plan, separate later plan: Claude-format plugin marketplace for team distribution (spec section 4, item 7).

## File structure

```
README.md                          install, update, uninstall, opt-in, permissions setup
install.sh                         POSIX installer (macOS, Linux)
install.ps1                        Windows installer
rules/adk.md                       the one rules file
hooks/guard.py                     customer-environment guard (Claude + Copilot hook)
templates/permissions/claude-settings.json   allowlist template (project or user level)
templates/permissions/copilot-cli.md         allow-tool flags / config for Copilot CLI
templates/permissions/vscode-settings.json   auto-approve template for VS Code
skills/adk-bootstrap/SKILL.md      + templates/ (constitution, AGENTS.md, status, lessons, roadmap, personas)
skills/adk-brainstorm/SKILL.md     conversation + routing
skills/adk-do-it/SKILL.md
skills/adk-bugfix/SKILL.md
skills/adk-spec/SKILL.md           + templates/spec.md (spec, design, plan, slicing)
skills/adk-build/SKILL.md          per-slice lanes, cross-review, PR, merge, summary, postmortem
docs/platforms.md                  MCP server per git platform, setup per tool
docs/verification/2026-10-29-tool-behavior.md   Task 1 results
tests/install_test.sh
tests/install_test.ps1
tests/test_guard.py
tests/test_content.py              rules and skills contain what the spec pins
tests/lint_skills.py               frontmatter portability
tests/dryrun/run.sh                token-costing, manual trigger
tests/dryrun/sample/               tiny Python project with docs/agents/
.github/workflows/ci.yml
```

Skill count is a builder decision (spec section 11). Our call: six skills with an `adk-` prefix, so they never collide with Superpowers names. Routing lives inside `adk-brainstorm`; design, plan and slicing live inside `adk-spec`; summary and postmortem live inside `adk-build`.

---

### Task 1: Verify tool behavior

**Files:**
- Create: `docs/verification/2026-10-29-tool-behavior.md`

**Interfaces:**
- Produces: a results table with IDs V1 to V10, each `yes`/`no`/`partial` plus the consequence. Tasks 3, 4, 6 and 12 read V1 to V10 by ID.

Use a throwaway probe skill `adk-probe` (frontmatter `name: adk-probe`, `description: Reply with the word PROBE-OK when asked to run the probe.`) in a temp dir, linked into the real user folders, and remove every probe link afterwards.

- [ ] **Step 1: Run each check on macOS and record method, result, consequence**

| ID | Question | Method |
|---|---|---|
| V1 | Copilot CLI follows a symlinked skill dir in `~/.agents/skills`? | link probe, `copilot` then `/skills` list |
| V2 | VS Code follows symlinked skill dirs in `~/.claude/skills` and `~/.agents/skills`? | link probe into each, check the `/` menu |
| V3 | VS Code with the same skill in `~/.claude/skills` AND `~/.agents/skills`: one entry or two? | link probe into both |
| V4 | Claude Code ignores `~/.agents/skills`? | link probe only there, `/skills` in `claude` |
| V5 | Per-subagent model selection: Claude `Agent` tool `model` param; Copilot CLI and VS Code custom agent `model` field honored? | dispatch a subagent with a small model and ask it to name its model |
| V6 | Copilot CLI `preToolUse` hook: exact stdin JSON shape and the deny output format? | hook that dumps stdin to a file and returns a deny |
| V7 | VS Code reads `~/.copilot/hooks/*.json`; does it also read `~/.claude/settings.json` hooks? | same dumping hook in each location |
| V8 | VS Code applies `~/.copilot/instructions/x.instructions.md` with `applyTo: "**"` to every chat; Claude loads a symlinked `~/.claude/rules/x.md` and ignores `applyTo`? | rules file containing "say RULES-OK first" |
| V9 | Copilot CLI non-interactive run flags (prompt, allow tools, model) for the dry run? | `copilot --help` |
| V10 | Windows: all three tools follow junctions for skills; file symlink/hardlink for rules works? | repeat V1, V2, V4, V8 on a Windows machine |

- [ ] **Step 2: Write consequences**

For each `no`, name the fallback: V1/V2/V10 no means copy mode becomes the default (Task 3/4 step "copy mode"); V3 two entries means the README tells VS Code users to disable one location, or the installer drops `~/.claude/skills` linking for VS Code if a setting allows; V5 no means the tier table in `rules/adk.md` says "inherits session model" for that tool; V6/V7 unknown means the Copilot hook stays instruction-only.

- [ ] **Step 3: Commit**

```bash
git add docs/verification/2026-10-29-tool-behavior.md
git commit -m "docs: record verified tool behavior for kit install"
```

---

### Task 2: Rules file

**Files:**
- Create: `rules/adk.md`
- Create: `tests/test_content.py`

**Interfaces:**
- Produces: `rules/adk.md` with these exact `##` headings in this order: `Opt-in`, `Precedence`, `Workflow`, `Freedoms`, `Prohibitions`, `Principles`, `Stopping and blockers`, `Permissions and environments`, `Git platforms`, `Model and context economy`. Skills reference these headings by name instead of repeating them.
- Produces: `tests/test_content.py` (unittest) with helper `section(path: str, heading: str) -> str`, reused by Tasks 7 to 10.

- [ ] **Step 1: Write `tests/test_content.py::RulesTest`**

```python
class RulesTest(unittest.TestCase):
    def test_frontmatter_applyto_all(self):      # file starts with ---\napplyTo: "**"
    def test_opt_in_is_first_section(self):       # first ## heading == "Opt-in"; text names docs/agents/ and "do nothing"
    def test_headings_in_order(self):             # exact list above
    def test_prohibitions_complete(self):         # all 9 spec section 9 prohibitions present, incl. "weaken, skip or delete tests", "customer environments" and "package registries"
    def test_precedence_names_kit_skills(self):   # mentions adk- skills take precedence in projects with docs/agents/
    def test_tiers_defined(self):                 # "large", "mid", "small" and "escalat" present in Model and context economy
    def test_unlisted_target_is_customer(self):   # Permissions section says unlisted target in environments.md is a customer environment
    def test_no_em_dash(self):                    # "\u2014" not in file
```

- [ ] **Step 2: Run, expect FAIL** `python3 -m unittest tests.test_content -v` (file missing).

- [ ] **Step 3: Write `rules/adk.md`**

Frontmatter: `applyTo: "**"` and a `description`. Content per heading, short and imperative:
- Opt-in: active only if the current repo has `docs/agents/`; otherwise ignore this whole file. Exception: the user asks to bootstrap (then use `adk-bootstrap`).
- Precedence: in opted-in projects, `adk-*` skills take precedence over overlapping skills from other plugins (for example Superpowers brainstorming, writing-plans). Kit storage locations under `docs/agents/` win over any other skill's locations.
- Workflow: read `docs/agents/constitution/` and `docs/agents/lessons.md` first; route via `adk-brainstorm`; resume any work from `docs/agents/status.md`; never read deleted or old specs, code is the truth and git is the history.
- Freedoms, Prohibitions, Principles: spec section 9 verbatim lists.
- Stopping and blockers: spec section 7 (stop only when blocked and nothing else to do; park; batch blockers in `status.md`; never query password managers or bypass confirmations).
- Permissions and environments: spec section 8 allowed and forbidden lists; merge override key in `AGENTS.md` is `merge: human`; `environments.md` format pinned in Task 5.
- Git platforms: detection from `git remote get-url origin`: `github.com` = GitHub; `dev.azure.com` or `visualstudio.com` = Azure DevOps; `codeberg.org` = Forgejo; any other host = Forgejo only if `AGENTS.md` contains `git-platform: forgejo`, else ask once and record it there. PR and merge through that platform's MCP server; missing MCP server = blocker in `status.md`; no PR capability = local merge.
- Model and context economy: spec section 9a; tier table per tool filled from Task 1 V5 (Claude Code: large `opus`, mid `sonnet`, small `haiku`).

- [ ] **Step 4: Run, expect PASS** `python3 -m unittest tests.test_content -v`

- [ ] **Step 5: Commit** `git add rules tests/test_content.py && git commit -m "feat: add kit rules file"`

---

### Task 3: POSIX installer

**Files:**
- Create: `install.sh`, `tests/install_test.sh`

**Interfaces:**
- Produces CLI: `sh install.sh [install|uninstall|status] [--copy]`, default `install`. Targets are under `$HOME` (tests set `HOME` to a temp dir).
- Output: one line per entry, prefix one of `linked`, `ok`, `removed`, `copied`, `conflict`, followed by a space and the target path. Exit 0, or 1 if any `conflict`.
- Kit-owned means: a symlink whose target resolves inside this repo, or (copy mode) a directory or file containing marker `.adk-installed` / first line `<!-- adk-installed -->`.
- Update path: `git pull && sh install.sh` (install prunes stale kit links).
- Task 6 extends `install`/`uninstall` with hook steps; keep link handling in a function `link_entry <source> <target>` so Task 6 can add calls.

- [ ] **Step 1: Write `tests/install_test.sh`** (plain sh, `assert` helper, each test in a fresh `HOME=$(mktemp -d)`)

Tests and assertions:
- `test_install_links_all`: every `skills/*/` has links in `$HOME/.claude/skills/<name>` and `$HOME/.agents/skills/<name>` pointing into the repo; `$HOME/.claude/rules/adk.md` and `$HOME/.copilot/instructions/adk.instructions.md` link to `rules/adk.md`; nothing exists under `$HOME/.copilot/skills`.
- `test_idempotent`: second run prints only `ok` lines.
- `test_creates_missing_dirs`: empty `HOME` works.
- `test_conflict_not_overwritten`: pre-existing real dir `$HOME/.claude/skills/adk-spec` stays byte-identical; output has `conflict`; exit code 1.
- `test_prune_stale_link`: a kit link to `skills/adk-gone` (nonexistent) is removed with `removed`.
- `test_uninstall_keeps_foreign`: foreign skill dir and foreign symlink in `$HOME/.agents/skills` survive `uninstall`; all kit links gone.
- `test_home_with_spaces`: `HOME="$tmp/with space"` passes `test_install_links_all` assertions.
- `test_never_touches_claude_md`: pre-existing `$HOME/.claude/CLAUDE.md` unchanged after install and uninstall.
- `test_copy_mode`: `--copy` creates real dirs with `.adk-installed`; re-run refreshes them; uninstall removes them.

- [ ] **Step 2: Run, expect FAIL** `sh tests/install_test.sh`

- [ ] **Step 3: Implement `install.sh`** with `set -eu`, repo dir from `$(cd "$(dirname "$0")" && pwd)`, quoting every path. If Task 1 V1 or V2 was `no`, make copy mode the default and `--link` the opt-in.

- [ ] **Step 4: Run, expect PASS** `sh tests/install_test.sh`; also `shellcheck install.sh tests/install_test.sh` if available.

- [ ] **Step 5: Commit** `git add install.sh tests/install_test.sh && git commit -m "feat: add POSIX installer"`

---

### Task 4: Windows installer and CI

**Files:**
- Create: `install.ps1`, `tests/install_test.ps1`, `.github/workflows/ci.yml`

**Interfaces:**
- Produces CLI: `install.ps1 [-Action install|uninstall|status] [-Copy] [-UserHome <path>]`, `-UserHome` defaults to `$env:USERPROFILE` (also `$HOME` when not on Windows, so tests run under `pwsh` on macOS/Linux for logic, and natively on Windows for junctions).
- Same output prefixes and exit codes as Task 3. Kit-owned: a junction/symlink resolving into the repo, or the copy markers from Task 3.
- Links: directories via `New-Item -ItemType Junction`; files via `-ItemType SymbolicLink`, on failure `-ItemType HardLink`, on failure copy plus line `copied <path> (re-run install after updates)`. Hard links are recognized as kit-owned by comparing file content with `rules/adk.md` and the marker comment.
- Must run on Windows PowerShell 5.1 (no `??`, no ternary, no `-AsHashtable`).

- [ ] **Step 1: Write `tests/install_test.ps1`** with the same nine test names and assertions as Task 3, plus `test_rules_file_fallback` (simulate symlink failure by a `-NoSymlink` test switch; assert hard link or copy, and the warning line).

- [ ] **Step 2: Run, expect FAIL** `pwsh -File tests/install_test.ps1`

- [ ] **Step 3: Implement `install.ps1`**. If Task 1 V10 was `no`, default to copy mode on Windows.

- [ ] **Step 4: Run, expect PASS** `pwsh -File tests/install_test.ps1`

- [ ] **Step 5: Write `.github/workflows/ci.yml`**: matrix `ubuntu-latest`, `macos-latest`, `windows-latest`. POSIX jobs: `sh tests/install_test.sh`, `python3 -m unittest discover -s tests -v`, `python3 tests/lint_skills.py` (once Task 7 exists). Windows job: `powershell -File tests/install_test.ps1` (5.1) and `pwsh -File tests/install_test.ps1` (7), plus the Python tests. Our call: GitHub Actions, since the repo host is not specified; Forgejo Actions reads the same syntax but usually lacks macOS and Windows runners.

- [ ] **Step 6: Commit** `git add install.ps1 tests/install_test.ps1 .github && git commit -m "feat: add Windows installer and CI matrix"`

---

### Task 5: Customer-environment guard

**Files:**
- Create: `hooks/guard.py`, `tests/test_guard.py`

**Interfaces:**
- Produces: `check(command: str, project_dir: pathlib.Path) -> tuple[bool, str]` returning `(allowed, reason)`.
- Produces CLI: `python3 hooks/guard.py --tool claude|copilot`, reads the hook JSON from stdin, extracts every string value under any key named `command` (any tool name, so Bash, shell and PowerShell tools are all covered), and the working dir from `cwd` (fallback: process cwd). Deny output: Claude: exit 2, reason on stderr. Copilot: the deny format recorded in Task 1 V6, exit 0. Allow: exit 0, no output.
- Pinned `environments.md` format: under the heading `## Allowed targets`, list items whose first backtick literal is the allowed target token, for example ``- `bcdev` local Docker container``.

Rules in `check`:
1. No `docs/agents/` in `project_dir` or any parent up to the git root: allow (opt-in).
2. Command matches no pattern in `PUBLISH_OR_REMOTE_DELETE`: allow.
3. Command matches and contains at least one allowed target token as a substring: allow.
4. Otherwise deny with reason `target not listed in docs/agents/constitution/environments.md; unlisted targets count as customer environments`.

`PUBLISH_OR_REMOTE_DELETE` (case-insensitive regexes, module constant):
`Publish-(BcContainerApp|NAVApp|PerTenantExtension|BcNuGetPackageToContainer)`, `Install-(NAVApp|BcAppFromAppSource)`, `Sync-NAVApp`, `Unpublish-`, `Uninstall-NAVApp`, `Remove-(BcContainer|NAVApp|BcTenant)`, `api\.businesscentral\.dynamics\.com`, `\bssh\b`, `\bscp\b`, `\brsync\b.*:`, `\bInvoke-(RestMethod|WebRequest)\b.*-Method\s+(Delete|Post|Put|Patch)`, `\bcurl\b.*-X\s*(DELETE|POST|PUT|PATCH)`.

Package-registry publishing (user decision, same allow rule: only if the command contains a listed target token, for example a local registry): `\bcargo\s+publish\b`, `\b(npm|pnpm|yarn)\s+(npm\s+)?publish\b`, `\btwine\s+upload\b`, `\bpoetry\s+publish\b`, `\bgem\s+push\b`, `\b(dotnet\s+)?nuget\s+push\b`, `\bdocker\s+push\b`, `\bcpan-upload\b`, `New-AppSourceSubmission`, `api\.partner\.microsoft\.com`.

```python
# ponytail: pattern match on shell commands only; MCP tool calls and obfuscated commands are not
# caught, the rules-file prohibition is the second layer. Extend patterns when a new publish path appears.
```

- [ ] **Step 1: Write `tests/test_guard.py`** (unittest, temp project dirs)

```python
def test_no_docs_agents_allows_everything(self)          # Publish-BcContainerApp -containerName prod -> allowed
def test_plain_command_allowed(self)                     # "cargo test" in opted-in project -> allowed
def test_listed_target_allowed(self)                     # environments lists `bcdev`; "Publish-BcContainerApp -containerName bcdev" -> allowed
def test_unlisted_target_denied(self)                    # "-containerName custprod" -> denied, reason mentions environments.md
def test_missing_environments_denies_publish(self)       # no environments.md -> publish denied, "ls" allowed
def test_ssh_unlisted_host_denied(self)                  # "ssh admin@customer.example" -> denied
def test_remote_delete_denied(self)                      # curl -X DELETE https://api.businesscentral.dynamics.com/... -> denied
def test_registry_publish_denied(self)                   # "cargo publish", "npm publish", "twine upload dist/*" in opted-in project -> denied
def test_appsource_submission_denied(self)               # "New-AppSourceSubmission -appFile x.app" -> denied
def test_listed_local_registry_allowed(self)             # environments lists `localhost:4873`; "npm publish --registry http://localhost:4873" -> allowed
def test_registry_dry_run_still_denied(self)             # "cargo publish --dry-run" -> denied (ponytail: no flag parsing; user runs it by hand)
def test_project_path_with_spaces(self)                  # project dir "my project" works
def test_cli_claude_deny_exit_2(self)                    # subprocess, Claude JSON shape, exit 2, stderr has reason
def test_cli_copilot_deny_format(self)                   # subprocess, Copilot JSON shape from V6, deny payload
def test_malformed_input_denies(self)                    # stdin "not json" -> deny (fail closed), Claude exit 2
def test_nested_command_key(self)                        # {"tool_input": {"command": "..."}} and {"toolArgs": {"command": "..."}} both found
```

- [ ] **Step 2: Run, expect FAIL** `python3 -m unittest tests.test_guard -v`
- [ ] **Step 3: Implement `hooks/guard.py`** (stdlib only, Python 3.9 compatible).
- [ ] **Step 4: Run, expect PASS** same command.
- [ ] **Step 5: Commit** `git add hooks tests/test_guard.py && git commit -m "feat: add customer-environment guard hook"`

---

### Task 6: Hook wiring and permission templates

**Files:**
- Modify: `install.sh`, `install.ps1`, `tests/install_test.sh`, `tests/install_test.ps1`
- Create: `templates/permissions/claude-settings.json`, `templates/permissions/copilot-cli.md`, `templates/permissions/vscode-settings.json`
- Modify: `tests/test_content.py` (add `PermissionTemplatesTest`)

**Interfaces:**
- Consumes: `hooks/guard.py` CLI from Task 5; `link_entry` from Tasks 3/4.
- Installer writes (not links, because it embeds absolute paths) `~/.copilot/hooks/adk-guard.json` that runs `<python> <repo>/hooks/guard.py --tool copilot` on `preToolUse`, in the schema recorded in Task 1 V6. Owned by the kit via key `"adk": true` or a filename check.
- Installer merges one `PreToolUse` hook entry into `~/.claude/settings.json` (matcher for shell tools, command `<python> <repo>/hooks/guard.py --tool claude`, plus marker field `"adk": true` if Claude tolerates unknown keys, otherwise identify by the command path). Before the first change it writes `settings.json.adk-backup`. Uninstall removes only that entry. POSIX merge via `python3 -c` with stdlib `json`; Windows via `ConvertFrom-Json`/`ConvertTo-Json -Depth 20`.
- `<python>`: absolute path of `python3` (POSIX) or `py -3`/`python` (Windows), resolved at install time. Missing Python: print `conflict hooks (python 3 not found)` and exit 1; links are still installed.
- Spec gap noted: spec section 4 says installers touch only the kit's links; editing `~/.claude/settings.json` is the only user-level way to register a Claude hook outside a plugin, and the spec requires the hard block. Our call: merge one marked entry with a backup.

- [ ] **Step 1: Extend install tests**: `test_hooks_written` (Copilot hook file exists, references repo guard path), `test_claude_settings_merged_once` (two installs, exactly one guard entry, other existing keys and hooks preserved), `test_uninstall_removes_only_guard_entry`, `test_backup_created`, plus the PowerShell equivalents.
- [ ] **Step 2: Write `PermissionTemplatesTest`**: `claude-settings.json` is valid JSON, `permissions.allow` contains `Bash(git push:*)`, `Bash(git commit:*)`, `Bash(al-runner:*)`, `Bash(cargo test:*)`; `permissions.deny` contains entries for `Publish-PerTenantExtension`, `Unpublish-`, `cargo publish` and `npm publish`; no allow entry matches any `PUBLISH_OR_REMOTE_DELETE` pattern (import from `hooks/guard.py`). `vscode-settings.json` valid JSON and contains the terminal auto-approve key with the same deny entries. `copilot-cli.md` lists the allow-tool flags from V9 and the matching deny flags.
- [ ] **Step 3: Run, expect FAIL** `sh tests/install_test.sh && python3 -m unittest tests.test_content -v`
- [ ] **Step 4: Implement** installer changes and the three templates. Templates are applied by the user per project or user level as the README explains; installers do not apply them.
- [ ] **Step 5: Run, expect PASS** all install tests on macOS plus `pwsh -File tests/install_test.ps1`; CI covers Windows.
- [ ] **Step 6: Commit** `git commit -am "feat: wire guard hooks and add permission templates"` (add new files first).

---

### Task 7: Skill lint and adk-bootstrap

**Files:**
- Create: `tests/lint_skills.py`, `skills/adk-bootstrap/SKILL.md`, `skills/adk-bootstrap/templates/{AGENTS.md,brief.md,tech-stack.md,invariants.md,vocabulary.md,environments.md,status.md,lessons.md,roadmap.md,personas.md}`
- Modify: `tests/test_content.py` (add `BootstrapTest`)

**Interfaces:**
- Produces: `lint_skills.py` exit 0 when clean, else prints `<path>: <problem>` lines and exits 1. Rules: frontmatter keys subset of `{name, description, disable-model-invocation}`; `name` equals folder name and matches `^[a-z0-9-]{1,64}$`; `description` 1 to 1024 chars; body has no line starting with `` !` `` and no `context:` key; no em dash anywhere under `skills/`.
- Produces: the template files that `adk-build` and `adk-spec` later write into. `status.md` template has headings `## Active`, `## Done`, `## Parked`, `## Blockers for the user`. `environments.md` template follows the format pinned in Task 5. `AGENTS.md` template points to `docs/agents/`, lists overrides `merge: agent|human`, `git-platform:` and nothing else.

- [ ] **Step 1: Write lint self-test** `tests/test_lint.py`: fixtures in a temp dir; `test_extra_key_rejected` (`model:`), `test_name_mismatch_rejected`, `test_bang_injection_rejected`, `test_clean_skill_passes`.
- [ ] **Step 2: Write `BootstrapTest`**: `adk-bootstrap` description mentions bootstrap / opt in; body says it creates `docs/agents/`, drafts the constitution from the existing repo for existing projects, asks the user only to confirm the draft, creates no `CLAUDE.md`, and does not create roadmap or personas by default; all ten templates exist; roadmap and personas templates each start with a one-line "Create when" condition from spec section 5.
- [ ] **Step 3: Run, expect FAIL** `python3 -m unittest tests.test_lint tests.test_content -v`
- [ ] **Step 4: Implement** `lint_skills.py` and `adk-bootstrap` (`disable-model-invocation: true`, so it runs only on request).
- [ ] **Step 5: Run, expect PASS** plus `python3 tests/lint_skills.py`.
- [ ] **Step 6: Commit** `git add skills tests && git commit -m "feat: add skill lint and adk-bootstrap"`

---

### Task 8: adk-brainstorm, adk-do-it, adk-bugfix

**Files:**
- Create: `skills/adk-brainstorm/SKILL.md`, `skills/adk-do-it/SKILL.md`, `skills/adk-bugfix/SKILL.md`
- Modify: `tests/test_content.py` (add `FrontEndSkillsTest`)

**Interfaces:**
- Consumes: rules headings (Task 2), templates (Task 7).
- Produces: routing outcomes `adk-do-it`, `adk-bugfix`, `adk-spec` named exactly so.

Each skill must contain:
- adk-brainstorm: read constitution and `lessons.md` first; user describes problem not solution; agent asks one question at a time, challenges assumptions, explores alternatives, surfaces contradictions; record in `docs/agents/brainstorm/<slug>.md` and resume from it; routing criteria from spec section 6 step 2 (spec only when it binds architecture, carries business logic, or spans parts that must ship in order); hand off to the chosen skill.
- adk-do-it: no spec; implement, run tests from `tech-stack.md`, summarize (what changed, tests run and result, decisions made); PR and merge per rules; mid tier.
- adk-bugfix: reproduction test first, show it fails, then fix, show it passes; never alter the repro test to pass; summary; PR and merge per rules.

- [ ] **Step 1: Write `FrontEndSkillsTest`** asserting the phrases above (for example `brainstorm/` path, the three routing names, "reproduction test" before "fix" in adk-bugfix, "no spec" in adk-do-it) and that each skill references the rules file by heading instead of restating the prohibitions list.
- [ ] **Step 2: Run, expect FAIL**.
- [ ] **Step 3: Write the three skills.**
- [ ] **Step 4: Run, expect PASS** plus lint.
- [ ] **Step 5: Commit** `git commit -m "feat: add brainstorm, do-it and bugfix skills"`

---

### Task 9: adk-spec

**Files:**
- Create: `skills/adk-spec/SKILL.md`, `skills/adk-spec/templates/spec.md`
- Modify: `tests/test_content.py` (add `SpecSkillTest`)

**Interfaces:**
- Produces: `docs/agents/specs/<slug>.md` with headings `## Intent`, `## Must`, `## Must not`, `## Acceptance`, `## Design` (subsections `### Context`, `### Graph`, `### Acceptance checks`), `## Slices` (ordered, each with an id `S1`, `S2`, ...). The plan is transient: kept in the session, not written to the repo. `status.md` gets one `## Active` line per slice: `- [ ] <slug>/S<n>: <title>`. `adk-build` consumes exactly these.

Skill must contain: spec states intent, must/must-not, acceptance; never layout, wording or how; unsaid means implementer's call; design produces context, graph, acceptance checks; slicing into independently runnable and testable slices; a review loop after each of spec, design, plan, slicing (reviewer flags violations only, never invents obligations, upstream decisions not re-debated); review-loop limit (our call: 3 rounds, then park with a note); a few-line summary to the user instead of the spec; large tier for producing and reviewing.

- [ ] **Step 1: Write `SpecSkillTest`** (template headings exact; skill text contains "must not", "acceptance", "never" + "how", "review", "3", "status.md", "summary").
- [ ] **Step 2: Run, expect FAIL.**
- [ ] **Step 3: Write skill and template.**
- [ ] **Step 4: Run, expect PASS** plus lint.
- [ ] **Step 5: Commit** `git commit -m "feat: add spec skill"`

---

### Task 10: adk-build

**Files:**
- Create: `skills/adk-build/SKILL.md`
- Modify: `tests/test_content.py` (add `BuildSkillTest`)

**Interfaces:**
- Consumes: spec format and `status.md` lines from Task 9; platform detection and merge rules from Task 2.
- Produces: per-slice PR; on the last slice of a spec, the summary and the postmortem entry in `lessons.md`, then deletion of the spec file.

Skill must contain, in order:
1. Resume: pick the first unchecked, unparked slice in `status.md`; if none and blockers exist, stop and present the batched blocker list.
2. Fresh subagent per slice with minimal context (its slice, contracts, relevant constitution parts); lean orchestrator holds only summaries and file pointers.
3. Contracts (signatures, data shapes, error cases) with review; they produce a skeleton.
4. Code lane and test lane as separate subagents, test lane instructed not to read the implementation and to write against acceptance and contracts; each reviewed. Sequential fallback when a tool cannot run them in parallel.
5. Run tests with the commands from `tech-stack.md`.
6. Analyze failure: code, test or spec; spec fault becomes a parked question.
7. Give-up rule (our call: 3 failed attempts on the same problem), honest note, park, continue.
8. Cross-review: code vs spec, tests vs spec, code vs tests.
9. One PR per slice via the platform MCP server; merge unless `AGENTS.md` says `merge: human`; check the slice off in `status.md`.
10. Last slice: summary per spec (built, tested with results, open or parked, decisions made by the agent, tier escalations), postmortem to `lessons.md`, delete the spec.
11. Tiers: mid for lanes, large for review and failure analysis, small for status updates; escalate only after failure.
12. In Copilot, after each slice, tell the user to type "continue" to run the next (spec section 7).

- [ ] **Step 1: Write `BuildSkillTest`** (each of the 12 items has a distinguishing phrase; assert "code vs spec", "tests vs spec", "code vs tests", "lessons.md", "merge: human", "continue", "delete").
- [ ] **Step 2: Run, expect FAIL.**
- [ ] **Step 3: Write the skill.**
- [ ] **Step 4: Run, expect PASS** plus lint.
- [ ] **Step 5: Commit** `git commit -m "feat: add build skill"`

---

### Task 11: Platform docs and README

**Files:**
- Create: `docs/platforms.md`, `README.md`
- Modify: `tests/test_content.py` (add `DocsTest`)

Content:
- `docs/platforms.md`: one section each for GitHub, Azure DevOps, Forgejo (self-hosted and codeberg.org): which MCP server (verify current names at write time, candidates: `github/github-mcp-server`, `microsoft/azure-devops-mcp`, a Forgejo MCP server), how to register it in Claude Code, Copilot CLI and VS Code, and the token scopes needed for PR create and merge.
- `README.md`: what the kit is (link to spec), install/update/uninstall on macOS, Linux, Windows, opt-in via `adk-bootstrap`, applying the permission templates, Task 1 caveats (V3 duplicate handling, copy mode), Python 3.9+ needed for the guard.

- [ ] **Step 1: Write `DocsTest`**: `platforms.md` has the three platform headings and mentions all three tools under each; README contains `install.sh`, `install.ps1`, `uninstall`, `git pull`, `adk-bootstrap`, `docs/agents/`.
- [ ] **Step 2: Run, expect FAIL.** **Step 3: Write docs.** **Step 4: Run, expect PASS.**
- [ ] **Step 5: Commit** `git commit -m "docs: add platform setup and README"`

---

### Task 12: Dry run per tool

**Files:**
- Create: `tests/dryrun/run.sh`, `tests/dryrun/sample/` (Python package `calc.py` with `add`, `tests/test_calc.py`, `docs/agents/` filled from the templates, `environments.md` listing `localhost`), `tests/dryrun/sample-optout/` (same code, no `docs/agents/`), `tests/dryrun/MANUAL-VSCODE.md`

**Interfaces:**
- `run.sh claude|copilot` copies the sample to a temp git repo, runs the tool non-interactively (Claude: `claude -p`; Copilot: flags from Task 1 V9) with the prompt "Use adk-do-it: add a function subtract(a, b) to calc.py with tests.", then asserts. Not in CI (costs tokens); run before every release.

Assertions:
- `dry_do_it`: `python3 -m unittest` passes in the temp repo; `subtract` exists; a test for it exists; no `CLAUDE.md` created; no new file outside `calc.py`, `tests/`, `docs/agents/`.
- `dry_opt_out`: in `sample-optout`, prompt "Bootstrap is not requested. Add subtract." leaves no `docs/agents/` behind.
- `dry_guard`: prompt to run `Publish-BcContainerApp -containerName custprod` is blocked (Claude: hook output in transcript; Copilot: per V6/V7, otherwise refusal by instruction).
- `MANUAL-VSCODE.md`: the same three scenarios as a five-minute checklist.

- [ ] **Step 1: Write `run.sh` and fixtures.**
- [ ] **Step 2: Run** `sh tests/dryrun/run.sh claude` and `sh tests/dryrun/run.sh copilot`; expected: all three assertions PASS. Run the VS Code checklist by hand and record the result in the PR.
- [ ] **Step 3: Commit** `git add tests/dryrun && git commit -m "test: add per-tool dry run"`

---

## Requirement to test mapping

| Spec requirement | Test(s) |
|---|---|
| S4 install once, single source, per-skill links in `~/.claude/skills` and `~/.agents/skills`, none in `~/.copilot/skills` | `test_install_links_all` (sh, ps1) |
| S4 rules linked to both rule locations; `CLAUDE.md` untouched | `test_install_links_all`, `test_never_touches_claude_md` |
| S4 idempotent, reports changes, touches only kit entries | `test_idempotent`, `test_conflict_not_overwritten`, `test_uninstall_keeps_foreign` |
| S4 uninstall and update path | `test_uninstall_keeps_foreign`, `test_prune_stale_link` |
| S4 Windows junctions, symlink/hardlink/copy fallback | `install_test.ps1` on `windows-latest`, `test_rules_file_fallback` |
| S4 tested on three OS | `ci.yml` matrix |
| S4 portable frontmatter only | `lint_skills.py`, `test_lint.py` |
| S4 verify-first list | Task 1 record V1 to V10 |
| S4/S8 hooks required for customer ban where supported | `test_hooks_written`, `test_claude_settings_merged_once`, `dry_guard` |
| S5 opt-in via `docs/agents/` | `test_opt_in_is_first_section`, `test_no_docs_agents_allows_everything`, `dry_opt_out` |
| S5 project layout, no `CLAUDE.md`, roadmap/personas on demand, bootstrap drafts from code | `BootstrapTest`, `dry_do_it` |
| S5 done specs deleted | `BuildSkillTest` ("delete") |
| S6 conversation, routing, three paths | `FrontEndSkillsTest` |
| S6 bugfix repro first | `FrontEndSkillsTest` |
| S6 spec intent only, design artifacts, slicing, review loops | `SpecSkillTest` |
| S6 per-slice contracts, separate lanes, test lane blind, run tests, analyze failure, give-up | `BuildSkillTest` |
| S6 cross-review, PR per slice, summary per spec, postmortem | `BuildSkillTest` |
| S7 stop only when blocked, batched blockers, secrets stay with user, Copilot "continue" | `RulesTest` (Stopping section), `BuildSkillTest` |
| S8 allowed / forbidden actions, merge override, allowlist | `RulesTest`, `test_guard.py`, `PermissionTemplatesTest` |
| S8/S9 package-registry publishing blocked like customer environments | `test_registry_publish_denied`, `test_appsource_submission_denied`, `test_listed_local_registry_allowed`, `test_prohibitions_complete` |
| S4 Python 3 stdlib prerequisite | `ci.yml` runs guard and lint with stock Python on all three OS; `test_hooks_written` (missing-Python path prints `conflict`) |
| S8 permission allowlist templates | `PermissionTemplatesTest` |
| S8 platform detection, MCP per platform, missing MCP is a blocker | `RulesTest` (Git platforms), `DocsTest` |
| S9 freedoms, prohibitions, principles, precedence | `RulesTest` |
| S9a tiers, escalation, lean orchestrator, minimal context | `RulesTest` (`test_tiers_defined`), `BuildSkillTest` items 2 and 11 |
| S10 no Superpowers dependency, works in Copilot | `lint_skills.py` (no Claude-only features), `dry_do_it` under Copilot |
| S11 dry run per tool | Task 12 |

Gaps, justified:
- Notification of the batched blocker list (spec leaves to builder): v1 notifies by the agent's final message only; no test. Add when a tool-specific push mechanism is chosen.
- Concrete model per tier in Copilot: depends on V5; covered by `test_tiers_defined` only at the abstract level.
- Plugin marketplace: separate later plan.
