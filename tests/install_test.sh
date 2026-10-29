#!/bin/sh
# Tests for install.sh. Each test runs against a temp copy of the repo with a fresh HOME.
set -u
SRC=$(cd "$(dirname "$0")/.." && pwd)
FAILS=0
CASES=0

assert() { # assert <description> <command...>
	desc=$1
	shift
	CASES=$((CASES + 1))
	if ! "$@"; then
		FAILS=$((FAILS + 1))
		printf 'FAIL: %s\n' "$desc"
	fi
}

# Sets REPO and HOME (HOME may be overridden by caller via $1 subdir).
setup() {
	T=$(mktemp -d)
	REPO="$T/repo"
	mkdir -p "$REPO/rules" "$REPO/skills/adk-a" "$REPO/skills/adk-b"
	cp "$SRC/install.sh" "$REPO/"
	cp "$SRC/rules/adk.md" "$REPO/rules/"
	printf 'a\n' >"$REPO/skills/adk-a/SKILL.md"
	printf 'b\n' >"$REPO/skills/adk-b/SKILL.md"
	HOME="$T/${1:-home}"
	mkdir -p "$HOME"
	export HOME
}

run() { sh "$REPO/install.sh" "$@" >"$T/out" 2>&1; }

points_to() { [ -L "$1" ] && [ "$(readlink "$1")" = "$2" ]; }

check_links() {
	for n in adk-a adk-b; do
		assert "claude skill $n" points_to "$HOME/.claude/skills/$n" "$REPO/skills/$n"
		assert "agents skill $n" points_to "$HOME/.agents/skills/$n" "$REPO/skills/$n"
	done
	assert "claude rule" points_to "$HOME/.claude/rules/adk.md" "$REPO/rules/adk.md"
	assert "copilot rule" points_to "$HOME/.copilot/instructions/adk.instructions.md" "$REPO/rules/adk.md"
	assert "no copilot skills" test ! -e "$HOME/.copilot/skills"
}

test_install_links_all() {
	setup
	run
	check_links
}

test_idempotent() {
	setup
	run
	run
	assert "second run has no non-ok line" test "$(grep -vc '^ok ' "$T/out")" = 0
	assert "second run has ok lines" grep -q '^ok ' "$T/out"
}

test_creates_missing_dirs() {
	setup
	assert "HOME empty" test -z "$(ls -A "$HOME")"
	run
	assert "install exit 0" test $? -eq 0
	assert "rules dir created" test -L "$HOME/.claude/rules/adk.md"
}

test_conflict_not_overwritten() {
	setup
	mkdir -p "$HOME/.claude/skills/adk-spec" "$HOME/.claude/skills/adk-a"
	printf 'mine\n' >"$HOME/.claude/skills/adk-a/SKILL.md"
	before=$(cat "$HOME/.claude/skills/adk-a/SKILL.md")
	rc=0
	run || rc=$?
	assert "exit 1" test "$rc" -eq 1
	assert "conflict printed" grep -q "^conflict $HOME/.claude/skills/adk-a" "$T/out"
	assert "content intact" test "$(cat "$HOME/.claude/skills/adk-a/SKILL.md")" = "$before"
	assert "still real dir" test ! -L "$HOME/.claude/skills/adk-a"
	assert "others still linked" points_to "$HOME/.claude/skills/adk-b" "$REPO/skills/adk-b"
}

test_prune_stale_link() {
	setup
	mkdir -p "$HOME/.claude/skills"
	ln -s "$REPO/skills/adk-gone" "$HOME/.claude/skills/adk-gone"
	run
	assert "removed printed" grep -q "^removed $HOME/.claude/skills/adk-gone" "$T/out"
	assert "link gone" test ! -L "$HOME/.claude/skills/adk-gone"
}

