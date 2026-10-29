#!/bin/sh
# Link (or copy) the kit's skills and rules file into user-level tool folders.
# Usage: sh install.sh [install|uninstall|status] [--copy]
set -eu

REPO=$(cd "$(dirname "$0")" && pwd)
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
# (marker dir file, or marker line within the first 20 lines of a file).
kit_owned() {
	if [ -L "$1" ]; then
		case $(readlink "$1") in "$REPO"/*) return 0 ;; esac
		return 1
	fi
	if [ -d "$1" ]; then [ -f "$1/.adk-installed" ]; return; fi
	[ -f "$1" ] && head -n 20 "$1" | grep -qxF "$MARK"
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
	rm -rf "$1"
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

# Newline-separated lists so paths with spaces survive word splitting.
NL=$(printf '\n_')
NL=${NL%_}
IFS=$NL
SKILL_DIRS="$HOME/.claude/skills$NL$HOME/.agents/skills"
RULES="$HOME/.claude/rules/adk.md$NL$HOME/.copilot/instructions/adk.instructions.md"

case $CMD in
install)
	for d in $SKILL_DIRS; do [ -d "$d" ] && prune "$d"; done
	for s in "$REPO"/skills/*/; do
		[ -d "$s" ] || continue
		n=$(basename "$s")
		for d in $SKILL_DIRS; do link_entry "$REPO/skills/$n" "$d/$n"; done
	done
	for r in $RULES; do link_entry "$REPO/rules/adk.md" "$r"; done
	;;
uninstall)
	for d in $SKILL_DIRS; do [ -d "$d" ] && prune "$d"; done
	for r in $RULES; do
		if exists "$r" && kit_owned "$r"; then remove_entry "$r"; fi
	done
	;;
status)
	for s in "$REPO"/skills/*/; do
		[ -d "$s" ] || continue
		for d in $SKILL_DIRS; do status_entry "$d/$(basename "$s")"; done
	done
	for r in $RULES; do status_entry "$r"; done
	;;
esac

exit "$CONFLICT"
