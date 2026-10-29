import json
import subprocess
import sys
import tempfile
import unittest
from pathlib import Path

ROOT = Path(__file__).resolve().parent.parent
GUARD = ROOT / "hooks" / "guard.py"
sys.path.insert(0, str(ROOT / "hooks"))

import guard  # noqa: E402

ENV_MD = """# Environments

## Allowed targets

- `bcdev` local Docker container
- `localhost:4873` local npm registry

## Notes

- `custprod` is a customer system, not allowed
"""


class GuardTest(unittest.TestCase):
    def setUp(self):
        self._tmp = tempfile.TemporaryDirectory()
        self.root = Path(self._tmp.name)

    def tearDown(self):
        self._tmp.cleanup()

    def project(self, name="proj", opted_in=True, environments=ENV_MD):
        p = self.root / name
        (p / ".git").mkdir(parents=True)
        if opted_in:
            (p / "docs" / "agents" / "constitution").mkdir(parents=True)
            if environments is not None:
                (p / "docs" / "agents" / "constitution" / "environments.md").write_text(
                    environments, encoding="utf-8")
        return p

    def assertAllowed(self, cmd, p):
        ok, reason = guard.check(cmd, p)
        self.assertTrue(ok, cmd + ": " + reason)

    def assertDenied(self, cmd, p):
        ok, reason = guard.check(cmd, p)
        self.assertFalse(ok, cmd)
        self.assertIn("environments.md", reason)

    def test_no_docs_agents_allows_everything(self):
        self.assertAllowed("Publish-BcContainerApp -containerName prod", self.project(opted_in=False))

    def test_plain_command_allowed(self):
        self.assertAllowed("cargo test", self.project())

    def test_listed_target_allowed(self):
        self.assertAllowed("Publish-BcContainerApp -containerName bcdev", self.project())

    def test_unlisted_target_denied(self):
        # `custprod` appears outside the Allowed targets section, so it stays unlisted.
        self.assertDenied("Publish-BcContainerApp -containerName custprod", self.project())

    def test_missing_environments_denies_publish(self):
        p = self.project(environments=None)
        self.assertDenied("Publish-BcContainerApp -containerName bcdev", p)
        self.assertAllowed("ls", p)

    def test_ssh_unlisted_host_denied(self):
        self.assertDenied("ssh admin@customer.example", self.project())

    def test_remote_delete_denied(self):
        self.assertDenied(
            "curl -X DELETE https://api.businesscentral.dynamics.com/v2.0/tenant/companies(1)",
            self.project())

    def test_registry_publish_denied(self):
        p = self.project()
        for cmd in ("cargo publish", "npm publish", "twine upload dist/*"):
            self.assertDenied(cmd, p)

    def test_appsource_submission_denied(self):
        self.assertDenied("New-AppSourceSubmission -appFile x.app", self.project())

    def test_listed_local_registry_allowed(self):
        self.assertAllowed("npm publish --registry http://localhost:4873", self.project())

    def test_registry_dry_run_still_denied(self):
        self.assertDenied("cargo publish --dry-run", self.project())

    def test_project_path_with_spaces(self):
        p = self.project("my project")
        self.assertDenied("ssh admin@customer.example", p)
        self.assertAllowed("Publish-BcContainerApp -containerName bcdev", p)

    def test_subdirectory_finds_opt_in_root(self):
        sub = self.project() / "src" / "app"
        sub.mkdir(parents=True)
        self.assertDenied("cargo publish", sub)
        self.assertAllowed("Publish-BcContainerApp -containerName bcdev", sub)

    def test_listed_target_prefix_not_allowed(self):
        p = self.project()
        self.assertDenied("ssh bcdev-cust.example", p)
        self.assertDenied("ssh xbcdev", p)
        self.assertAllowed("ssh bcdev", p)

    def run_cli(self, tool, stdin, cwd=None):
        return subprocess.run(
            [sys.executable, str(GUARD), "--tool", tool],
            input=stdin, capture_output=True, text=True, cwd=cwd)

    def test_cli_claude_deny_exit_2(self):
        p = self.project()
        r = self.run_cli("claude", json.dumps(
            {"tool_name": "Bash", "tool_input": {"command": "cargo publish"}, "cwd": str(p)}))
        self.assertEqual(r.returncode, 2)
        self.assertIn("environments.md", r.stderr)
        self.assertEqual(r.stdout, "")

    def test_cli_copilot_deny_format(self):
        p = self.project()
        r = self.run_cli("copilot", json.dumps(
            {"sessionId": "s", "timestamp": 1, "cwd": str(p), "toolName": "bash",
             "toolArgs": {"command": "ssh admin@customer.example", "mode": "sync"}}))
        self.assertEqual(r.returncode, 0)
        out = json.loads(r.stdout)
        self.assertEqual(out["permissionDecision"], "deny")
        self.assertIn("environments.md", out["permissionDecisionReason"])

    def test_cli_allow_no_output(self):
        p = self.project()
        for tool, payload in (
                ("claude", {"tool_input": {"command": "cargo test"}, "cwd": str(p)}),
                ("copilot", {"cwd": str(p), "toolName": "bash", "toolArgs": {"command": "cargo test"}})):
            r = self.run_cli(tool, json.dumps(payload))
            self.assertEqual((r.returncode, r.stdout, r.stderr), (0, "", ""), tool)

    def test_malformed_input_denies(self):
        p = self.project()
        r = self.run_cli("claude", "not json", cwd=str(p))
        self.assertEqual(r.returncode, 2)
        self.assertNotEqual(r.stderr, "")
        r = self.run_cli("copilot", "not json", cwd=str(p))
        self.assertEqual(r.returncode, 0)
        self.assertEqual(json.loads(r.stdout)["permissionDecision"], "deny")

    def test_malformed_input_outside_opt_in_allows(self):
        p = self.project(opted_in=False)
        for tool in ("claude", "copilot"):
            r = self.run_cli(tool, "not json", cwd=str(p))
            self.assertEqual((r.returncode, r.stdout, r.stderr), (0, "", ""), tool)

    def test_nested_command_key(self):
        self.assertEqual(
            guard.find_commands({"tool_input": {"command": "a"}}), ["a"])
        self.assertEqual(
            guard.find_commands({"toolArgs": {"command": "b", "x": [{"command": "c"}]}}), ["b", "c"])
        p = self.project()
        r = self.run_cli("claude", json.dumps(
            {"tool_input": {"nested": {"command": "cargo publish"}}, "cwd": str(p)}))
        self.assertEqual(r.returncode, 2)


if __name__ == "__main__":
    unittest.main()
