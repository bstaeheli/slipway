#!/bin/sh
# Tests for install.sh. Each test runs against a temp copy of the repo with a fresh HOME.
set -u
SRC=$(cd "$(dirname "$0")/.." && pwd)
PY=$(command -v python3)
SH=$(command -v sh)
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
	T=$(cd "$(mktemp -d)" && pwd -P)
	REPO="$T/repo"
	mkdir -p "$REPO/rules" "$REPO/hooks" "$REPO/skills/adk-a" "$REPO/skills/adk-b"
	cp "$SRC/install.sh" "$REPO/"
	cp "$SRC/hooks/guard.py" "$REPO/hooks/"
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
	mkdir -p "$HOME/.claude/skills/adk-spec" "$HOME/.agents/skills/adk-a"
	printf 'mine\n' >"$HOME/.agents/skills/adk-a/SKILL.md"
	before=$(cat "$HOME/.agents/skills/adk-a/SKILL.md")
	ln -s "$T/foreign" "$HOME/.claude/skills/adk-a"
	rc=0
	run || rc=$?
	assert "exit 1" test "$rc" -eq 1
	assert "conflict printed for dir" grep -qx "conflict $HOME/.agents/skills/adk-a" "$T/out"
	assert "content intact" test "$(cat "$HOME/.agents/skills/adk-a/SKILL.md")" = "$before"
	assert "still real dir" test ! -L "$HOME/.agents/skills/adk-a"
	assert "conflict printed for foreign link" grep -qx "conflict $HOME/.claude/skills/adk-a" "$T/out"
	assert "foreign link kept" points_to "$HOME/.claude/skills/adk-a" "$T/foreign"
	assert "others still linked" points_to "$HOME/.claude/skills/adk-b" "$REPO/skills/adk-b"
}

test_prune_stale_link() {
	setup
	mkdir -p "$HOME/.claude/skills" "$HOME/.agents/skills/foreign-dir" "$T/repo-other/skills/x"
	ln -s "$REPO/skills/adk-gone" "$HOME/.claude/skills/adk-gone"
	ln -s "$REPO/skills/adk-gone" "$HOME/.agents/skills/adk-gone"
	ln -s /nonexistent-foreign "$HOME/.agents/skills/foreign-dangling"
	ln -s "$T/repo-other/skills/x" "$HOME/.agents/skills/prefix-twin"
	run
	assert "removed printed" grep -qx "removed $HOME/.claude/skills/adk-gone" "$T/out"
	assert "link gone" test ! -L "$HOME/.claude/skills/adk-gone"
	assert "agents removed printed" grep -qx "removed $HOME/.agents/skills/adk-gone" "$T/out"
	assert "agents link gone" test ! -L "$HOME/.agents/skills/adk-gone"
	assert "foreign dir kept" test -d "$HOME/.agents/skills/foreign-dir"
	assert "foreign dangling link kept" points_to "$HOME/.agents/skills/foreign-dangling" /nonexistent-foreign
	assert "prefix-sharing link kept" points_to "$HOME/.agents/skills/prefix-twin" "$T/repo-other/skills/x"
}

test_prune_rm_failure() {
	setup
	mkdir -p "$HOME/.claude/skills"
	ln -s "$REPO/skills/adk-gone" "$HOME/.claude/skills/adk-gone"
	chmod 555 "$HOME/.claude/skills"
	rc=0
	run || rc=$?
	chmod 755 "$HOME/.claude/skills"
	assert "rm failure exits nonzero" test "$rc" -ne 0
	assert "no removed line on rm failure" test "$(grep -c '^removed ' "$T/out")" = 0
	assert "link still there" test -L "$HOME/.claude/skills/adk-gone"
}

test_symlinked_repo_path() {
	setup
	ln -s "$REPO" "$T/repolink"
	sh "$T/repolink/install.sh" >"$T/out" 2>&1
	assert "link uses physical repo path" points_to "$HOME/.claude/skills/adk-a" "$REPO/skills/adk-a"
	assert "hook uses physical repo path" grep -qF "\"$REPO/hooks/guard.py\\\" --tool copilot" "$HOME/.copilot/hooks/adk-guard.json"
	sh "$T/repolink/install.sh" uninstall >"$T/out" 2>&1
	assert "uninstall via physical path" test ! -L "$HOME/.claude/skills/adk-a"
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
	run --copy
	{ seq 1 30; cat "$f"; } >"$T/shifted" && mv "$T/shifted" "$f"
	run uninstall
	assert "marker past line 20 still kit-owned" test ! -e "$f"
	printf 'plain\n' >"$REPO/rules/adk.md"
	run --copy
	assert "no frontmatter: marker on line 1" test "$(head -n1 "$f")" = "<!-- adk-installed -->"
}

