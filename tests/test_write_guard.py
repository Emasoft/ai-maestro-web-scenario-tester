"""Real tests for scripts/amwst_subagent-write-guard.sh — the PreToolUse write-guard.

Every test runs the REAL shell script in a subprocess with a REAL hook payload on
stdin and a REAL sentinel file on disk. Nothing is mocked: the assertions are on the
hook contract itself — exit 0 allows the tool call, exit 2 blocks it.

Forbidden targets are absolute paths that are never touched on disk (`/etc/...`,
`/Users/victim/...`). The guard's allowlist check is pure string matching after
`realpath -m`, which does not require the path to exist, so no test can damage
anything outside its own tmp_path.
"""
import json
import os
import shutil
import subprocess
import tempfile
from pathlib import Path

import pytest

REPO_ROOT = Path(__file__).resolve().parent.parent
GUARD = REPO_ROOT / "scripts" / "amwst_subagent-write-guard.sh"

ALLOW = 0
BLOCK = 2

# A path outside every allowed root, on every platform. Never created.
FORBIDDEN = "/etc/amwst-write-guard-should-never-write-here.txt"

# pytest's tmp_path lives under the system scratch dir (/tmp on Linux,
# /var/folders/... on macOS), which the guard ALLOWS by design. An escape test
# rooted there would "pass" for the wrong reason: `cd ../..` out of it lands in
# scratch, which is legitimately writable. Escape tests therefore need a project
# root OUTSIDE every allowed root. /var/tmp is world-writable and sticky on both
# macOS (-> /private/var/tmp) and Linux, and matches none of the scratch patterns.
OUTSIDE_TMP = "/var/tmp"


@pytest.fixture
def outside_root():
    """A real directory that is NOT inside any of the guard's allowed roots."""
    path = Path(tempfile.mkdtemp(dir=OUTSIDE_TMP, prefix="amwst-wg-"))
    yield path
    shutil.rmtree(path, ignore_errors=True)


def run_guard(payload, project_dir, *, sentinel=True, env_extra=None):
    """Run the guard on `payload`. Returns (exit_code, stderr)."""
    project_dir = Path(project_dir)
    claude_dir = project_dir / ".claude"
    claude_dir.mkdir(parents=True, exist_ok=True)
    sentinel_file = claude_dir / "scenario_is_running.json"
    if sentinel:
        sentinel_file.write_text("{}")
    elif sentinel_file.exists():
        sentinel_file.unlink()

    env = {
        "PATH": os.environ.get("PATH", "/usr/bin:/bin"),
        "HOME": os.environ.get("HOME", "/root"),
        "CLAUDE_PROJECT_DIR": str(project_dir),
    }
    if env_extra:
        env.update(env_extra)
        env = {k: v for k, v in env.items() if v is not None}

    proc = subprocess.run(
        ["bash", str(GUARD)],
        input=json.dumps(payload),
        capture_output=True,
        text=True,
        env=env,
    )
    return proc.returncode, proc.stderr


def bash_payload(command, cwd):
    return {"tool_name": "Bash", "cwd": str(cwd), "tool_input": {"command": command}}


# ── Sentinel gate ────────────────────────────────────────────────────────────


def test_no_sentinel_is_inert(tmp_path):
    """With no scenario_is_running.json the guard allows even a blatant escape."""
    code, _ = run_guard(
        {"tool_name": "Write", "tool_input": {"file_path": FORBIDDEN}},
        tmp_path,
        sentinel=False,
    )
    assert code == ALLOW


def test_missing_project_dir_allows(tmp_path):
    """Without CLAUDE_PROJECT_DIR the guard cannot know the root, so it allows.

    Measured behaviour: it exits silently at the SENTINEL GATE (which tests the same
    variable) rather than reaching the later `CLAUDE_PROJECT_DIR not set` warning —
    that warn branch is unreachable. Asserting on the warning would be asserting on
    code that never runs.
    """
    code, _ = run_guard(
        {"tool_name": "Write", "tool_input": {"file_path": FORBIDDEN}},
        tmp_path,
        env_extra={"CLAUDE_PROJECT_DIR": None},
    )
    assert code == ALLOW


