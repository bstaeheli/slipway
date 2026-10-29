import re
import unittest
from pathlib import Path

ROOT = Path(__file__).resolve().parent.parent
RULES = ROOT / "rules" / "adk.md"


def section(path: str, heading: str) -> str:
    """Return the body of the `## heading` section of a markdown file."""
    text = Path(path).read_text(encoding="utf-8")
    m = re.search(r"^## " + re.escape(heading) + r"\s*$(.*?)(?=^## |\Z)", text, re.S | re.M)
    if not m:
        raise AssertionError(f"missing section {heading!r} in {path}")
    return m.group(1)


HEADINGS = [
    "Opt-in", "Precedence", "Workflow", "Freedoms", "Prohibitions", "Principles",
    "Stopping and blockers", "Permissions and environments", "Git platforms",
    "Model and context economy",
]


class RulesTest(unittest.TestCase):
    def setUp(self):
        self.text = RULES.read_text(encoding="utf-8")

    def test_frontmatter_applyto_all(self):
        self.assertTrue(self.text.startswith('---\napplyTo: "**"\n'))

    def test_opt_in_is_first_section(self):
        self.assertEqual(re.findall(r"^## (.+)$", self.text, re.M)[0], "Opt-in")
        body = section(str(RULES), "Opt-in")
        self.assertIn("docs/agents/", body)
        self.assertIn("do nothing", body)

    def test_headings_in_order(self):
        self.assertEqual(re.findall(r"^## (.+)$", self.text, re.M), HEADINGS)

    def test_prohibitions_complete(self):
        body = section(str(RULES), "Prohibitions")
        for s in ["violate the constitution", "contradict explicit requirements",
                  "break established contracts", "compromise security or privacy",
                  "silently change intended behavior",
                  "weaken, skip or delete tests", "conceal failures or uncertainty",
                  "customer environments", "package registries"]:
            self.assertIn(s, body)

    def test_precedence_names_kit_skills(self):
        body = section(str(RULES), "Precedence")
        self.assertIn("adk-", body)
        self.assertIn("take precedence", body)
        self.assertIn("docs/agents/", body)

    def test_tiers_defined(self):
        body = section(str(RULES), "Model and context economy")
        for s in ["large", "mid", "small", "escalat"]:
            self.assertIn(s, body)

    def test_unlisted_target_is_customer(self):
        body = section(str(RULES), "Permissions and environments")
        self.assertIn("environments.md", body)
        self.assertRegex(body, r"not listed.*customer environment")

    def test_no_em_dash(self):
        self.assertNotIn("—", self.text)


if __name__ == "__main__":
    unittest.main()
