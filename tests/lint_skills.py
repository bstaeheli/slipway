"""Lint skills/*/SKILL.md for portability across Claude Code and GitHub Copilot."""
import re
import sys
from pathlib import Path

ALLOWED = {"name", "description", "disable-model-invocation"}


def lint(skills: Path) -> list[str]:
    errs = []
    for f in sorted(skills.rglob("*")):
        if f.is_file() and f.suffix in {".md", ".json", ".txt"} and "—" in f.read_text(encoding="utf-8"):
            errs.append(f"{f}: em dash")
    for md in sorted(skills.glob("*/SKILL.md")):
        text = md.read_text(encoding="utf-8")
        m = re.match(r"---\n(.*?)\n---\n(.*)", text, re.S)
        if not m:
            errs.append(f"{md}: missing frontmatter")
            continue
        keys = dict(re.findall(r"^([A-Za-z-]+):\s*(.*)$", m.group(1), re.M))
        for k in keys.keys() - ALLOWED:
            errs.append(f"{md}: disallowed frontmatter key {k!r}")
        name = keys.get("name", "")
        if name != md.parent.name or not re.fullmatch(r"[a-z0-9-]{1,64}", name):
            errs.append(f"{md}: name {name!r} must equal folder and match [a-z0-9-]{{1,64}}")
        if not 1 <= len(keys.get("description", "")) <= 1024:
            errs.append(f"{md}: description must be 1 to 1024 chars")
        if re.search(r"^!`", m.group(2), re.M):
            errs.append(f"{md}: line starts with !` (shell injection)")
    return errs


if __name__ == "__main__":
    root = Path(__file__).resolve().parent.parent / "skills"
    problems = lint(root)
    print("\n".join(problems))
    sys.exit(1 if problems else 0)
