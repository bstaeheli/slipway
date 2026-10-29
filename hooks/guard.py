#!/usr/bin/env python3
"""Customer-environment guard: a pre-tool hook for Claude Code and Copilot CLI.

In projects that opted into the kit (a docs/agents/ directory), deny shell commands
that publish to or delete on targets not listed in
docs/agents/constitution/environments.md under "## Allowed targets".
"""
import argparse
import json
import os
import re
import sys
from pathlib import Path
from typing import List, Optional, Tuple

# ponytail: pattern match on shell commands only; MCP tool calls, obfuscated commands (variables,
# base64, eval) and shell aliases or wrapper scripts are not caught, the rules-file prohibition is the
# second layer. Extend patterns when a new publish path appears.
PUBLISH_OR_REMOTE_DELETE = [
    re.compile(p, re.IGNORECASE | re.DOTALL) for p in (
        r"Publish-(BcContainerApp|NAVApp|PerTenantExtension|BcNuGetPackageToContainer)",
        r"Install-(NAVApp|BcAppFromAppSource)",
        r"Sync-NAVApp",
        r"Unpublish-",
        r"Uninstall-NAVApp",
        r"Remove-(BcContainer|NAVApp|BcTenant)",
        r"api\.businesscentral\.dynamics\.com",
        r"(?<![\w./-])ssh(?![\w-])",
        r"(?<![\w./-])scp(?![\w-])",
        r"\brsync\b.*:",
        r"\bInvoke-(RestMethod|WebRequest)\b.*-Method\s+(Delete|Post|Put|Patch)",
        r"\bcurl\b.*-X\s*(DELETE|POST|PUT|PATCH)",
        r"\bcurl\b.*--request[\s=]+(DELETE|POST|PUT|PATCH)",
        r"\bcurl\b.*\s(-d|--data(-raw|-binary|-urlencode)?(?![\w-]))",  # implicit POST
        # Package registries
        r"\bcargo\s+publish\b",
        r"\b(npm|pnpm|yarn)\s+(npm\s+)?publish\b",
        r"\btwine\s+upload\b",
        r"\bpoetry\s+publish\b",
        r"\bgem\s+push\b",
        r"\b(dotnet\s+)?nuget\s+push\b",
        r"\bdocker\s+push\b",
        r"\bcpan-upload\b",
        r"New-AppSourceSubmission",
        r"api\.partner\.microsoft\.com",
    )
]

DENY_REASON = ("target not listed in docs/agents/constitution/environments.md; "
               "unlisted targets count as customer environments")


def opt_in_root(project_dir: Path) -> Optional[Path]:
    """Nearest dir from project_dir up to the git root that has docs/agents/.

    The user's home directory and its ancestors never count.
    """
    home = Path.home().resolve()
    for d in [project_dir] + list(project_dir.parents):
        if d == home or d in home.parents:
            return None
        if (d / "docs" / "agents").is_dir():
            return d
        if (d / ".git").exists():
            return None
    return None


def allowed_targets(root: Path) -> List[str]:
    try:
        text = (root / "docs" / "agents" / "constitution" / "environments.md").read_text(encoding="utf-8")
    except (OSError, UnicodeDecodeError):
        return []
    m = re.search(r"^## Allowed targets[ \t]*\r?$(.*?)(?=^## |\Z)", text, re.M | re.S)
    if not m:
        return []
    return re.findall(r"^[ \t]*[-*][ \t]+[^`\n]*`([^`\n]+)`", m.group(1), re.M)


def segments(command: str) -> List[str]:
    """Join bash/PowerShell line continuations, then split on ; && || | and newlines."""
    joined = re.sub(r"[\\`]\r?\n", " ", command)
    return re.split(r"&&|\|\||[;|\r\n]", joined)


def check(command: str, project_dir: Path) -> Tuple[bool, str]:
    root = opt_in_root(Path(project_dir).resolve())
    if root is None:
        return True, "project not opted in"
    targets = allowed_targets(root)
    for seg in segments(command):
        if not any(p.search(seg) for p in PUBLISH_OR_REMOTE_DELETE):
            continue
        # Whole-token match: `bcdev` must not allow `bcdev-cust.example` or `xbcdev`.
        if not any(re.search(r"(?<![A-Za-z0-9._-])" + re.escape(t) + r"(?![A-Za-z0-9._-])", seg)
                   for t in targets):
            return False, DENY_REASON
    return True, "no unlisted publish or remote delete"


def find_commands(node) -> List[str]:
    """Every string value under any key named `command`, at any depth."""
    out = []
    if isinstance(node, dict):
        for k, v in node.items():
            if k == "command" and isinstance(v, str):
                out.append(v)
            else:
                out.extend(find_commands(v))
    elif isinstance(node, list):
        for v in node:
            out.extend(find_commands(v))
    return out


def main() -> int:
    ap = argparse.ArgumentParser()
    ap.add_argument("--tool", choices=["claude", "copilot"], required=True)
    tool = ap.parse_args().tool

    reason = None
    project_dir = Path(os.getcwd())
    try:
        data = json.loads(sys.stdin.buffer.read().decode("utf-8"))
        cwd = data.get("cwd") if isinstance(data, dict) else None
        if isinstance(cwd, str) and cwd:
            project_dir = Path(cwd)
        for cmd in find_commands(data):
            ok, why = check(cmd, project_dir)
            if not ok:
                reason = why
                break
    except Exception as e:
        # Fail closed, but only in opted-in projects: the hook is installed globally.
        # project_dir is the payload cwd when it parsed, else the process cwd.
        if opt_in_root(project_dir.resolve()) is not None:
            reason = "guard could not parse hook input ({}); denying".format(e)

    if reason is None:
        return 0
    if tool == "claude":
        sys.stderr.write(reason + "\n")
        return 2
    sys.stdout.write(json.dumps({"permissionDecision": "deny", "permissionDecisionReason": reason}))
    return 0


if __name__ == "__main__":
    sys.exit(main())