# jget <json file> <python expression over d> [args...]: print the expression (extra args in sys.argv[3:]).
jget() { "$PY" -c 'import json, sys; d = json.load(open(sys.argv[1], encoding="utf-8")); print(eval(sys.argv[2]))' "$@"; }
guard_cmd() { printf '"%s" "%s/hooks/guard.py" --tool %s' "$PY" "$REPO" "$1"; }
# kit_count <settings>: number of PreToolUse hooks that run this repo's guard.
kit_count() { jget "$1" "sum(sys.argv[3] in h.get('command', '') for g in d['hooks']['PreToolUse'] for h in g['hooks'])" "$REPO/hooks/guard.py"; }
ORIG='{"model": "opus", "hooks": {"PreToolUse": [{"matcher": "Bash", "hooks": [{"type": "command", "command": "mine"}]}], "PostToolUse": [{"matcher": "*", "hooks": [{"type": "command", "command": "post"}]}]}, "env": {"A": "1"}}'

test_hooks_written() {
	setup
	run
	f="$HOME/.copilot/hooks/adk-guard.json"
	s="$HOME/.claude/settings.json"
	assert "copilot hook linked line" grep -qx "linked $f" "$T/out"
	# Expressions go through a variable: bash 3.2 mis-parses braces inside nested $(...).
	want="d == {'version': 1, 'hooks': {'preToolUse': [{'type': 'command', 'bash': sys.argv[3], 'timeoutSec': 10}]}}"
	assert "copilot hook schema" test "$(jget "$f" "$want" "$(guard_cmd copilot)")" = True
	assert "settings linked line" grep -qx "linked $s" "$T/out"
	want="d == {'hooks': {'PreToolUse': [{'matcher': 'Bash|PowerShell', 'hooks': [{'type': 'command', 'command': sys.argv[3]}]}]}}"
	assert "settings entry" test "$(jget "$s" "$want" "$(guard_cmd claude)")" = True
	assert "no backup without prior settings" test ! -e "$s.adk-backup"
	run uninstall
	assert "kit-created settings left empty" test "$(jget "$s" "d")" = "{}"
}

test_hook_commands_run() {
	setup
	mv "$REPO" "$T/my repo"
	REPO="$T/my repo"
	run
	proj="$T/proj"
	mkdir -p "$proj/docs/agents"
	c=$(jget "$HOME/.claude/settings.json" "d['hooks']['PreToolUse'][0]['hooks'][0]['command']")
	b=$(jget "$HOME/.copilot/hooks/adk-guard.json" "d['hooks']['preToolUse'][0]['bash']")
	rc=0
	printf '{"cwd": "%s", "tool_input": {"command": "cargo publish"}}' "$proj" | sh -c "$c" 2>/dev/null || rc=$?
	assert "claude hook denies publish (exit 2)" test "$rc" -eq 2
	rc=0
	printf '{"cwd": "%s", "tool_input": {"command": "echo hi"}}' "$proj" | sh -c "$c" || rc=$?
	assert "claude hook allows echo" test "$rc" -eq 0
	out=$(printf '{"cwd": "%s", "toolName": "bash", "toolArgs": {"command": "cargo publish"}}' "$proj" | sh -c "$b")
	assert "copilot hook denies publish" test "$(printf '%s' "$out" | "$PY" -c 'import json, sys; print(json.load(sys.stdin)["permissionDecision"])')" = deny
}

test_claude_settings_merged_once() {
	setup
	s="$HOME/.claude/settings.json"
	mkdir -p "$HOME/.claude"
	printf '%s\n' "$ORIG" >"$s"
	run
	run
	assert "second run ok line" grep -qx "ok $s" "$T/out"
	assert "exactly one guard entry" test "$(kit_count "$s")" = 1
	assert "key order kept" test "$(jget "$s" "list(d)")" = "['model', 'hooks', 'env']"
	assert "user hook kept first" test "$(jget "$s" "d['hooks']['PreToolUse'][0] == json.loads(sys.argv[3])['hooks']['PreToolUse'][0]" "$ORIG")" = True
	assert "other keys kept" test "$(jget "$s" "[d[k] == json.loads(sys.argv[3])[k] for k in ('model', 'env')] + [d['hooks']['PostToolUse'] == json.loads(sys.argv[3])['hooks']['PostToolUse']]" "$ORIG")" = "[True, True, True]"
	"$PY" -c 'import json, sys
p = sys.argv[1]; d = json.load(open(p))
d["hooks"]["PreToolUse"][1]["hooks"][0]["command"] = "\"/old/python3\" \"%s/hooks/guard.py\" --tool claude" % sys.argv[2]
json.dump(d, open(p, "w"))' "$s" "$REPO"
	run
	assert "stale entry replaced line" grep -qx "linked $s" "$T/out"
	assert "stale entry replaced, still one" test "$(kit_count "$s")" = 1
	assert "stale entry now current" test "$(jget "$s" "d['hooks']['PreToolUse'][-1]['hooks'][0]['command']")" = "$(guard_cmd claude)"
}

