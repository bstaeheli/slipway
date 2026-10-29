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


class FrontEndSkillsTest(unittest.TestCase):
    NAMES = ["adk-brainstorm", "adk-do-it", "adk-bugfix"]

    def skill(self, name):
        return (ROOT / "skills" / name / "SKILL.md").read_text(encoding="utf-8")

    def test_frontmatter_and_opt_in(self):
        for n in self.NAMES:
            t = self.skill(n)
            self.assertRegex(t, rf"(?m)^name: {n}$")
            desc = re.search(r"^description: (.+)$", t, re.M).group(1)
            self.assertIn("docs/agents/", desc, n)
            self.assertNotIn("disable-model-invocation", t, n)

    def test_reference_rules_by_heading_not_restated(self):
        prohibitions = [l[2:].strip() for h in ["Prohibitions", "Stopping and blockers", "Permissions and environments"]
                        for l in section(str(RULES), h).splitlines() if l.startswith("- ")]
        for n in self.NAMES:
            t = self.skill(n)
            self.assertIn("rules/adk.md", t, n)
            for p in prohibitions:
                self.assertNotIn(p, t, n)
        for n in self.NAMES[1:]:
            t = self.skill(n)
            self.assertIn("## Git platforms", t)
            self.assertIn("## Permissions and environments", t)
            self.assertIn("## Model and context economy", t)
            self.assertIn("tech-stack.md", t)
            self.assertIn("merge: human", t)

    def test_cited_headings_exist(self):
        # A cited heading must exist in the rules or in a kit template (status.md, spec.md).
        sources = [RULES, *(ROOT / "skills").glob("*/templates/*.md")]
        heads = {h for f in sources for h in re.findall(r"^#{2,3} (.+?)\s*$", f.read_text(encoding="utf-8"), re.M)}
        cited = 0
        for md in sorted((ROOT / "skills").glob("*/SKILL.md")):
            for h in re.findall(r"`#{2,3} ([^`]+)`", md.read_text(encoding="utf-8")):
                cited += 1
                self.assertIn(h, heads, f"{md.parent.name}: {h}")
        self.assertGreater(cited, 0)

    def test_give_up_rule(self):
        for n in ["adk-do-it", "adk-bugfix"]:
            t = self.skill(n)
            self.assertIn("3 attempts", t, n)
            self.assertIn("blocker", t.lower(), n)
            self.assertIn("docs/agents/status.md", t, n)

    def test_brainstorm(self):
        t = self.skill("adk-brainstorm")
        low = t.lower()
        self.assertIn("docs/agents/brainstorm/<slug>.md", t)
        self.assertIn("lessons.md", t)
        self.assertIn("constitution", low)
        for r in ["adk-do-it", "adk-bugfix", "adk-spec"]:
            self.assertIn(r, t)
        for w in ["one question", "problem", "assumption", "alternative", "contradiction", "resume",
                  "architecture", "business logic", "in order"]:
            self.assertIn(w, low, w)

    def test_do_it(self):
        t = self.skill("adk-do-it")
        low = t.lower()
        self.assertIn("no spec", low)
        for w in ["what changed", "tests run", "decisions", "escalat"]:
            self.assertIn(w, low, w)

    def test_bugfix(self):
        t = self.skill("adk-bugfix")
        low = t.lower()
        self.assertLess(low.index("reproduction test"), low.index("fix the cause"))
        for w in ["fails", "passes", "never alter", "what changed", "tests run", "decisions", "escalat"]:
            self.assertIn(w, low, w)


SPEC = ROOT / "skills" / "adk-spec"


