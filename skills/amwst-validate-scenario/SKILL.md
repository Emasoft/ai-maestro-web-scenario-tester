---
name: amwst-validate-scenario
description: >-
  Validate a .scen.md scenario file with amwst-validate-scenario.py before running
  or committing it. Use after writing or editing a scenario (amwst-create-scenario
  / amwst-edit-scenario), or when the user says "validate the scenario", "lint
  SCEN-012", "check my scenario file is well-formed". Reports errors-only +
  warnings and gates a malformed scenario before it wastes an expensive run.
disable-model-invocation: false
---

# Validate a scenario (.scen.md)

Run the bundled validator on a scenario file before a run or a commit — a malformed
scenario otherwise fails deep into an expensive run.

```bash
python3 "${CLAUDE_PLUGIN_ROOT}/scripts/amwst-validate-scenario.py" <file.scen.md>
python3 "${CLAUDE_PLUGIN_ROOT}/scripts/amwst-validate-scenario.py" <file.scen.md> --strict
```

## What it checks
- **Frontmatter** has the required keys: `number, name, version, description,
  client, browser_stack` (errors), and recommends `device, subsystems, ui_sections,
  prerequisites, rewipe-list` (warnings).
- **Body** has `## ` phases (a SAFE-SETUP / Phase 0 and a CLEANUP phase are
  recommended) and `#### S<NNN>` steps.
- **Steps** are numbered strictly increasing (gaps warn; dupes / out-of-order
  error) and each carries **Action / Goal / Verify** (errors); **Creates /
  Modifies** are recommended (cleanup steps that use **Removes:** are exempt).

## Output + exit code
`VALIDATE <file>: <E> errors, <W> warnings`, then one line per finding
(`ERROR:<line> …` / `WARN:<line> …`). Exit is non-zero on any error (CI-safe).
`--strict` promotes warnings to errors.

## On findings
Fix the scenario (via `amwst-edit-scenario`) and re-run until clean. Do NOT run a
scenario the validator errors on.

## Done when

- [ ] The validator exits 0 (no errors) for the scenario file.
- [ ] Any reported errors were fixed and the validator was re-run clean.
