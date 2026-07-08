"""Real tests for scripts/amwst-validate-scenario.py — the .scen.md DSL linter.

The script filename carries dashes, so it is loaded via importlib from its path.
Every test exercises the real validate() logic (no mocks); the CLI contract
(exit codes, --strict promotion) is tested end-to-end via subprocess.
"""
import importlib.util
import subprocess
import sys
from pathlib import Path

REPO_ROOT = Path(__file__).resolve().parent.parent
SCRIPT = REPO_ROOT / "scripts" / "amwst-validate-scenario.py"

spec = importlib.util.spec_from_file_location("amwst_validate_scenario", SCRIPT)
mod = importlib.util.module_from_spec(spec)
spec.loader.exec_module(mod)

GOOD_SCENARIO = """---
number: 1
name: sample scenario
version: "1.0"
description: >
  A user logs in and sees the dashboard.
client: claude
browser_stack: dev-browser
device: desktop
subsystems:
  - auth
ui_sections:
  - Login page
prerequisites:
  - App running
rewipe-list: []
---

## Phase 0: SAFE-SETUP

#### S001: Open the login page
- **Action:** Navigate to /login
- **Goal:** Login form visible
- **Creates:** nothing
- **Modifies:** nothing
- **Verify:** Form with username field present

## Phase CLEANUP: Restore Original State

#### S002: Revert session
- **Action:** Log out
- **Goal:** Session removed
- **Removes:** session cookie
- **Verify:** Login page shown again
"""


def test_good_scenario_passes():
    """A fully-formed scenario yields zero errors."""
    errors, _warns = mod.validate(GOOD_SCENARIO)
    assert errors == []


def test_missing_frontmatter_is_error():
    """A file not starting with '---' reports a frontmatter error."""
    errors, _ = mod.validate("# no frontmatter\n\n## Phase 0\n\n#### S001: x\n")
    assert any("frontmatter" in msg for _ln, msg in errors)


def test_missing_required_key_is_error():
    """Dropping a required frontmatter key (browser_stack) is an error."""
    text = GOOD_SCENARIO.replace("browser_stack: dev-browser\n", "")
    errors, _ = mod.validate(text)
    assert any("browser_stack" in msg for _ln, msg in errors)


def test_duplicate_step_id_is_error():
    """Two steps with the same S-id are flagged as duplicates."""
    text = GOOD_SCENARIO.replace("#### S002: Revert session", "#### S001: Revert session")
    errors, _ = mod.validate(text)
    assert any("duplicate step id" in msg for _ln, msg in errors)


def test_non_increasing_numbering_is_error():
    """A step numbered lower than its predecessor is a numbering error."""
    text = GOOD_SCENARIO + (
        "\n#### S001: Out of order\n"
        "- **Action:** noop\n- **Goal:** none\n- **Verify:** none\n"
    )
    errors, _ = mod.validate(text)
    assert any("duplicate step id" in msg or "not increasing" in msg for _ln, msg in errors)


def test_step_missing_verify_is_error():
    """A step without **Verify:** is an error (required step field)."""
    text = GOOD_SCENARIO.replace("- **Verify:** Form with username field present\n", "")
    errors, _ = mod.validate(text)
    assert any("missing **Verify:**" in msg for _ln, msg in errors)


def test_removes_step_skips_creates_modifies_warning():
    """A cleanup step using **Removes:** is not nagged for Creates/Modifies."""
    _errors, warns = mod.validate(GOOD_SCENARIO)
    assert not any("S002" in msg for _ln, msg in warns)


def test_cli_exit_codes_and_strict(tmp_path):
    """CLI exits 0 on a clean file and non-zero under --strict when warnings exist."""
    clean = tmp_path / "clean.scen.md"
    clean.write_text(GOOD_SCENARIO, encoding="utf-8")
    r = subprocess.run([sys.executable, str(SCRIPT), str(clean)], capture_output=True, text=True)
    assert r.returncode == 0, r.stdout

    # Unquoted version triggers a warning -> --strict promotes it to an error (exit 1).
    warny = tmp_path / "warny.scen.md"
    warny.write_text(GOOD_SCENARIO.replace('version: "1.0"', "version: 1.0"), encoding="utf-8")
    r_ok = subprocess.run([sys.executable, str(SCRIPT), str(warny)], capture_output=True, text=True)
    assert r_ok.returncode == 0, r_ok.stdout
    r_strict = subprocess.run(
        [sys.executable, str(SCRIPT), str(warny), "--strict"], capture_output=True, text=True
    )
    assert r_strict.returncode == 1, r_strict.stdout