class SpecSkillTest(unittest.TestCase):
    def setUp(self):
        self.text = (SPEC / "SKILL.md").read_text(encoding="utf-8")
        self.low = self.text.lower()

    def test_frontmatter(self):
        self.assertRegex(self.text, r"(?m)^name: adk-spec$")
        desc = re.search(r"^description: (.+)$", self.text, re.M).group(1)
        self.assertIn("docs/agents/", desc)
        self.assertNotIn("disable-model-invocation", self.text)

    def test_template_headings_exact(self):
        tpl = (SPEC / "templates" / "spec.md").read_text(encoding="utf-8")
        self.assertEqual(re.findall(r"^(#{2,3} .+?)\s*$", tpl, re.M), [
            "## Intent", "## Must", "## Must not", "## Acceptance", "## Design",
            "### Context", "### Graph", "### Acceptance checks", "## Slices"])
        self.assertIn("S1", section(str(SPEC / "templates" / "spec.md"), "Slices"))
        self.assertNotIn("—", tpl)

    def test_output_contract(self):
        for s in ["docs/agents/specs/<slug>.md", "templates/spec.md", "docs/agents/status.md",
                  "## Active", "- [ ] <slug>/S<n>: <title>", "adk-build"]:
            self.assertIn(s, self.text, s)

    def test_spec_content(self):
        for w in ["intent", "must not", "acceptance", "layout", "wording", "unsaid", "implementer"]:
            self.assertIn(w, self.low, w)
        self.assertRegex(self.low, r"never[^.\n]*how")

    def test_design_and_slicing(self):
        for w in ["context", "graph", "acceptance checks", "independently runnable", "testable"]:
            self.assertIn(w, self.low, w)
        self.assertRegex(self.low, r"plan[^.\n]*(never|not) written")

    def test_review_loop(self):
        for w in ["review", "violations only", "never invent", "re-debate", "3 rounds",
                  "## Parked", "separate subagent"]:
            self.assertIn(w.lower(), self.low, w)
        for step in ["spec", "design", "plan", "slicing"]:
            self.assertRegex(self.low, rf"after[^.\n]*{step}", step)

    def test_summary_and_tier(self):
        for w in ["summary", "few lines", "large tier", "## Blockers for the user",
                  "## Model and context economy", "## Stopping and blockers"]:
            self.assertIn(w.lower(), self.low, w)

    def test_assumptions_surfaced(self):
        lines = [l for l in self.low.splitlines() if "assum" in l]
        self.assertTrue(any("## blockers for the user" in l for l in lines))
        self.assertTrue(any('"assumed"' in l for l in lines))
        self.assertTrue(any("park" in l and "## parked" in l for l in lines))
        self.assertTrue(any("summary" in l for l in lines))

    def test_not_restating_rules(self):
        items = [l[2:].strip() for h in ["Stopping and blockers", "Model and context economy"]
                 for l in section(str(RULES), h).splitlines() if l.startswith("- ")]
        for p in items:
            self.assertNotIn(p, self.text)


BUILD = ROOT / "skills" / "adk-build" / "SKILL.md"