test_uninstall_keeps_foreign() {
	setup
	run
	mkdir -p "$HOME/.agents/skills/foreign-dir"
	ln -s /nonexistent-foreign "$HOME/.agents/skills/foreign-link"
	run uninstall
	assert "foreign dir kept" test -d "$HOME/.agents/skills/foreign-dir"
	assert "foreign link kept" test -L "$HOME/.agents/skills/foreign-link"
	for p in .claude/skills/adk-a .claude/skills/adk-b .agents/skills/adk-a .agents/skills/adk-b \
		.claude/rules/adk.md .copilot/instructions/adk.instructions.md; do
		assert "gone $p" test ! -e "$HOME/$p" -a ! -L "$HOME/$p"
	done
}

test_home_with_spaces() {
	setup "with space"
	run
	check_links
}

test_never_touches_claude_md() {
	setup
	mkdir -p "$HOME/.claude"
	printf 'user notes\n' >"$HOME/.claude/CLAUDE.md"
	run
	assert "unchanged after install" test "$(cat "$HOME/.claude/CLAUDE.md")" = "user notes"
	run uninstall
	assert "unchanged after uninstall" test "$(cat "$HOME/.claude/CLAUDE.md")" = "user notes"
}

test_copy_mode() {
	setup
	run --copy
	assert "copied printed" grep -q "^copied $HOME/.claude/skills/adk-a" "$T/out"
	for d in .claude/skills/adk-a .agents/skills/adk-b; do
		assert "real dir $d" test -d "$HOME/$d" -a ! -L "$HOME/$d"
		assert "marker $d" test -f "$HOME/$d/.adk-installed"
	done
	assert "rule is real file" test -f "$HOME/.claude/rules/adk.md" -a ! -L "$HOME/.claude/rules/adk.md"
	assert "rule marker" grep -qxF "<!-- adk-installed -->" "$HOME/.claude/rules/adk.md"
	printf 'b2\n' >"$REPO/skills/adk-b/SKILL.md"
	rc=0
	run --copy || rc=$?
	assert "refresh exit 0" test "$rc" -eq 0
	assert "refreshed content" test "$(cat "$HOME/.agents/skills/adk-b/SKILL.md")" = b2
	run uninstall
	assert "copies removed" test ! -e "$HOME/.claude/skills/adk-a" -a ! -e "$HOME/.agents/skills/adk-b" -a ! -e "$HOME/.claude/rules/adk.md"
}

# frontmatter <file>: lines between the opening and closing --- (empty if none).
frontmatter() { awk 'NR == 1 && $0 != "---" { exit } NR > 1 && $0 == "---" { exit } NR > 1' "$1"; }
fm_has() { frontmatter "$1" | grep -q "$2"; }
# after_frontmatter <file>: first line after the closing ---.
after_frontmatter() { awk 'p { print; exit } NR > 1 && $0 == "---" { p = 1 }' "$1"; }

test_copy_mode_keeps_frontmatter() {
	setup
	f="$HOME/.copilot/instructions/adk.instructions.md"
	run --copy
	assert "starts with ---" test "$(head -n1 "$f")" = "---"
	assert "applyTo in frontmatter" fm_has "$f" '^applyTo:'
	assert "marker right after frontmatter" test "$(after_frontmatter "$f")" = "<!-- adk-installed -->"
	assert "marker not in frontmatter" test "$(frontmatter "$f" | grep -c adk-installed)" = 0
	rc=0
	run --copy || rc=$?
	assert "re-run exit 0" test "$rc" -eq 0
	assert "re-run recognizes copy" grep -qx "copied $f" "$T/out"
	run uninstall
	assert "uninstall removes copy" test ! -e "$f"
	printf 'plain\n' >"$REPO/rules/adk.md"
	run --copy
	assert "no frontmatter: marker on line 1" test "$(head -n1 "$f")" = "<!-- adk-installed -->"
}

for t in test_install_links_all test_idempotent test_creates_missing_dirs test_conflict_not_overwritten \
	test_prune_stale_link test_uninstall_keeps_foreign test_home_with_spaces \
	test_never_touches_claude_md test_copy_mode test_copy_mode_keeps_frontmatter; do
	"$t"
done

printf '%s assertions, %s failed\n' "$CASES" "$FAILS"
[ "$FAILS" -eq 0 ]
