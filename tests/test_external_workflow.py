import re
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
        self.assertIn("state.py resolve", rules)
        self.assertIn("relative to the resolved state directory", rules)

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
