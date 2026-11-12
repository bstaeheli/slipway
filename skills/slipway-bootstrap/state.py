#!/usr/bin/env python3
"""Resolve and initialize Slipway state outside or inside a project."""
import argparse
import hashlib
import os
import stat
import sys
from pathlib import Path
from typing import Optional, Tuple


class StateError(RuntimeError):
    """A state lookup or initialization failed."""

    def __init__(self, message: str, opted_in: bool = False):
        super().__init__(message)
        self.opted_in = opted_in


ProjectState = Tuple[Path, Path, bool]


def _home() -> Optional[Path]:
    try:
        return Path.home().resolve()
    except Exception:
        return None


def _is_directory(path: Path) -> bool:
    try:
        return stat.S_ISDIR(path.stat().st_mode)
    except FileNotFoundError:
        return False


def _is_git_marker(path: Path) -> bool:
    try:
        mode = path.stat().st_mode
    except FileNotFoundError:
        return False
    return stat.S_ISDIR(mode) or stat.S_ISREG(mode)


def _external_dir(root: Path, home: Optional[Path]) -> Path:
    if home is None:
        raise StateError("cannot determine the user's home directory", True)
    try:
        key = os.path.normcase(str(root)).encode("utf-8")
    except Exception as exc:
        raise StateError("cannot identify Git repository root: {}".format(exc))
    digest = hashlib.sha256(key).hexdigest()
    return home / ".slipway" / "projects" / digest


def _paths_overlap(left: Path, right: Path) -> bool:
    return left == right or left in right.parents or right in left.parents


def _locate(project_directory: Optional[os.PathLike] = None) -> Tuple[Optional[ProjectState], Optional[Path]]:
    try:
        project = Path(project_directory if project_directory is not None else os.getcwd()).expanduser().resolve()
        if not project.is_dir():
            raise StateError("project directory does not exist or is not a directory: {}".format(project))
    except StateError:
        raise
    except Exception as exc:
        raise StateError("cannot resolve project directory: {}".format(exc))

    home = _home()
    for directory in (project,) + tuple(project.parents):
        if home is not None and (directory == home or directory in home.parents):
            return None, None

        local_dir = directory / "docs" / "agents"
        try:
            if _is_directory(local_dir):
                return (directory, local_dir, False), None
        except OSError as exc:
            raise StateError("cannot inspect local state directory {}: {}".format(local_dir, exc), True)

        try:
            is_root = _is_git_marker(directory / ".git")
        except OSError as exc:
            raise StateError("cannot inspect Git metadata in {}: {}".format(directory, exc))
        if is_root:
            external_dir = _external_dir(directory, home)
            try:
                exists_as_dir = _is_directory(external_dir)
            except OSError as exc:
                raise StateError("cannot inspect external state directory {}: {}".format(external_dir, exc), True)
            if exists_as_dir:
                return (directory, external_dir, True), None
            try:
                external_dir.lstat()
            except FileNotFoundError:
                return None, directory
            except OSError as exc:
                raise StateError("cannot inspect external state directory {}: {}".format(external_dir, exc), True)
            raise StateError("external state path exists but is not a directory: {}".format(external_dir), True)

    return None, None


def resolve_project_state(project_directory: Optional[os.PathLike] = None) -> Optional[ProjectState]:
    """Return (project root, state directory, is_external), or None if not opted in."""
    result, _ = _locate(project_directory)
    return result


def resolve_state(project_directory: Optional[os.PathLike] = None) -> Optional[Path]:
    """Return the opted-in state directory, or None when the project is not opted in."""
    result = resolve_project_state(project_directory)
    return result[1] if result is not None else None


def init_state(project_directory: Optional[os.PathLike] = None) -> Path:
    """Create an external state directory without writing into the target repository."""
    result, git_root = _locate(project_directory)
    if result is not None:
        raise StateError("project is already opted in: {}".format(result[1]), True)
    if git_root is None:
        raise StateError("no Git repository root (.git directory or file) found")

    external_dir = _external_dir(git_root, _home())
    try:
        target = external_dir.resolve()
    except OSError as exc:
        raise StateError("cannot resolve external state directory {}: {}".format(external_dir, exc))
    if _paths_overlap(target, git_root):
        raise StateError("external state path overlaps the Git repository: {}".format(target))

    try:
        external_dir.mkdir(parents=True, exist_ok=False)
    except FileExistsError:
        raise StateError("external state path already exists: {}".format(external_dir), True)
    except OSError as exc:
        raise StateError("cannot create external state directory {}: {}".format(external_dir, exc))
    return external_dir


def main(argv=None) -> int:
    parser = argparse.ArgumentParser()
    parser.add_argument("command", choices=("resolve", "init"))
    parser.add_argument("project_directory", nargs="?")
    args = parser.parse_args(argv)
    try:
        if args.command == "resolve":
            result = resolve_state(args.project_directory)
            if result is None:
                return 1
        else:
            result = init_state(args.project_directory)
        print(str(result))
        return 0
    except Exception as exc:
        print("error: {}".format(exc), file=sys.stderr)
        return 2


if __name__ == "__main__":
    sys.exit(main())
