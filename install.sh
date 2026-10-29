#!/bin/sh
# Link (or copy) the kit's skills and rules file into user-level tool folders and register
# hooks/guard.py as a pre-tool hook for Claude Code (settings.json) and Copilot CLI.
# Usage: sh install.sh [install|uninstall|status] [--copy]
set -eu

REPO=$(cd "$(dirname "$0")" && pwd -P)
MARK='<!-- adk-installed -->'
CMD=install
COPY=0
CONFLICT=0

for a in "$@"; do
	case $a in
	install | uninstall | status) CMD=$a ;;
	--copy) COPY=1 ;;
	*)
		echo "usage: sh install.sh [install|uninstall|status] [--copy]" >&2
		exit 2
		;;
	esac
done

say() { printf '%s %s\n' "$1" "$2"; }

# kit_owned <target>: symlink into this repo, or a copy carrying the marker
# (marker file in a dir, or marker line anywhere in a file).
kit_owned() {
	if [ -L "$1" ]; then
		case $(readlink "$1") in "$REPO"/*) return 0 ;; esac
		return 1
	fi
	if [ -d "$1" ]; then [ -f "$1/.adk-installed" ]; return; fi
	[ -f "$1" ] && grep -qxF "$MARK" "$1"
}

exists() { [ -e "$1" ] || [ -L "$1" ]; }

# link_entry <source> <target>: install one kit entry, never overwrite foreign content.
link_entry() {
	src=$1
	tgt=$2
	if [ "$COPY" -eq 0 ] && [ -L "$tgt" ] && [ "$(readlink "$tgt")" = "$src" ]; then
		say ok "$tgt"
		return
	fi
	if exists "$tgt"; then
		if ! kit_owned "$tgt"; then
			say conflict "$tgt"
			CONFLICT=1
			return
		fi
		rm -rf "$tgt"
	fi
	mkdir -p "$(dirname "$tgt")"
	if [ "$COPY" -eq 1 ]; then
		if [ -d "$src" ]; then
			mkdir "$tgt"
			cp -R "$src/." "$tgt/"
			: >"$tgt/.adk-installed"
		else
			# Marker goes after the closing --- of frontmatter, else on line 1.
			awk -v m="$MARK" '
				NR == 1 && $0 != "---" { print m; d = 1 }
				{ print }
				!d && NR > 1 && $0 == "---" { print m; d = 1 }
				END { if (!d) print m }
			' "$src" >"$tgt"
		fi
		say copied "$tgt"
	else
		ln -s "$src" "$tgt"
		say linked "$tgt"
	fi
}

# remove_entry <target>: delete a kit-owned entry.
remove_entry() {
	rm -rf "$1" || return 1
	say removed "$1"
}

# prune <dir>: remove kit-owned entries in dir (all on uninstall, stale ones on install).
prune() {
	for e in "$1"/* "$1"/.[!.]*; do
		exists "$e" || continue
		kit_owned "$e" || continue
		if [ "$CMD" = uninstall ] || [ ! -d "$REPO/skills/$(basename "$e")" ]; then
			remove_entry "$e"
		fi
	done
}

# status_entry <target>
status_entry() {
	exists "$1" || return 0
	if kit_owned "$1"; then say ok "$1"; else say conflict "$1"; CONFLICT=1; fi
}

# Hook registration, run by python3: argv = action settings claude_cmd copilot_file copilot_cmd.
# The kit's settings entry is any hook whose command contains the quoted guard path + --tool claude.
HOOKS_PY='
import json, os, shutil, sys
act, path, cmd, cfile, ccmd = sys.argv[1:]
ident = cmd[cmd.index("\" \"") + 2:]

def say(word, p, extra=""):
    print(word, p + extra)

def write(p, text):
    real = os.path.realpath(p)
    os.makedirs(os.path.dirname(real), exist_ok=True)
    with open(real + ".adk-tmp", "w", encoding="utf-8") as f:
        f.write(text)
    os.replace(real + ".adk-tmp", real)

if act == "install":
    hook = {"version": 1, "hooks": {"preToolUse": [{"type": "command", "bash": ccmd, "timeoutSec": 10}]}}
    text = json.dumps(hook, indent=2) + "\n"
    try:
        same = open(cfile, encoding="utf-8").read() == text
    except OSError:
        same = False
    if not same:
        write(cfile, text)
    say("ok" if same else "linked", cfile)

data = {}
if os.path.exists(path):
    try:
        with open(path, encoding="utf-8") as f:
            data = json.load(f)
    except ValueError:
        say("conflict", path, " (invalid JSON)")
        sys.exit(1)
hooks = data.get("hooks", {}) if isinstance(data, dict) else None
pre = hooks.get("PreToolUse", []) if isinstance(hooks, dict) else None
if not isinstance(pre, list):
    say("conflict", path, " (unexpected hooks structure)")
    sys.exit(1)

def kit(h):
    return isinstance(h, dict) and isinstance(h.get("command"), str) and ident in h["command"]

found, rest = [], []
for g in pre:
    if isinstance(g, dict) and isinstance(g.get("hooks"), list) and any(kit(h) for h in g["hooks"]):
        found += [h for h in g["hooks"] if kit(h)]
        g["hooks"] = [h for h in g["hooks"] if not kit(h)]
        if not g["hooks"]:
            continue
    rest.append(g)

if act == "status":
    if found:
        say("ok", path)
    sys.exit(0)
if act == "install":
    if len(found) == 1 and found[0]["command"] == cmd:
        say("ok", path)
        sys.exit(0)
    rest.append({"matcher": "Bash|PowerShell", "hooks": [{"type": "command", "command": cmd}]})
elif not found:
    sys.exit(0)
if rest:
    data.setdefault("hooks", {})["PreToolUse"] = rest
elif "hooks" in data:
    hooks.pop("PreToolUse", None)
    if not hooks:
        del data["hooks"]
if os.path.exists(path) and not os.path.exists(path + ".adk-backup"):
    shutil.copy2(path, path + ".adk-backup")
write(path, json.dumps(data, indent=2, ensure_ascii=False) + "\n")
say("linked" if act == "install" else "removed", path)
'
GUARD="$REPO/hooks/guard.py"
SETTINGS="$HOME/.claude/settings.json"
COPILOT_HOOK="$HOME/.copilot/hooks/adk-guard.json"
PY=$(command -v python3 || :)

# hooks <install|uninstall|status>: register, remove or report the guard hooks.
hooks() {
	if [ "$1" = uninstall ] && [ -f "$COPILOT_HOOK" ]; then remove_entry "$COPILOT_HOOK" || CONFLICT=1; fi
	if [ "$1" = status ] && [ -f "$COPILOT_HOOK" ]; then say ok "$COPILOT_HOOK"; fi
	if [ "$1" != install ] && [ ! -f "$SETTINGS" ]; then return 0; fi
	if [ -z "$PY" ]; then
		say conflict "hooks (python 3 not found)"
		CONFLICT=1
		return 0
	fi
	"$PY" -c "$HOOKS_PY" "$1" "$SETTINGS" "\"$PY\" \"$GUARD\" --tool claude" \
		"$COPILOT_HOOK" "\"$PY\" \"$GUARD\" --tool copilot" || CONFLICT=1
}

# Newline-separated lists so paths with spaces survive word splitting.
NL=$(printf '\n_')
NL=${NL%_}
IFS=$NL
SKILL_DIRS="$HOME/.claude/skills$NL$HOME/.agents/skills"
RULES="$HOME/.claude/rules/adk.md$NL$HOME/.copilot/instructions/adk.instructions.md"

case $CMD in
install)
	for d in $SKILL_DIRS; do
		if [ -d "$d" ]; then prune "$d"; fi
	done
	for s in "$REPO"/skills/*/; do
		[ -d "$s" ] || continue
		n=$(basename "$s")
		for d in $SKILL_DIRS; do link_entry "$REPO/skills/$n" "$d/$n"; done
	done
	for r in $RULES; do link_entry "$REPO/rules/adk.md" "$r"; done
	hooks install
	;;
uninstall)
	for d in $SKILL_DIRS; do
		if [ -d "$d" ]; then prune "$d"; fi
	done
	for r in $RULES; do
		if exists "$r" && kit_owned "$r"; then remove_entry "$r"; fi
	done
	hooks uninstall
	;;
status)
	for s in "$REPO"/skills/*/; do
		[ -d "$s" ] || continue
		for d in $SKILL_DIRS; do status_entry "$d/$(basename "$s")"; done
	done
	for r in $RULES; do status_entry "$r"; done
	hooks status
	;;
esac

exit "$CONFLICT"
