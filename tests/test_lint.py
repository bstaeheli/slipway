import sys
import tempfile
import unittest
from pathlib import Path

sys.path.insert(0, str(Path(__file__).resolve().parent))
from lint_skills import lint  # noqa: E402

GOOD = "---\nname: demo\ndescription: A demo skill.\n---\n\nBody.\n"


def make(text: str, folder: str = "demo") -> Path:
    root = Path(tempfile.mkdtemp())
    (root / folder).mkdir()
    (root / folder / "SKILL.md").write_text(text, encoding="utf-8")
    return root


class LintTest(unittest.TestCase):
    def test_clean_skill_passes(self):
        self.assertEqual(lint(make(GOOD)), [])

    def test_extra_key_rejected(self):
        self.assertTrue(lint(make(GOOD.replace("---\n\n", "model: x\n---\n\n"))))

    def test_name_mismatch_rejected(self):
        self.assertTrue(lint(make(GOOD, folder="other")))

    def test_bang_injection_rejected(self):
        self.assertTrue(lint(make(GOOD + "!`ls`\n")))

    def test_context_key_rejected(self):
        self.assertTrue(lint(make(GOOD.replace("---\n\n", "context: fork\n---\n\n"))))

    def test_em_dash_rejected(self):
        self.assertTrue(lint(make(GOOD + "a — b\n")))

    def test_long_description_rejected(self):
        self.assertTrue(lint(make(GOOD.replace("A demo skill.", "x" * 1025))))


if __name__ == "__main__":
    unittest.main()
