#!/usr/bin/env python3
"""Customer-environment guard: a pre-tool hook for Claude Code and Copilot CLI.

In opted-in projects, deny shell commands that publish to or delete on targets
not listed in the state directory's constitution/environments.md.
"""
import argparse
import json
import os
import re
import sys
from pathlib import Path
from typing import List, Optional, Tuple

# Keep state resolution shared with the bootstrap CLI.
try:
    _STATE_MODULE = Path(__file__).resolve().parents[1] / "skills" / "slipway-bootstrap"
    sys.path.insert(0, str(_STATE_MODULE))
    if not (_STATE_MODULE / "state.py").is_file():
        raise ImportError("missing {}".format(_STATE_MODULE / "state.py"))
    import state as slipway_state  # noqa: E402
    from state import StateError, resolve_project_state  # noqa: E402
    _state_import_error = None
except Exception as exc:
    slipway_state = None
    _state_import_error = str(exc)

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

DENY_REASON = ("target not listed in Slipway state constitution/environments.md; "
               "unlisted targets count as customer environments")


def opt_in_root(project_dir: Path) -> Optional[Path]:
    """Return the local project root or external state directory when opted in."""
    result = resolve_project_state(project_dir)
    if result is None:
        return None
    project_root, state_dir, is_external = result
    return state_dir if is_external else project_root


def allowed_targets(root: Path) -> List[str]:
    state_dir = root
    if (root / "docs" / "agents").is_dir():
        state_dir = root / "docs" / "agents"
    try:
        text = (state_dir / "constitution" / "environments.md").read_text(encoding="utf-8")
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


def decide() -> Optional[str]:
    """Deny reason, or None to allow."""
    if _state_import_error is not None:
        return "guard cannot load state resolver ({}); denying".format(_state_import_error)
    project_dir = None
    try:
        data = json.loads(sys.stdin.buffer.read().decode("utf-8"))
        cwd = data.get("cwd") if isinstance(data, dict) else None
        project_dir = Path(cwd) if isinstance(cwd, str) and cwd else Path(os.getcwd())
        for cmd in find_commands(data):
            ok, why = check(cmd, project_dir)
            if not ok:
                return why
        return None
    except Exception as e:
        # Fail closed, but only in opted-in projects: the hook is installed globally.
        # project_dir is the payload cwd when it parsed, else the process cwd. If even that
        # cannot be resolved (deleted cwd), the project cannot be opted in as far as we know: allow.
        if isinstance(e, StateError) and e.opted_in:
            return "guard failed while resolving opted-in state ({}); denying".format(e)
        try:
            if opt_in_root((project_dir or Path(os.getcwd())).resolve()) is not None:
                return "guard failed on hook input ({}); denying".format(e)
        except StateError as state_error:
            if state_error.opted_in:
                return "guard failed while resolving opted-in state ({}); denying".format(state_error)
        except Exception:
            pass
        return None


def main() -> int:
    ap = argparse.ArgumentParser()
    ap.add_argument("--tool", choices=["claude", "copilot"], required=True)
    tool = ap.parse_args().tool
    reason = decide()
    if reason is None:
        return 0
    if tool == "claude":
        sys.stderr.write(reason + "\n")
        return 2
    sys.stdout.write(json.dumps({"permissionDecision": "deny", "permissionDecisionReason": reason}))
    return 0


if __name__ == "__main__":
    sys.exit(main())
