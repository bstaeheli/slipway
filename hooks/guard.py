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

# ponytail: pattern match on shell commands only; MCP tool calls and obfuscated commands are not
# caught, the rules-file prohibition is the second layer. Extend patterns when a new publish path appears.
PUBLISH_OR_REMOTE_DELETE = [
    re.compile(p, re.IGNORECASE) for p in (
        r"Publish-(BcContainerApp|NAVApp|PerTenantExtension|BcNuGetPackageToContainer)",
        r"Install-(NAVApp|BcAppFromAppSource)",
        r"Sync-NAVApp",
        r"Unpublish-",
        r"Uninstall-NAVApp",
        r"Remove-(BcContainer|NAVApp|BcTenant)",
        r"api\.businesscentral\.dynamics\.com",
        r"\bssh\b",
        r"\bscp\b",
        r"\brsync\b.*:",
        r"\bInvoke-(RestMethod|WebRequest)\b.*-Method\s+(Delete|Post|Put|Patch)",
        r"\bcurl\b.*-X\s*(DELETE|POST|PUT|PATCH)",
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
    """Nearest dir from project_dir up to the git root (or filesystem root) that has docs/agents/."""
    for d in [project_dir] + list(project_dir.parents):
        if (d / "docs" / "agents").is_dir():
            return d
        if (d / ".git").exists():
            return None
    return None


def allowed_targets(root: Path) -> List[str]:
    try:
        text = (root / "docs" / "agents" / "constitution" / "environments.md").read_text(encoding="utf-8")
    except OSError:
        return []
    m = re.search(r"^## Allowed targets[ \t]*\r?$(.*?)(?=^## |\Z)", text, re.M | re.S)
    if not m:
        return []
    return re.findall(r"^[ \t]*[-*][ \t]+[^`\n]*`([^`\n]+)`", m.group(1), re.M)


def check(command: str, project_dir: Path) -> Tuple[bool, str]:
    root = opt_in_root(Path(project_dir).resolve())
    if root is None:
        return True, "project not opted in"
    if not any(p.search(command) for p in PUBLISH_OR_REMOTE_DELETE):
        return True, "no publish or remote delete"
    # Whole-token match: `bcdev` must not allow `bcdev-cust.example` or `xbcdev`.
    if any(re.search(r"(?<![A-Za-z0-9._-])" + re.escape(t) + r"(?![A-Za-z0-9._-])", command)
           for t in allowed_targets(root)):
        return True, "target listed"
    return False, DENY_REASON


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
    try:
        data = json.loads(sys.stdin.read())
        cwd = data.get("cwd") if isinstance(data, dict) else None
        project_dir = Path(cwd if isinstance(cwd, str) and cwd else os.getcwd())
        for cmd in find_commands(data):
            ok, why = check(cmd, project_dir)
            if not ok:
                reason = why
                break
    except Exception as e:
        # Fail closed, but only in opted-in projects: the hook is installed globally.
        if opt_in_root(Path(os.getcwd()).resolve()) is not None:
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
