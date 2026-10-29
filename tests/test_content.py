import json
import re
import sys
import unittest
from pathlib import Path

ROOT = Path(__file__).resolve().parent.parent
RULES = ROOT / "rules" / "adk.md"
TEMPLATES = ROOT / "templates" / "permissions"
BOOT = ROOT / "skills" / "adk-bootstrap"
sys.path.insert(0, str(ROOT / "hooks"))
from guard import PUBLISH_OR_REMOTE_DELETE  # noqa: E402


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


def rule_command(rule: str) -> str:
    """`Bash(cargo publish:*)` -> `cargo publish`."""
    m = re.fullmatch(r"(?:Bash|PowerShell)\((.+?)(?::\*)?\)", rule)
    if not m:
        raise AssertionError(f"unexpected rule shape {rule!r}")
    return m.group(1)


def publishes(command: str) -> bool:
    return any(p.search(command) for p in PUBLISH_OR_REMOTE_DELETE)


class PermissionTemplatesTest(unittest.TestCase):
    def setUp(self):
        perms = json.loads((TEMPLATES / "claude-settings.json").read_text(encoding="utf-8"))["permissions"]
        self.allow, self.deny = perms["allow"], perms["deny"]
        self.allow_cmds = {rule_command(r) for r in self.allow}
        self.deny_cmds = {rule_command(r) for r in self.deny}

    def test_claude_allow(self):
        for r in ["Bash(git push:*)", "Bash(git commit:*)", "Bash(al-runner:*)", "Bash(cargo test:*)"]:
            self.assertIn(r, self.allow)

    def test_claude_deny(self):
        for s in ["Publish-PerTenantExtension", "Unpublish-", "cargo publish", "npm publish"]:
            self.assertTrue(any(s in r for r in self.deny), s)

    def test_deny_is_publish_and_never_push(self):
        for c in self.deny_cmds:
            self.assertTrue(publishes(c), c)
            self.assertNotIn("git push", c)

    def test_no_allow_publishes(self):
        for c in self.allow_cmds:
            self.assertFalse(publishes(c), c)

    def test_vscode_same_entries(self):
        data = json.loads((TEMPLATES / "vscode-settings.json").read_text(encoding="utf-8"))
        approve = data["chat.tools.terminal.autoApprove"]
        self.assertEqual({k for k, v in approve.items() if v is True}, self.allow_cmds)
        self.assertEqual({k for k, v in approve.items() if v is False}, self.deny_cmds)

    def test_copilot_cli_flags(self):
        text = (TEMPLATES / "copilot-cli.md").read_text(encoding="utf-8")
        allow = set(re.findall(r"--allow-tool='shell\(([^)]+)\)'", text))
        deny = set(re.findall(r"--deny-tool='shell\(([^)]+)\)'", text))
        self.assertEqual(allow, self.allow_cmds)
        self.assertEqual(deny, self.deny_cmds)
        self.assertNotIn("—", text)


TEMPLATE_FILES = ["AGENTS.md", "brief.md", "tech-stack.md", "invariants.md", "vocabulary.md",
                  "environments.md", "status.md", "lessons.md", "roadmap.md", "personas.md"]


class BootstrapTest(unittest.TestCase):
    def setUp(self):
        self.text = (BOOT / "SKILL.md").read_text(encoding="utf-8")

    def tpl(self, name):
        return (BOOT / "templates" / name).read_text(encoding="utf-8")

    def test_description_and_flag(self):
        desc = re.search(r"^description: (.+)$", self.text, re.M).group(1).lower()
        self.assertIn("bootstrap", desc)
        self.assertIn("opt", desc)
        self.assertIn("disable-model-invocation: true", self.text)

    def test_body_requirements(self):
        low = self.text.lower()
        self.assertIn("docs/agents/", self.text)
        self.assertIn("existing", low)
        self.assertRegex(low, r"confirm")
        self.assertRegex(low, r"never create `?claude\.md")
        self.assertRegex(low, r"never create `?roadmap")

    def test_all_templates_exist(self):
        for n in TEMPLATE_FILES:
            self.assertTrue((BOOT / "templates" / n).is_file(), n)

    def test_status_headings(self):
        heads = re.findall(r"^## (.+)$", self.tpl("status.md"), re.M)
        self.assertEqual(heads, ["Active", "Done", "Parked", "Blockers for the user"])

    def test_environments_format(self):
        t = self.tpl("environments.md")
        self.assertIn("## Allowed targets", t)
        listed = re.findall(r"^- `", section(str(BOOT / "templates" / "environments.md"), "Allowed targets"), re.M)
        self.assertEqual(listed, [])

    def test_agents_overrides(self):
        t = self.tpl("AGENTS.md")
        self.assertIn("docs/agents/", t)
        self.assertIn("merge: agent|human", t)
        self.assertIn("git-platform:", t)

    def test_tech_stack_commands(self):
        low = self.tpl("tech-stack.md").lower()
        for w in ["build", "test", "publish"]:
            self.assertIn(w, low)

    def test_create_when(self):
        for n in ["roadmap.md", "personas.md"]:
            self.assertTrue(self.tpl(n).startswith("Create when"), n)


if __name__ == "__main__":
    unittest.main()
