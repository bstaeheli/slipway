# Git platform setup

The kit opens and merges PRs through a platform MCP server (see `## Git platforms` in `rules/slipway.md`). A missing server is recorded as a blocker. Checked 2026-10-29 against official docs; anything not confirmed is marked **unverified**. Use placeholders below, never commit real tokens: keep them in environment variables or a secrets manager.

## GitHub

Server: `github/github-mcp-server` (remote endpoint `https://api.githubcopilot.com/mcp/`, or local via Docker image `ghcr.io/github/github-mcp-server`). Tools include `create_pull_request` and `merge_pull_request`.

Claude Code (local Docker variant from the server README; needs Docker):

```sh
claude mcp add github -e GITHUB_PERSONAL_ACCESS_TOKEN=<token> -- docker run -i --rm -e GITHUB_PERSONAL_ACCESS_TOKEN ghcr.io/github/github-mcp-server
```

Remote with a token header (generic `claude mcp add --transport http` syntax; GitHub-specific form unverified):

```sh
claude mcp add --transport http github https://api.githubcopilot.com/mcp/ --header "Authorization: Bearer <token>"
```

Copilot CLI: the GitHub MCP server is built in, no setup needed. To run your own: `copilot mcp add github --env GITHUB_PERSONAL_ACCESS_TOKEN=<token> -- docker run -i --rm -e GITHUB_PERSONAL_ACCESS_TOKEN ghcr.io/github/github-mcp-server`.

VS Code (1.101+), `.vscode/mcp.json`:

```json
{
  "servers": {
    "github": {
      "type": "http",
      "url": "https://api.githubcopilot.com/mcp/",
      "headers": { "Authorization": "Bearer ${input:github_mcp_pat}" }
    }
  },
  "inputs": [
    { "type": "promptString", "id": "github_mcp_pat", "description": "GitHub token", "password": true }
  ]
}
```

Omit `headers` and `inputs` to sign in with OAuth instead.

Token scopes: classic PAT `repo` (the server README lists `repo`, `read:org`, `read:packages`). Fine-grained PAT: Pull requests write to create a PR, Contents write to merge it.

## Azure DevOps

Server: Microsoft's Azure DevOps MCP, remote (`https://mcp.dev.azure.com/<organization>`, Microsoft Entra ID sign-in, organization must be backed by an Entra tenant) or local (`npx -y @azure-devops/mcp <organization>`, Node.js 20+). PR create is `repo_pull_request_write` with action `create`. The documented tool list has no explicit merge or complete action; `update` can set autocomplete. Whether that completes a PR in your policies is **unverified**; if not, treat merge as a blocker or merge in the web UI.

Claude Code, local server:

```sh
claude mcp add --transport stdio azure-devops -- npx -y @azure-devops/mcp <organization>
```

Claude Code, remote server (needs your own Entra app registration with redirect `http://localhost:3118/callback`; see the remote server page):

```sh
claude mcp add --transport http ado https://mcp.dev.azure.com/<organization> --client-id <app-client-id> --callback-port 3118
```

Copilot CLI: remote endpoint is a supported environment (Entra sign-in; exact Copilot CLI registration command **unverified**). Local server, `~/.copilot/mcp-config.json`:

```json
{ "mcpServers": { "ado": { "command": "npx", "args": ["-y", "@azure-devops/mcp", "<organization>"], "tools": ["*"] } } }
```

VS Code, `.vscode/mcp.json` (remote needs no install; sign in with Entra when prompted):

```json
{ "servers": { "ado-remote-mcp": { "url": "https://mcp.dev.azure.com/<organization>", "type": "http" } } }
```

Local alternative: `{"servers": {"ado": {"type": "stdio", "command": "npx", "args": ["-y", "@azure-devops/mcp", "<organization>"]}}}`.

Token scopes: the remote server uses Entra OAuth, so no PAT; delegated scopes follow the app registration and the signed-in user's permissions (grant the Code write scope; exact scope name **unverified**). The local server also accepts a PAT (`--authentication pat`, env `PERSONAL_ACCESS_TOKEN` = base64 of `<email>:<pat>`); required PAT scope for PRs (Code: Read & write) is **unverified** in the MCP docs.

## Forgejo

Servers: `forgejo-mcp` (Go, from `codeberg.org/goern/forgejo-mcp`; the project page points releases to `git.b4mad.industries/agentic-forges/forgejo-mcp`). Tools include `create_pull_request` and `merge_pull_request`. Official Forgejo or Codeberg MCP server: none found (**unverified** that this is the best choice). Self-hosted instances: set `--url` to your instance. For codeberg.org use `https://codeberg.org`.

Claude Code:

```sh
claude mcp add --env FORGEJO_ACCESS_TOKEN=<token> --transport stdio forgejo -- forgejo-mcp --transport stdio --url https://codeberg.org
```

Copilot CLI, `~/.copilot/mcp-config.json`:

```json
{ "mcpServers": { "forgejo": { "type": "local", "command": "forgejo-mcp", "args": ["--transport", "stdio", "--url", "https://codeberg.org"], "env": { "FORGEJO_ACCESS_TOKEN": "<token>" }, "tools": ["*"] } } }
```

VS Code, `.vscode/mcp.json`:

```json
{
  "servers": {
    "forgejo": {
      "type": "stdio",
      "command": "forgejo-mcp",
      "args": ["--transport", "stdio", "--url", "https://codeberg.org"],
      "env": { "FORGEJO_ACCESS_TOKEN": "${input:forgejo_token}" }
    }
  },
  "inputs": [{ "type": "promptString", "id": "forgejo_token", "description": "Forgejo token", "password": true }]
}
```

Token scopes (Settings, Applications): `write:repository` covers creating PRs per the Forgejo docs; that it also covers merging is **unverified**. Add `write:issue` if the agent comments on issues.

## Sources

- https://github.com/github/github-mcp-server
- https://docs.github.com/en/copilot/how-tos/copilot-cli/customize-copilot/add-mcp-servers
- https://docs.github.com/en/rest/authentication/permissions-required-for-fine-grained-personal-access-tokens
- https://github.com/microsoft/azure-devops-mcp
- https://learn.microsoft.com/en-us/azure/devops/mcp-server/remote-mcp-server
- https://codeberg.org/goern/forgejo-mcp
- https://forgejo.org/docs/latest/user/token-scope/
- https://code.claude.com/docs/en/mcp
- https://code.visualstudio.com/docs/copilot/customization/mcp-servers
