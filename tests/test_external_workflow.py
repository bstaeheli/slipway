import re
import os
import shutil
import subprocess
import sys
import tempfile
import unittest
from pathlib import Path


ROOT = Path(__file__).resolve().parent.parent


def read(path):
    return (ROOT / path).read_text(encoding="utf-8")


class ExternalWorkflowContentTest(unittest.TestCase):
    def test_bootstrap_documents_explicit_external_opt_in_and_resolver(self):
        bootstrap = read(Path("skills") / "slipway-bootstrap" / "SKILL.md")
        rules = read(Path("rules") / "slipway.md")

        self.assertIn("`/slipway-bootstrap external`", bootstrap)
        self.assertIn("state.py resolve", bootstrap)
        self.assertIn("state.py init", bootstrap)
        self.assertIn('" resolve`', rules)
        self.assertIn("relative to the resolved state directory", rules)
        self.assertIn('py -3 "$HOME\\.agents\\skills\\slipway-bootstrap\\state.py" resolve', rules)
        self.assertIn('python "$HOME\\.agents\\skills\\slipway-bootstrap\\state.py" resolve', rules)
        self.assertIn('python3 "$HOME/.agents/skills/slipway-bootstrap/state.py" resolve', rules)
        self.assertIn("replacing `resolve` with `init`", bootstrap)

    @unittest.skipUnless(os.name == "nt" and shutil.which("powershell"), "requires Windows PowerShell")
    def test_powershell_commands_with_spaces_and_launcher(self):
        rules = read(Path("rules") / "slipway.md")
        commands = re.findall(r'`((?:py -3|python|python3) "\$HOME\\[^`]+?" resolve)`', rules)
        self.assertEqual(len(commands), 3)
        with tempfile.TemporaryDirectory(prefix="slipway home ") as tmp:
            home = Path(tmp)
            script = home / ".agents" / "skills" / "slipway-bootstrap" / "state.py"
            script.parent.mkdir(parents=True)
            shutil.copyfile(ROOT / "skills" / "slipway-bootstrap" / "state.py", script)
            project = home.parent / (home.name + " project")
            project.mkdir()
            try:
                (project / ".git").mkdir()
                env = {**os.environ, "USERPROFILE": str(home), "HOME": str(home)}
                for command in commands:
                    for action in ("resolve", "init"):
                        if action == "init":
                            # Each init needs a fresh repository.
                            run_project = project / command.split()[0]
                            run_project.mkdir()
                            (run_project / ".git").mkdir()
                        else:
                            run_project = project
                        prefix = (
                            "$HOME = $env:USERPROFILE; "
                            f"function py {{ & '{sys.executable}' @($args | Select-Object -Skip 1) }}; "
                            f"function python {{ & '{sys.executable}' @args }}; "
                            f"function python3 {{ & '{sys.executable}' @args }}; "
                        )
                        result = subprocess.run(
                            ["powershell", "-NoProfile", "-Command",
                             prefix + command.replace("resolve", action) + "; exit $LASTEXITCODE"],
                            cwd=run_project, env=env, capture_output=True, text=True)
                        self.assertEqual(result.returncode, 1 if action == "resolve" else 0,
                                         result.stderr)
            finally:
                shutil.rmtree(project)

    def test_external_bootstrap_keeps_state_out_of_repo_and_preserves_local_mode(self):
        bootstrap = read(Path("skills") / "slipway-bootstrap" / "SKILL.md")

        self.assertIn("otherwise use the existing local mode", bootstrap)
        self.assertIn("In local mode create `docs/agents/`", bootstrap)
        self.assertIn("In external mode, `AGENTS.md` in the state directory", bootstrap)
        self.assertIn("do not create or edit the repo-root file", bootstrap)
        self.assertIn("commit only in local mode", bootstrap)
        self.assertIn("must not be committed to the project", bootstrap)

    def test_all_other_workflow_skills_advertise_external_opt_in(self):
        skills = (
            "slipway-brainstorm",
            "slipway-bugfix",
            "slipway-do-it",
            "slipway-spec",
            "slipway-build",
        )

        for skill in skills:
            with self.subTest(skill=skill):
                content = read(Path("skills") / skill / "SKILL.md")
                description = re.search(r"^description: (.+)$", content, re.MULTILINE)
                self.assertIsNotNone(description, f"{skill} has no description")
                self.assertIn("external state", description.group(1))

    def test_readme_documents_external_bootstrap_and_guard(self):
        readme = read(Path("README.md"))
        guard_section = re.search(r"^## Guard\n(.*?)(?=^## |\Z)", readme, re.MULTILINE | re.DOTALL)

        self.assertIn("`/slipway-bootstrap external`", readme)
        self.assertIsNotNone(guard_section, "README has no Guard section")
        self.assertIn("state directory's `constitution/environments.md`", guard_section.group(1))
        self.assertIn("second layer", guard_section.group(1))


if __name__ == "__main__":
    unittest.main()