class BuildSkillTest(unittest.TestCase):
    def setUp(self):
        self.text = BUILD.read_text(encoding="utf-8")
        self.low = self.text.lower()

    def test_frontmatter(self):
        self.assertRegex(self.text, r"(?m)^name: adk-build$")
        desc = re.search(r"^description: (.+)$", self.text, re.M).group(1)
        self.assertIn("docs/agents/", desc)
        self.assertNotIn("disable-model-invocation", self.text)

    def test_items_in_order(self):
        # One distinguishing phrase per brief item, 1 to 12, in order.
        phrases = ["first unchecked", "fresh subagent", "skeleton", "not read the implementation",
                   "tech-stack.md", "code, test or spec", "3 attempts", "code vs spec",
                   "merge: human", "postmortem", "small tier", '"continue"']
        idx = [self.low.find(p) for p in phrases]
        for p, i in zip(phrases, idx):
            self.assertGreaterEqual(i, 0, p)
        self.assertEqual(idx, sorted(idx))

    def test_resume_and_blockers(self):
        for w in ["docs/agents/status.md", "## Parked", "## Blockers for the user", "batch"]:
            self.assertIn(w.lower(), self.low, w)

    def test_lanes(self):
        for w in ["contracts", "signatures", "data shapes", "error cases", "code lane", "test lane",
                  "## acceptance", "### acceptance checks", "sequential", "review"]:
            self.assertIn(w, self.low, w)

    def test_failure_and_give_up(self):
        for w in ["spec fault", "parked question", "blocker", "next slice"]:
            self.assertIn(w, self.low, w)

    def test_cross_review_pr_merge(self):
        for w in ["code vs spec", "tests vs spec", "code vs tests", "one pr per slice",
                  "## Git platforms", "## Permissions and environments", "- [x]"]:
            self.assertIn(w.lower(), self.low, w)

    def test_summary_honest(self):
        for w in ["summary", "built", "tests run", "result", "open or parked", "decisions",
                  '"assumed"', "escalat", "## Prohibitions", "never claim", "not run"]:
            self.assertIn(w.lower(), self.low, w)

    def test_last_slice(self):
        for w in ["lessons.md", "delete the spec", "git keeps the history"]:
            self.assertIn(w, self.low, w)

    def test_summary_timing_and_records(self):
        self.assertIn("no buildable slice of the spec remains under `## active`", self.low)
        line = next(l for l in self.low.splitlines() if "record in the pr description" in l)
        for w in ["tests run with results", "decisions", "escalations", "docs/agents/status.md"]:
            self.assertIn(w, line, w)
        self.assertIn("build it from the pr descriptions and status notes", self.low)

    def test_resume_wraps_up_and_flags_closed_prs(self):
        resume = next(l for l in self.low.splitlines() if l.startswith("1. **resume"))
        self.assertIn("completes a spec", resume)
        self.assertIn("wrap-up", resume)
        self.assertIn("closed without merging", resume)
        self.assertIn("## blockers for the user", resume)

    def test_rerun_tests_after_cross_review(self):
        line = next(l for l in self.low.splitlines() if "**cross-review" in l)
        self.assertIn("rerun step 5", line)

    def test_stacked_branch(self):
        line = next(l for l in self.low.splitlines() if "stacked" in l)
        self.assertIn("awaits merge", line)
        self.assertIn("pr description", line)

    def test_give_up_any_fix_loop(self):
        line = next(l for l in self.low.splitlines() if "3 attempts" in l)
        for w in ["any fix loop", "lane review", "test failure", "cross-review"]:
            self.assertIn(w, line, w)

    def test_test_fault_cites_prohibitions(self):
        line = next(l for l in self.text.splitlines() if "goes back to that lane" in l)
        self.assertIn("`## Prohibitions`", line)

    def test_human_merge_pending(self):
        self.assertIn("- [ ] <slug>/S<n>: <title> (PR <link>, awaiting human merge)", self.text)
        resume = self.low[self.low.find("resume"):self.low.find("first unchecked")]
        self.assertIn("awaiting human merge", resume)
        self.assertIn("mcp server", resume)
        self.assertIn("prs awaiting merge", self.low)

    def test_delete_requires_all_merged(self):
        line = next(l for l in self.low.splitlines() if "delete the spec" in l)
        self.assertIn("every slice", line)
        self.assertIn("merged", line)
        self.assertLess(line.find("merged"), line.find("delete the spec"))

    def test_tiers(self):
        tiers = self.low[self.low.index("## tiers"):]
        lines = tiers.splitlines()
        def line_with(w):
            return next(l for l in lines if w in l)
        self.assertIn("mid tier", line_with("code lane"))
        self.assertIn("mid tier", line_with("test lane"))
        self.assertIn("large tier", line_with("reviews"))
        self.assertIn("large tier", line_with("failure analysis"))
        self.assertIn("small tier", line_with("status updates"))
        for w in ["## model and context economy", "after a failure"]:
            self.assertIn(w, tiers, w)

    def test_copilot_continue(self):
        self.assertRegex(self.text, r"Copilot[^\n]*\"continue\"")

    def test_not_restating_rules(self):
        items = [l[2:].strip() for h in ["Prohibitions", "Stopping and blockers",
                                         "Permissions and environments", "Model and context economy"]
                 for l in section(str(RULES), h).splitlines() if l.startswith("- ")]
        for p in items:
            self.assertNotIn(p, self.text)


class DocsTest(unittest.TestCase):
    def setUp(self):
        self.plat = (ROOT / "docs" / "platforms.md").read_text(encoding="utf-8")
        self.readme = (ROOT / "README.md").read_text(encoding="utf-8")

    def test_platforms_sections_mention_all_tools(self):
        for head in ("GitHub", "Azure DevOps", "Forgejo"):
            body = section(str(ROOT / "docs" / "platforms.md"), head)
            self.assertTrue(body.strip(), head)
            for tool in ("Claude Code", "Copilot CLI", "VS Code"):
                self.assertIn(tool, body, f"{head}: {tool}")

    def test_readme_terms(self):
        for w in ("install.sh", "install.ps1", "uninstall", "git pull", "adk-bootstrap",
                  "docs/agents/", "Python 3.9", "--copy", "-Copy", "adk-backup",
                  "docs/platforms.md", "2026-10-29-tool-behavior.md"):
            self.assertIn(w, self.readme, w)

    def test_no_em_dash_or_token(self):
        for t in (self.plat, self.readme):
            self.assertNotIn("\u2014", t)
            self.assertNotRegex(t, r"gh[ps]_[A-Za-z0-9]{20,}")


if __name__ == "__main__":
    unittest.main()
