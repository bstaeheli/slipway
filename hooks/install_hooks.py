#!/usr/bin/env python3
"""Register the guard hook for Claude Code and Copilot CLI; used by install.sh and install.ps1.

Usage: install_hooks.py <install|uninstall|status> <settings.json> <copilot hook file> <python> <guard.py>

Prints one line per touched file (linked|ok|removed|conflict <path>) and exits 1 on conflict.
The kit's settings entry is any PreToolUse hook whose command ends with
`/hooks/guard.py" --tool claude`, from any clone path, so a moved clone replaces its orphan.
Hook commands exit 0 when the guard or the interpreter is gone: the hooks are global, and a
failure to start must not block tools outside opted-in projects (Claude Code blocks on exit 2,
Copilot CLI on any non-zero exit). The guard itself denies with exit 2 (Claude) or stdout JSON. The Copilot hook file is kit-owned by its name; install.sh and
install.ps1 remove it on uninstall themselves, so uninstall here touches settings only.
"""
import json
import os
import shutil
import stat
import sys


def say(word, path, extra=""):
    print(word, path + extra)


def write(path, text):
    """Atomic write through symlinks, UTF-8 without BOM, keeping an existing file's mode."""
    real = os.path.realpath(path)
    os.makedirs(os.path.dirname(real), exist_ok=True)
    tmp = real + ".adk-tmp"
    with open(tmp, "w", encoding="utf-8", newline="\n") as f:
        f.write(text)
    if os.path.exists(real):
        os.chmod(tmp, stat.S_IMODE(os.stat(real).st_mode))
    os.replace(tmp, real)


KIT_SUFFIX = '/hooks/guard.py" --tool claude'


def copilot_text(python, guard):
    run = '"{}" "{}" --tool copilot'.format(python, guard)
    hook = {"type": "command", "bash": run + " || true",
            "powershell": 'if (Test-Path "{}") {{ & {} }}; exit 0'.format(guard, run), "timeoutSec": 10}
    return json.dumps({"version": 1, "hooks": {"preToolUse": [hook]}}, indent=2) + "\n"


def copilot(act, path, python, guard):
    """Return True on conflict."""
    text = copilot_text(python, guard)
    try:
        with open(path, encoding="utf-8-sig") as f:
            same = f.read() == text
    except FileNotFoundError:
        if act == "status":
            return False
        same = False
    except (OSError, UnicodeDecodeError):
        same = False
    if act == "status":
        say("ok" if same else "conflict", path, "" if same else " (stale, re-run install)")
        return not same
    if not same:
        write(path, text)
    say("ok" if same else "linked", path)
    return False


def settings(act, path, cmd):
    """Return True on conflict."""
    exists = os.path.exists(path)
    if not exists and act != "install":
        return False
    data = {}
    if exists:
        try:
            with open(path, encoding="utf-8-sig") as f:
                data = json.load(f)
        except (ValueError, UnicodeDecodeError):
            say("conflict", path, " (invalid JSON)")
            return True
    if not isinstance(data, dict):
        say("conflict", path, " (invalid JSON)")
        return True
    hooks = data.get("hooks", {})
    pre = hooks.get("PreToolUse", []) if isinstance(hooks, dict) else None
    if not isinstance(pre, list):
        say("conflict", path, " (unexpected hooks structure)")
        return True

    def kit(h):
        return isinstance(h, dict) and isinstance(h.get("command"), str) and h["command"].endswith(KIT_SUFFIX)

    found, rest = [], []
    for g in pre:
        if isinstance(g, dict) and isinstance(g.get("hooks"), list) and any(kit(h) for h in g["hooks"]):
            found += [h for h in g["hooks"] if kit(h)]
            g["hooks"] = [h for h in g["hooks"] if not kit(h)]
            if not g["hooks"]:
                continue
        rest.append(g)

    current = len(found) == 1 and found[0]["command"] == cmd
    if act == "status":
        if found:
            say("ok" if current else "conflict", path, "" if current else " (stale, re-run install)")
        return bool(found) and not current
    if act == "install":
        if current:
            say("ok", path)
            return False
        rest.append({"matcher": "Bash|PowerShell", "hooks": [{"type": "command", "command": cmd}]})
    elif not found:
        return False
    if rest:
        data.setdefault("hooks", {})["PreToolUse"] = rest
    elif "hooks" in data:
        hooks.pop("PreToolUse", None)
        if not hooks:
            del data["hooks"]
    backup = path + ".adk-backup"
    if exists and not os.path.exists(backup):
        shutil.copy2(path, backup)
    write(path, json.dumps(data, indent=2, ensure_ascii=False) + "\n")
    say("linked" if act == "install" else "removed", path)
    return False


def main(argv):
    if len(argv) != 5 or argv[0] not in ("install", "uninstall", "status"):
        sys.stderr.write(__doc__)
        return 2
    act, settings_path, copilot_path, python, guard = argv
    conflict = False
    if act != "uninstall":
        conflict |= copilot(act, copilot_path, python, guard)
    claude = '[ ! -f "{0}" ] || "{1}" "{0}" --tool claude'.format(guard, python)
    conflict |= settings(act, settings_path, claude)
    return 1 if conflict else 0


if __name__ == "__main__":
    sys.exit(main(sys.argv[1:]))