def test_sentinel_present_enforces(tmp_path):
    """The same payload that passed without a sentinel is blocked with one."""
    code, err = run_guard(
        {"tool_name": "Write", "tool_input": {"file_path": FORBIDDEN}}, tmp_path
    )
    assert code == BLOCK
    assert "BLOCKED by scenarios write-guard" in err


# ── File-tool targets ────────────────────────────────────────────────────────


@pytest.mark.parametrize("tool", ["Write", "Edit", "MultiEdit"])
def test_file_tools_allow_inside_project(tmp_path, tool):
    code, _ = run_guard(
        {"tool_name": tool, "tool_input": {"file_path": str(tmp_path / "src" / "a.py")}},
        tmp_path,
    )
    assert code == ALLOW


@pytest.mark.parametrize("tool", ["Write", "Edit", "MultiEdit"])
def test_file_tools_block_outside_project(tmp_path, tool):
    code, err = run_guard(
        {"tool_name": tool, "tool_input": {"file_path": FORBIDDEN}}, tmp_path
    )
    assert code == BLOCK
    assert tool in err


def test_notebook_edit_uses_notebook_path(tmp_path):
    """NotebookEdit carries notebook_path, not file_path — reading the wrong field would let it through."""
    code, err = run_guard(
        {"tool_name": "NotebookEdit", "tool_input": {"notebook_path": FORBIDDEN}},
        tmp_path,
    )
    assert code == BLOCK
    assert "NotebookEdit" in err


def test_unmatched_tool_is_allowed(tmp_path):
    """Reads are never restricted; a tool outside the matcher falls through to allow."""
    code, _ = run_guard(
        {"tool_name": "Read", "tool_input": {"file_path": FORBIDDEN}}, tmp_path
    )
    assert code == ALLOW


def test_tilde_path_outside_project_is_blocked(outside_root):
    """`~/x` must be expanded before matching, or it slips past as a relative-looking token."""
    home = outside_root / "fake-home"
    home.mkdir()
    code, _ = run_guard(
        {"tool_name": "Write", "tool_input": {"file_path": "~/stolen.txt"}},
        outside_root / "proj",
        env_extra={"HOME": str(home)},
    )
    assert code == BLOCK


# ── Scratch allowlist ────────────────────────────────────────────────────────


def test_tmp_is_allowed(tmp_path):
    code, _ = run_guard(
        {"tool_name": "Write", "tool_input": {"file_path": "/tmp/amwst-scratch.txt"}},
        tmp_path,
    )
    assert code == ALLOW


def test_platform_tmpdir_is_allowed(tmp_path):
    """REGRESSION: on macOS $TMPDIR is /var/folders/..., which realpath -m rewrites to
    /private/var/folders/... . The allowlist matched only the unresolved spelling, so
    every mktemp -d / tempfile write was blocked while the block message claimed
    /var/folders was allowed (measured 2026-08-29)."""
    tmpdir = os.environ.get("TMPDIR") or "/tmp"
    code, err = run_guard(
        {
            "tool_name": "Write",
            "tool_input": {"file_path": str(Path(tmpdir) / "amwst-scratch.txt")},
        },
        tmp_path,
    )
    assert code == ALLOW, err


def test_dev_null_redirection_is_allowed(tmp_path):
    code, _ = run_guard(bash_payload("echo hi > /dev/null", tmp_path), tmp_path)
    assert code == ALLOW


# ── Bash: cd ─────────────────────────────────────────────────────────────────


def test_bash_cd_absolute_outside_is_blocked(tmp_path):
    code, err = run_guard(bash_payload("cd /etc && ls", tmp_path), tmp_path)
    assert code == BLOCK
    assert "'cd' to forbidden dir" in err


def test_bash_cd_inside_project_is_allowed(tmp_path):
    code, _ = run_guard(bash_payload("cd src && ls", tmp_path), tmp_path)
    assert code == ALLOW


def test_bash_cd_relative_escape_is_blocked(outside_root):
    """REGRESSION for 4494ace: `cd ../..` was unchecked until 2026-08-27 and was a live
    escape out of the worktree. It is resolved against the payload's cwd, not the
    hook process's cwd."""
    project = outside_root / "outer" / "inner" / "proj"
    project.mkdir(parents=True)
    code, err = run_guard(
        bash_payload("cd ../.. && rm -rf .git", project), project
    )
    assert code == BLOCK
    assert "'cd' to forbidden dir" in err


