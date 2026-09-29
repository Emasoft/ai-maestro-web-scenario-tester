"""Repo-level password guard — issue #3 regression test (Rule 12).

No file under references/ or skills/ may carry a quoted `governance_password:`
value that is not an env-var NAME ($VARNAME), and no committed file may assign
a non-empty value to AIM_GOVERNANCE_PASSWORD (env files are never committed, so
a committed assignment is a leaked default). Scans *.md *.py *.json *.sh *.yml
under references/ and skills/ only, so the test stays fast.
"""
import importlib.util
import re
from pathlib import Path

REPO_ROOT = Path(__file__).resolve().parent.parent
SCAN_DIRS = [REPO_ROOT / "references", REPO_ROOT / "skills"]
SCAN_SUFFIXES = {".md", ".py", ".json", ".sh", ".yml"}

# The validator module (dashed filename → importlib), same loader as test_validate_scenario.py.
_spec = importlib.util.spec_from_file_location(
    "amwst_validate_scenario", REPO_ROOT / "scripts" / "amwst-validate-scenario.py"
)
assert _spec is not None and _spec.loader is not None  # the script exists; a None spec means it vanished
_validator = importlib.util.module_from_spec(_spec)
_spec.loader.exec_module(_validator)

# The env-var NAME is the only sanctioned quoted form (Rule 12: THE PASSWORD
# NEVER PASSES THROUGH A MODEL).
ENV_VAR_NAME_RE = re.compile(r"^\$[A-Z_][A-Z0-9_]*$")
ALLOWED_PLACEHOLDERS = {"$MYAPP_TEST_PASSWORD"}
# group(2) is the content BETWEEN the quotes, so the $VARNAME match sees the
# bare name, not the quoted string.
QUOTED_PW_RE = re.compile(r"""governance_password:\s*(['"])(.+?)\1""")
ASSIGNED_PW_RE = re.compile(r"AIM_GOVERNANCE_PASSWORD=(\S+)")


def _guarded_files():
    for d in SCAN_DIRS:
        assert d.is_dir(), f"missing guarded dir: {d}"
        for p in sorted(d.rglob("*")):
            if p.is_file() and p.suffix in SCAN_SUFFIXES:
                yield p


def test_no_literal_governance_password():
    """A quoted governance_password value must be an env-var NAME, never a literal credential."""
    bad = []
    for p in _guarded_files():
        for n, line in enumerate(p.read_text(encoding="utf-8", errors="replace").splitlines(), 1):
            m = QUOTED_PW_RE.search(line)
            if m and not ENV_VAR_NAME_RE.match(m.group(2)) and m.group(2) not in ALLOWED_PLACEHOLDERS:
                bad.append(f"{p.relative_to(REPO_ROOT)}:{n}: {line.strip()}")
    assert not bad, "literal governance_password found (must be $VARNAME, see Rule 12):\n" + "\n".join(bad)


def test_no_committed_aim_governance_password_value():
    """AIM_GOVERNANCE_PASSWORD= may only appear with an empty value — env files are never committed."""
    bad = []
    for p in _guarded_files():
        for n, line in enumerate(p.read_text(encoding="utf-8", errors="replace").splitlines(), 1):
            m = ASSIGNED_PW_RE.search(line)
            if m:
                bad.append(f"{p.relative_to(REPO_ROOT)}:{n}: {line.strip()}")
    assert not bad, "committed AIM_GOVERNANCE_PASSWORD value found (env files are never committed):\n" + "\n".join(bad)


def test_validator_flags_quoted_literal():
    """The scenario validator errors on governance_password: \"literal\" (authoring-time gate)."""
    bad = "---\nnumber: 1\nname: x\nversion: \"1.0\"\ndescription: x\nclient: claude\n" \
          "browser_stack: dev\ngovernance_password: \"hunter2\"\n---\n\n## Phase CLEANUP\n\n" \
          "#### S001: x\n- **Action:** x\n- **Goal:** x\n- **Verify:** x\n"
    errors, _ = _validator.validate(bad)
    assert any("governance_password" in msg for _ln, msg in errors)


def test_validator_accepts_env_var_name():
    """The sanctioned $VARNAME form passes the validator without a governance_password error."""
    ok = "---\nnumber: 1\nname: x\nversion: \"1.0\"\ndescription: x\nclient: claude\n" \
         "browser_stack: dev\ngovernance_password: \"$MYAPP_TEST_PASSWORD\"\n---\n\n## Phase CLEANUP\n\n" \
         "#### S001: x\n- **Action:** x\n- **Goal:** x\n- **Verify:** x\n"
    errors, _ = _validator.validate(ok)
    assert not any("governance_password" in msg for _ln, msg in errors)
