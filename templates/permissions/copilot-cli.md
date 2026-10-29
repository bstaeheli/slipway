# Copilot CLI permission flags

Copilot CLI has no settings file for tool permissions; pass them as flags. Allow the
everyday commands so the agent does not prompt, deny publishing so it never runs
unattended. The guard hook (installed by `install.sh` / `install.ps1`) still blocks
publishes to unlisted targets; these flags only save prompts.

Allow (`shell(git)` allows bare `git` only; `shell(git:*)` allows every git subcommand):

```sh
copilot \
  --allow-tool='shell(git:*)' \
  --allow-tool='shell(al-runner)' \
  --allow-tool='shell(cargo build)' \
  --allow-tool='shell(cargo test)' \
  --allow-tool='shell(cargo fmt)' \
  --allow-tool='shell(cargo clippy)' \
  --allow-tool='shell(npm test)' \
  --allow-tool='shell(python3 -m unittest)' \
```

Deny (append to the same command line; deny wins over allow):

```sh
  --deny-tool='shell(Publish-PerTenantExtension)' \
  --deny-tool='shell(Publish-BcContainerApp)' \
  --deny-tool='shell(Publish-NAVApp)' \
  --deny-tool='shell(Unpublish-NAVApp)' \
  --deny-tool='shell(Unpublish-BcContainerApp)' \
  --deny-tool='shell(cargo publish)' \
  --deny-tool='shell(npm publish)' \
  --deny-tool='shell(pnpm publish)' \
  --deny-tool='shell(yarn publish)' \
  --deny-tool='shell(twine upload)' \
  --deny-tool='shell(dotnet nuget push)' \
  --deny-tool='shell(docker push)'
```

For a non-interactive run add `-p "<prompt>"`. Avoid `--allow-all-tools` unless you
accept every tool call without review. Copilot in VS Code uses
`vscode-settings.json` instead; Claude Code uses `claude-settings.json`.

Where to apply the other templates:

- `claude-settings.json`: merge `permissions` into `.claude/settings.json` (project) or
  `~/.claude/settings.json` (user).
- `vscode-settings.json`: merge into `.vscode/settings.json` (workspace) or the user
  `settings.json`.