def test_bash_relative_path_without_cwd_is_blocked(tmp_path):
    """No cwd in the payload means the target cannot be resolved — unverifiable must
    block, never allow."""
    code, err = run_guard(
        {"tool_name": "Bash", "tool_input": {"command": "cd ../../.. && ls"}}, tmp_path
    )
    assert code == BLOCK
    assert "unresolvable" in err


# ── Bash: redirection ────────────────────────────────────────────────────────


def test_bash_redirect_absolute_outside_is_blocked(tmp_path):
    code, err = run_guard(
        bash_payload(f"echo pwned > {FORBIDDEN}", tmp_path), tmp_path
    )
    assert code == BLOCK
    assert "redirection target" in err


def test_bash_redirect_relative_escape_is_blocked(outside_root):
    project = outside_root / "outer" / "inner" / "proj"
    project.mkdir(parents=True)
    code, err = run_guard(
        bash_payload("echo pwned >> ../../owned.txt", project), project
    )
    assert code == BLOCK
    assert "redirection target" in err


def test_bash_redirect_inside_project_is_allowed(tmp_path):
    code, _ = run_guard(bash_payload("echo ok > ./out.log", tmp_path), tmp_path)
    assert code == ALLOW


# ── Bash: git -C ─────────────────────────────────────────────────────────────


def test_bash_git_dash_c_outside_is_blocked(tmp_path):
    code, err = run_guard(
        bash_payload("git -C /etc/somerepo reset --hard", tmp_path), tmp_path
    )
    assert code == BLOCK
    assert "'git -C' references forbidden dir" in err


def test_bash_git_dash_c_inside_is_allowed(tmp_path):
    code, _ = run_guard(
        bash_payload(f"git -C {tmp_path}/sub status", tmp_path), tmp_path
    )
    assert code == ALLOW


# ── Bash: cp/mv/ln/install — destination only ────────────────────────────────


def test_cp_destination_outside_is_blocked(tmp_path):
    code, err = run_guard(
        bash_payload(f"cp ./local.txt {FORBIDDEN}", tmp_path), tmp_path
    )
    assert code == BLOCK
    assert "destination outside allowed roots" in err


def test_cp_source_outside_destination_inside_is_allowed(tmp_path):
    """Reads are unrestricted: copying FROM outside INTO the project is legitimate."""
    code, err = run_guard(
        bash_payload("cp /etc/hosts ./hosts.copy", tmp_path), tmp_path
    )
    assert code == ALLOW, err


# ── Bash: rm/mkdir/touch/tee/chmod/dd/sed -i — all-path scan ─────────────────


@pytest.mark.parametrize(
    "command",
    [
        f"rm -rf {FORBIDDEN}",
        f"mkdir -p {FORBIDDEN}",
        f"touch {FORBIDDEN}",
        f"echo x | tee {FORBIDDEN}",
        f"chmod 777 {FORBIDDEN}",
        f"sed -i 's/a/b/' {FORBIDDEN}",
    ],
)
def test_write_ops_outside_are_blocked(tmp_path, command):
    code, err = run_guard(bash_payload(command, tmp_path), tmp_path)
    assert code == BLOCK, f"{command!r} was not blocked"
    assert "BLOCKED by scenarios write-guard" in err


def test_write_op_relative_inside_project_is_allowed(tmp_path):
    """The all-path scan must not turn every bare flag or in-project relative path into
    a false block."""
    code, err = run_guard(bash_payload("rm -rf ./build ./dist", tmp_path), tmp_path)
    assert code == ALLOW, err


def test_write_op_relative_escape_is_blocked(outside_root):
    project = outside_root / "outer" / "inner" / "proj"
    project.mkdir(parents=True)
    code, _ = run_guard(bash_payload("rm -rf ../../victim", project), project)
    assert code == BLOCK


# ── Heredoc bodies are literal data, not shell ───────────────────────────────