test_backup_created() {
	setup
	s="$HOME/.claude/settings.json"
	mkdir -p "$HOME/.claude"
	printf '{"model": "opus"}\n' >"$s"
	run
	assert "backup is original" test "$(cat "$s.adk-backup")" = '{"model": "opus"}'
	run uninstall
	printf '{"model": "sonnet"}\n' >"$s"
	run
	assert "backup never overwritten" test "$(cat "$s.adk-backup")" = '{"model": "opus"}'
}

test_uninstall_removes_only_guard_entry() {
	setup
	s="$HOME/.claude/settings.json"
	f="$HOME/.copilot/hooks/adk-guard.json"
	mkdir -p "$HOME/.claude" "$HOME/.copilot/hooks"
	printf '%s\n' "$ORIG" >"$s"
	printf '{}\n' >"$HOME/.copilot/hooks/mine.json"
	run
	run uninstall
	assert "settings removed line" grep -qx "removed $s" "$T/out"
	assert "copilot hook removed line" grep -qx "removed $f" "$T/out"
	assert "settings equal original" test "$(jget "$s" "d == json.loads(sys.argv[3])" "$ORIG")" = True
	assert "copilot hook gone" test ! -e "$f"
	assert "foreign copilot hook kept" test -f "$HOME/.copilot/hooks/mine.json"
	run uninstall
	assert "second uninstall prints nothing" test ! -s "$T/out"
}

test_invalid_settings_json() {
	setup
	s="$HOME/.claude/settings.json"
	mkdir -p "$HOME/.claude"
	printf '{not json\n' >"$s"
	rc=0
	run || rc=$?
	assert "invalid json exit 1" test "$rc" -eq 1
	assert "invalid json conflict line" grep -qx "conflict $s (invalid JSON)" "$T/out"
	assert "invalid json untouched" test "$(cat "$s")" = '{not json'
	assert "invalid json no backup" test ! -e "$s.adk-backup"
	assert "copilot hook still written" test -f "$HOME/.copilot/hooks/adk-guard.json"
	check_links
}

test_missing_python() {
	setup
	mkdir "$T/bin"
	for c in dirname readlink grep rm mkdir ln awk cp basename; do ln -s "$(command -v "$c")" "$T/bin/$c"; done
	rc=0
	PATH="$T/bin" "$SH" "$REPO/install.sh" >"$T/out" 2>&1 || rc=$?
	assert "no python exit 1" test "$rc" -eq 1
	assert "no python conflict line" grep -qx "conflict hooks (python 3 not found)" "$T/out"
	assert "no python: no copilot hook" test ! -e "$HOME/.copilot/hooks/adk-guard.json"
	assert "no python: no settings" test ! -e "$HOME/.claude/settings.json"
	check_links
}

test_status_hooks() {
	setup
	run
	run status
	assert "status copilot hook" grep -qx "ok $HOME/.copilot/hooks/adk-guard.json" "$T/out"
	assert "status settings" grep -qx "ok $HOME/.claude/settings.json" "$T/out"
}

for t in test_install_links_all test_idempotent test_creates_missing_dirs test_conflict_not_overwritten \
	test_prune_stale_link test_prune_rm_failure test_symlinked_repo_path test_uninstall_keeps_foreign test_home_with_spaces \
	test_never_touches_claude_md test_copy_mode test_copy_mode_keeps_frontmatter test_hooks_written test_hook_commands_run \
	test_claude_settings_merged_once test_backup_created test_uninstall_removes_only_guard_entry test_invalid_settings_json \
	test_missing_python test_status_hooks; do
	"$t"
done

printf '%s assertions, %s failed\n' "$CASES" "$FAILS"
[ "$FAILS" -eq 0 ]
