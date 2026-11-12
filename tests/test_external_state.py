import hashlib
import os
import shutil
import subprocess
import sys
import tempfile
import unittest
from pathlib import Path
from unittest import mock

ROOT = Path(__file__).resolve().parent.parent
STATE = ROOT / "skills" / "slipway-bootstrap" / "state.py"
sys.path.insert(0, str(ROOT / "hooks"))

import guard  # noqa: E402

ENVIRONMENTS = """# Environments

## Allowed targets

- `local-target` local test target
"""


def external_state(home: Path, git_root: Path) -> Path:
    key = hashlib.sha256(
        os.path.normcase(str(git_root.resolve())).encode("utf-8")
    ).hexdigest()
    return home / ".slipway" / "projects" / key


class ExternalStateTest(unittest.TestCase):
    def setUp(self):
        self._tmp = tempfile.TemporaryDirectory()
        self.root = Path(self._tmp.name)
        self.home = self.root / "home"
        self.home.mkdir()
        self.env = {
            **os.environ,
            "HOME": str(self.home),
            "USERPROFILE": str(self.home),
        }

    def tearDown(self):
        self._tmp.cleanup()

    def project(self, name="project with spaces", git_file=False):
        project = self.root / name
        project.mkdir(parents=True)
        if git_file:
            (project / ".git").write_text("gitdir: ../git-metadata\n", encoding="utf-8")
        else:
            (project / ".git").mkdir()
        return project

    def run_state(self, command, project, env=None):
        return subprocess.run(
            [sys.executable, str(STATE), command, str(project)],
            cwd=project,
            env=env or self.env,
            capture_output=True,
            text=True,
            check=False,
        )

    def snapshot(self, project):
        paths = [project, *project.rglob("*")]
        return {
            path.relative_to(project.parent): (
                "dir" if path.is_dir() else path.read_bytes(),
                path.stat().st_mtime_ns,
            )
            for path in paths
        }

    def test_resolve_external_state_from_root_and_subdirectory(self):
        project = self.project()
        selected = external_state(self.home, project)
        selected.mkdir(parents=True)
        subdirectory = project / "src" / "nested"
        subdirectory.mkdir(parents=True)

        for directory in (project, subdirectory):
            with self.subTest(directory=directory):
                result = self.run_state("resolve", directory)
                self.assertEqual(result.returncode, 0, result.stderr)
                self.assertEqual(result.stdout.strip(), str(selected.resolve()))

    def test_resolve_returns_local_state_before_external_state(self):
        project = self.project()
        local = project / "docs" / "agents"
        local.mkdir(parents=True)
        external_state(self.home, project).mkdir(parents=True)

        result = self.run_state("resolve", project)

        self.assertEqual(result.returncode, 0, result.stderr)
        self.assertEqual(result.stdout.strip(), str(local.resolve()))

    def test_resolve_without_opt_in_fails_silently(self):
        result = self.run_state("resolve", self.project())

        self.assertEqual(result.returncode, 1)
        self.assertEqual(result.stdout, "")
        self.assertEqual(result.stderr, "")

    def test_init_finds_nearest_root_and_supports_git_file_or_directory(self):
        for git_file in (False, True):
            with self.subTest(git_file=git_file):
                project = self.project(
                    name=f"git {'file' if git_file else 'directory'} project",
                    git_file=git_file,
                )
                nested = project / "src" / "nested"
                nested.mkdir(parents=True)

                result = self.run_state("init", nested)

                expected = external_state(self.home, project).resolve()
                self.assertEqual(result.returncode, 0, result.stderr)
                self.assertEqual(result.stdout.strip(), str(expected))
                self.assertTrue(expected.is_dir())

    def test_init_does_not_change_project_or_git_metadata(self):
        project = self.project()
        (project / "tracked.txt").write_text("unchanged", encoding="utf-8")
        before = self.snapshot(project)

        result = self.run_state("init", project)

        self.assertEqual(result.returncode, 0, result.stderr)
        self.assertEqual(self.snapshot(project), before)

    def test_init_rejects_external_state_inside_worktree_without_changes(self):
        project = self.project()
        home = project / "home"
        home.mkdir()
        env = {**self.env, "HOME": str(home), "USERPROFILE": str(home)}
        before = self.snapshot(project)

        result = self.run_state("init", project, env=env)

        self.assertNotEqual(result.returncode, 0)
        self.assertEqual(self.snapshot(project), before)

    def test_init_refuses_to_repeat_an_existing_opt_in(self):
        project = self.project()
        first = self.run_state("init", project)
        state_dir = Path(first.stdout.strip())
        sentinel = state_dir / "reinit-sentinel"
        sentinel.write_text("unchanged", encoding="utf-8")
        before = self.snapshot(project)

        second = self.run_state("init", project)

        self.assertEqual(first.returncode, 0, first.stderr)
        self.assertNotEqual(second.returncode, 0)
        self.assertEqual(second.stdout, "")
        self.assertEqual(sentinel.read_text(encoding="utf-8"), "unchanged")
        self.assertEqual(self.snapshot(project), before)

    def test_guard_uses_external_environments_for_allowed_and_unlisted_targets(self):
        project = self.project()
        env_file = (
            external_state(self.home, project)
            / "constitution"
            / "environments.md"
        )
        env_file.parent.mkdir(parents=True)
        env_file.write_text(ENVIRONMENTS, encoding="utf-8")

        with mock.patch.dict(os.environ, self.env):
            allowed, reason = guard.check("ssh local-target", project)
            denied, _ = guard.check("ssh unlisted-target", project)

        self.assertTrue(allowed, reason)
        self.assertFalse(denied)

    def test_guard_local_state_takes_precedence_over_external_state(self):
        project = self.project()
        local_env = (
            project / "docs" / "agents" / "constitution" / "environments.md"
        )
        local_env.parent.mkdir(parents=True)
        local_env.write_text(ENVIRONMENTS.replace("local-target", "local-only"), encoding="utf-8")
        external_env = (
            external_state(self.home, project)
            / "constitution"
            / "environments.md"
        )
        external_env.parent.mkdir(parents=True)
        external_env.write_text(ENVIRONMENTS, encoding="utf-8")

        with mock.patch.dict(os.environ, self.env):
            local_allowed, reason = guard.check("ssh local-only", project)
            external_denied, _ = guard.check("ssh local-target", project)

        self.assertTrue(local_allowed, reason)
        self.assertFalse(external_denied)

    def test_guard_keeps_non_opted_in_behavior(self):
        project = self.project()

        with mock.patch.dict(os.environ, self.env):
            allowed, reason = guard.check("cargo publish", project)

        self.assertTrue(allowed, reason)

    def test_broken_external_state_denies_even_on_malformed_input(self):
        project = self.project()
        state = external_state(self.home, project)
        state.parent.mkdir(parents=True)
        state.write_text("not a directory", encoding="utf-8")
        for payload in ('{"cwd": "%s", "command": "cargo publish"}' %
                        str(project).replace("\\", "\\\\"), "not json"):
            result = subprocess.run(
                [sys.executable, str(ROOT / "hooks" / "guard.py"), "--tool", "claude"],
                input=payload, cwd=project, env=self.env, capture_output=True, text=True)
            self.assertEqual(result.returncode, 2, result.stderr)
            self.assertIn("denying", result.stderr)

    def test_unknown_home_denies_when_external_opt_in_cannot_be_checked(self):
        project = self.project()
        stdin = mock.Mock()
        stdin.buffer.read.return_value = ('{"cwd": "%s", "command": "cargo test"}' %
                                          str(project).replace("\\", "\\\\")).encode()
        with mock.patch.object(guard.sys, "stdin", stdin), \
                mock.patch.object(guard.slipway_state, "_home", return_value=None):
            self.assertIn("denying", guard.decide())

    def test_missing_state_helper_denies_instead_of_disabling_guard(self):
        project = self.project()
        isolated_guard = self.root / "isolated" / "hooks" / "guard.py"
        isolated_guard.parent.mkdir(parents=True)
        shutil.copyfile(ROOT / "hooks" / "guard.py", isolated_guard)
        result = subprocess.run(
            [sys.executable, str(isolated_guard), "--tool", "claude"],
            input="{}", cwd=project, env=self.env, capture_output=True, text=True)
        self.assertEqual(result.returncode, 2, result.stderr)
        self.assertIn("cannot load state resolver", result.stderr)


if __name__ == "__main__":
    unittest.main()