def test_heredoc_body_is_not_scanned(tmp_path):
    """A dev-browser call ships JS inside <<'EOF' … EOF. Redirect-looking text and
    absolute paths in that body are string data, not shell constructs."""
    command = (
        "node - <<'EOF'\n"
        "const f = (x) => x > 1;\n"
        f"console.log('{FORBIDDEN}');\n"
        "EOF"
    )
    code, err = run_guard(bash_payload(command, tmp_path), tmp_path)
    assert code == ALLOW, err


def test_escape_after_heredoc_is_still_caught(tmp_path):
    """Stripping the body must not swallow the rest of the command."""
    command = (
        "cat <<'EOF' > ./ok.txt\n"
        "harmless\n"
        "EOF\n"
        f"rm -rf {FORBIDDEN}"
    )
    code, _ = run_guard(bash_payload(command, tmp_path), tmp_path)
    assert code == BLOCK


# ── writeGuardAllowlist from scenarios.config.json ───────────────────────────


def test_allowlist_root_is_honoured(tmp_path):
    project = tmp_path / "proj"
    extra = tmp_path / "shared-fixtures"
    extra.mkdir(parents=True)
    config = project / "tests" / "scenarios"
    config.mkdir(parents=True)
    (config / "scenarios.config.json").write_text(
        json.dumps({"writeGuardAllowlist": [str(extra)]})
    )

    code, err = run_guard(
        {"tool_name": "Write", "tool_input": {"file_path": str(extra / "seed.json")}},
        project,
    )
    assert code == ALLOW, err


def test_path_outside_allowlist_root_still_blocked(tmp_path):
    """The allowlist must widen the roots, not disable the guard."""
    project = tmp_path / "proj"
    extra = tmp_path / "shared-fixtures"
    extra.mkdir(parents=True)
    config = project / "tests" / "scenarios"
    config.mkdir(parents=True)
    (config / "scenarios.config.json").write_text(
        json.dumps({"writeGuardAllowlist": [str(extra)]})
    )

    code, _ = run_guard(
        {"tool_name": "Write", "tool_input": {"file_path": FORBIDDEN}}, project
    )
    assert code == BLOCK


def test_malformed_config_does_not_open_the_guard(tmp_path):
    """A broken config must fail closed — the guard keeps enforcing its built-in roots."""
    project = tmp_path / "proj"
    config = project / "tests" / "scenarios"
    config.mkdir(parents=True)
    (config / "scenarios.config.json").write_text("{ not json")

    code, _ = run_guard(
        {"tool_name": "Write", "tool_input": {"file_path": FORBIDDEN}}, project
    )
    assert code == BLOCK


# ── Payload robustness ───────────────────────────────────────────────────────


def test_malformed_payload_blocks(tmp_path):
    """Unparseable JSON yields an empty target, and an unverifiable target must block."""
    project = Path(tmp_path)
    (project / ".claude").mkdir(parents=True, exist_ok=True)
    (project / ".claude" / "scenario_is_running.json").write_text("{}")
    proc = subprocess.run(
        ["bash", str(GUARD)],
        input="{ this is not json",
        capture_output=True,
        text=True,
        env={
            "PATH": os.environ.get("PATH", "/usr/bin:/bin"),
            "HOME": os.environ.get("HOME", "/root"),
            "CLAUDE_PROJECT_DIR": str(project),
        },
    )
    # tool_name is empty -> falls through the case to the catch-all "allow" arm.
    # This documents the measured behaviour: the guard is not a JSON validator, and a
    # malformed payload cannot name a write target it could block on.
    assert proc.returncode == ALLOW


def test_quotes_in_command_do_not_break_the_parser(tmp_path):
    """The payload reaches python3 through an env var precisely so quotes/backslashes
    in the command cannot break parsing."""
    code, _ = run_guard(
        bash_payload("""echo "it's \\"quoted\\"" > ./out.txt""", tmp_path), tmp_path
    )
    assert code == ALLOW


@pytest.mark.skipif(shutil.which("bash") is None, reason="bash required")
def test_guard_is_executable_shell():
    assert GUARD.exists()
    assert GUARD.read_text().startswith("#!/usr/bin/env bash")
