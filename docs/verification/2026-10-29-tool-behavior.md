# Tool behavior verification (2026-10-29)

Run on macOS with Claude Code 2.1.306 and GitHub Copilot CLI 1.0.48. Probe skill `adk-probe`
(description: "Reply with the word PROBE-OK when asked to run the probe.") lived in a scratch dir
and was linked into the real user folders only for the duration of each check; every probe entry
was removed afterwards. VS Code and Windows were not available, so those items are
`pending manual` with a checklist and the expected result per current official docs.

## Results

| ID | Result | Method | Evidence | Consequence |
|---|---|---|---|---|
| V1 | yes | Symlinked `adk-probe` into `~/.agents/skills`, ran `copilot -p ... --log-level debug`, inspected the request payload | `<available_skills>` contained `adk-probe` with the exact description, `<location>user</location>`. Control without the link: `NONE` | Link mode works for Copilot CLI on macOS/Linux. |
| V2 | pending manual | Not runnable here (VS Code GUI) | Docs list `~/.claude/skills/`, `~/.agents/skills/`, `~/.copilot/skills/` as personal skill locations (https://code.visualstudio.com/docs/copilot/customization/agent-skills); symlink following is not stated | Default: link mode. If VS Code does not follow symlinks, copy mode becomes the default for VS Code. |
| V3 | pending manual | Not runnable here | Docs list both locations; dedup behavior not stated | Default: assume two entries. README tells VS Code users to disable one location, or the installer skips `~/.claude/skills` linking when only VS Code is targeted and a setting allows. |
| V4 | yes | Link only in `~/.agents/skills`; `claude -p --model haiku` asked to quote the skill description | `NONE`. Control: same link in `~/.claude/skills` returned the exact description (so Claude Code also follows symlinked skill dirs) | Claude Code needs `~/.claude/skills`; no double-listing risk from `~/.agents/skills`. |
| V5 | yes (Claude, Copilot CLI); pending manual (VS Code) | Claude: `claude -p --model haiku` called `Agent` with `model: sonnet`. Copilot: custom agent `.github/agents/probe.agent.md` with `model: gpt-4.1`, run with `--agent probe`, default model is `gpt-5.3-codex` | Claude: `PARENT=claude-haiku-5-5`, `SUBAGENT=claude-sonnet-5-5`. Copilot debug log: request `"model": "gpt-4.1"` for the agent run | Tier table can name per-subagent models for Claude and Copilot CLI. VS Code custom agent `model` field unverified; fall back to "inherits session model" in `rules/adk.md` for VS Code if the manual check fails. |
| V6 | yes | `~/.copilot/hooks/adk-probe.json` with a `preToolUse` command hook that dumps stdin and prints a deny; prompt "run echo hello" with `--allow-tool='shell(echo)'` | Config: `{"version":1,"hooks":{"preToolUse":[{"type":"command","bash":"<script>","timeoutSec":10}]}}`. Stdin: `{"sessionId":"...","timestamp":1793292027018,"cwd":"...","toolName":"bash","toolArgs":{"command":"echo hello","description":"...","mode":"sync","initial_wait":30}}` (toolArgs is an object, camelCase keys, shell tool name is `bash`). Deny output `{"permissionDecision":"deny","permissionDecisionReason":"ADK-PROBE-DENY"}` on stdout, exit 0: the command did not run and the model reported the reason | Copilot hook can be a real enforcement hook, not instruction-only. Parse `toolName` and `toolArgs.command`. Other exit-code/output variants were not tested. |
| V7 | pending manual | Not runnable here | Docs: VS Code reads `~/.copilot/hooks/` and `~/.copilot/settings.json`, plus repo `.claude/settings.json`; user-level `~/.claude/settings.json` is not mentioned (https://code.visualstudio.com/docs/copilot/customization/hooks) | Default: install the Copilot hook in `~/.copilot/hooks/` only. If VS Code does not read it, Copilot hook stays instruction-only for VS Code. |
| V8 | partial | Claude half: symlinked `~/.claude/rules/adk-probe.md` (frontmatter `applyTo: "**"`, body "Say RULES-OK as the first word of every reply"), `claude -p --model haiku "What is 2+2?"`. VS Code half pending manual | Claude reply `RULES-OK 4`: the symlinked rule loads and `applyTo` is ignored (rule applies unconditionally). Docs list `~/.copilot/instructions` and `~/.claude/rules` for VS Code (https://code.visualstudio.com/docs/copilot/customization/custom-instructions) | One rules source can serve Claude via symlink. VS Code `applyTo` behavior to be confirmed manually. |
| V9 | yes | `copilot --help` | Non-interactive: `-p/--prompt <text>`, `-s/--silent` (response only), `--model <m>`, `--allow-tool[=tools...]` (e.g. `shell(echo)`), `--allow-all-tools` (needed for unattended tool use), `--available-tools[=tools...]`, `--agent <name>`, `--output-format json`, `--log-level`, `--log-dir`, `-C <dir>` | Dry run: `copilot -p "<prompt>" -s --model <m> --allow-tool='shell(...)'`. Use `--allow-all-tools` only where the user accepts it. Model availability varies (`gpt-5-mini`, `gpt-5.4-mini` were rejected; `gpt-4.1` worked intermittently), so do not hard-code a model for the dry run. |
| V10 | pending manual | Not runnable here (no Windows machine) | Docs only: mklink and New-Item describe junctions, symlinks and hardlinks (https://learn.microsoft.com/windows-server/administration/windows-commands/mklink); tool behavior unverified | Default: link mode. If junctions fail for any tool, copy mode becomes the Windows default (Task 3/4 "copy mode"). |

## Manual checklists

V2/V3 (VS Code, macOS or Windows):
1. Link `adk-probe` into `~/.claude/skills/` only; open Copilot Chat, type `/`, note whether `adk-probe` is listed. Repeat with `~/.agents/skills/` only.
2. Link into both; count the `adk-probe` entries in the `/` menu (one = V3 no, two = V3 yes).
3. Remove the links.

Expected (V2): `adk-probe` is listed for each location. Docs list all three skill folders but do not state symlink handling, so symlink following stays unconfirmed. Expected (V3): docs do not state dedup, so two entries is the working assumption; one entry would confirm dedup.

V7 (VS Code):
1. Put the dumping deny hook from V6 in `~/.copilot/hooks/adk-probe.json`; in Agent mode ask to run `echo hello`; check whether the dump file appears.
2. Repeat with the same hook in `~/.claude/settings.json` under `hooks.PreToolUse` (back the file up first).

Expected (V7): step 1 dumps the file and the command is denied (documented). Step 2 produces no dump (user-level `~/.claude/settings.json` is not documented as read; only repo `.claude/settings.json`). Whether VS Code honors it anyway stays unconfirmed.

V8 (VS Code half):
1. Create `~/.copilot/instructions/adk-probe.instructions.md` with frontmatter `applyTo: "**"` and body "say RULES-OK first".
2. Start a new chat in an unrelated folder; confirm the reply starts with RULES-OK. Remove the file.

Expected (V8 VS Code): reply starts with RULES-OK, since `~/.copilot/instructions` is a documented location and `applyTo: "**"` matches every file. Whether it applies to chats with no file context stays unconfirmed.

V5 (VS Code half):
1. Create a `*.agent.md` with `model:` set to a model different from the picker's current model; run it and check the model shown in the chat response details. Pick `GPT-4.1` (or any model that differs from the picker) for `model:`.

Expected (V5 VS Code): the response details show the model named in `model:`, not the picker's model (the custom agent `model` field is documented in https://code.visualstudio.com/docs/copilot/customization/custom-agents). Availability of the chosen model on the user's plan stays unconfirmed.

V10 (Windows, PowerShell):
1. Create junctions with `New-Item -ItemType Junction` for `adk-probe` in `~/.claude/skills` and `~/.agents/skills`; repeat V1, V2, V4.
2. Create a file symlink (needs Developer Mode or elevation) or hardlink for `~/.claude/rules/adk-probe.md`; repeat V8 Claude half.

Expected (V10): junctions work without elevation and are followed as directories; file symlinks need Developer Mode or elevation, hardlinks do not (https://learn.microsoft.com/windows-server/administration/windows-commands/mklink, https://learn.microsoft.com/powershell/module/microsoft.powershell.management/new-item). Whether each tool follows them stays unconfirmed.

## Defaults for downstream tasks until manual checks are done

- Install mode: link (copy mode remains the fallback for any tool/OS where V2 or V10 comes back no).
- V3: assume two entries in VS Code (document the workaround in the README).
- Copilot hook: implement a real `preToolUse` hook in `~/.copilot/hooks/` per the V6 shapes above; also keep the instruction text as the fallback for VS Code until V7 is confirmed.
- Tier table in `rules/adk.md`: name models for Claude and Copilot CLI; VS Code custom agents named too but marked unverified.

## Cleanup

Probe entries removed and verified by `ls`: `~/.claude/skills/adk-probe`, `~/.agents/skills/adk-probe`, `~/.claude/rules/adk-probe.md` (the `rules` dir did not exist before and was removed), `~/.copilot/hooks/adk-probe.json` (the `hooks` dir did not exist before and was removed). Stray files remain only in the scratchpad.
