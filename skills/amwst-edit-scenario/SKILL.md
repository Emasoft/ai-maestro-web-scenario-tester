---
name: amwst-edit-scenario
description: >-
  Use when modifying an existing scenario file. Trigger with "edit SCEN-N" or
  "add a step to scenario N". Adds/removes/reorders steps, tightens
  verifications, fixes Rule 6, bumps version.
argument-hint: scenario-number-or-filename [what-to-edit]
disable-model-invocation: false
model: opus
---

# Edit Scenario — targeted modifications

## Overview

You are the scenario editor. Find an existing scenario file, apply the user's requested edit, and re-validate that the result still passes the 14 scenario rules. You do NOT create new scenario files — direct users to `amwst-create-scenario` for that.

## Prerequisites

- Target scenario file at `${CLAUDE_PROJECT_DIR}/tests/scenarios/SCEN-<padded-id>_*.scen.md` (the scenarios folder is configurable via `scenarios.config.json` `scenariosDir`; default `tests/scenarios/`)
- Scenario rules file (bundled or project override)

## Instructions

### Checklist

Copy this checklist and track your progress:

- [ ] Parse `$ARGUMENTS` to get scenario identifier and edit description
- [ ] Resolve scenario file via `.scen.md` glob; report failure if not found
- [ ] Read the full file: frontmatter, phases, steps, version
- [ ] Apply the edit with the Edit tool
- [ ] Re-validate rule compliance (Rules 1, 2, 6, 10, 12)
- [ ] Bump `version:` if numbering or verifications changed
- [ ] Re-validate the edited file with `amwst-validate-scenario` and fix any reported errors before finishing
- [ ] Return 3-line summary

### Workflow

1. Parse `$ARGUMENTS` to get the scenario identifier and edit description.
2. Resolve the scenario file via glob; report failure if not found.
3. Read the full file: frontmatter, phases, steps, current version.
4. Apply the edit with the Edit tool; preserve field ordering and blank lines.
5. Re-validate: Rule 6 forbidden tokens, Rule 1 cleanup, Rule 2 naming, Rule 10 screenshot, Rule 12 sudo.
6. Bump `version:` if numbering, verifications, or prerequisites changed.
7. Re-validate the edited file before finishing — run `python3 "${CLAUDE_PLUGIN_ROOT}/scripts/amwst-validate-scenario.py" <file.scen.md>` (or invoke the `amwst-validate-scenario` skill). Fix every reported error (frontmatter keys, SAFE-SETUP/CLEANUP phases, strictly-increasing `#### S<NNN>` steps each with Action/Goal/Verify) and re-run until it exits clean.
8. Return a 3-line summary.

### Rules reference

Canonical rules file: `${CLAUDE_PLUGIN_ROOT}/references/SCENARIOS_TESTS_RULES.md` (the bundled canonical copy of the 14 mandatory rules). A consuming project MAY override it at `${CLAUDE_PROJECT_DIR}/tests/scenarios/SCENARIOS_TESTS_RULES.md` — prefer the consumer copy when it exists, else the bundled one.

See [Edit Procedure](references/edit-procedure.md) for the full edit-type table (7 types), Rule 6 forbidden token list, and step-by-step procedure.

## Output

```
SCENARIO_EDITED SCEN-<padded-id> <version-old>-><version-new>
Edits applied: <count> | Violations caught: <count> | Violations fixed: <count>
File: <absolute-path-to-.scen.md>
```

## Error Handling

| Error | Action |
|-------|--------|
| Scenario file not found | List existing files; tell user to use `amwst-create-scenario` for new ones |
| Ambiguous edit request | Ask user for clarification; do not guess intent |
| Forbidden token found post-edit | Report it with suggested UI-only replacement; await approval |
| Edit adds `Creates:` without cleanup step | Flag as Rule 1 violation; propose cleanup step |

## Examples

```
/amwst-edit-scenario 18 add a step after S014 verifying the created item's ID is shown in the card
/amwst-edit-scenario SCEN-009 fix Rule 6 violation in Step S022
/amwst-edit-scenario 16 update prerequisites to require an extra CLI tool
```

## Resources

- [Edit Procedure](references/edit-procedure.md) — full 6-step procedure with renumbering rules, Rule 6 forbidden token table, and violation reporting format
  - Step 1 — Find the scenario file
  - Step 2 — Read the current scenario
  - Step 3 — Understand the requested edit
  - Step 4 — Apply the edit
  - Step 5 — Re-validate rule compliance
  - Step 6 — Bump the version
- `${CLAUDE_PLUGIN_ROOT}/references/SCENARIOS_TESTS_RULES.md` — canonical 14-rule spec (or the consumer override under `tests/scenarios/`)
