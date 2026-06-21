---
name: amwst-create-scenario
description: >-
  Use when adding a new scenario. Trigger with "create a new scenario", "write
  a scenario for X", or "author SCEN-N". Assigns the next number, drafts
  frontmatter/phases/steps, saves the file.
argument-hint: slug-or-description
disable-model-invocation: false
model: opus
---

# Create Scenario — interactive authoring

## Overview

You are the scenario author. Interview the user, draft a complete scenario file that passes all 14 scenario rules, and save it into the project's scenarios folder (`${CLAUDE_PROJECT_DIR}/tests/scenarios/` by default; configurable via `scenarios.config.json` `scenariosDir`).

## Prerequisites

- The scenarios folder exists (created on first use via `init-scenarios-folder.sh`)
- The target web app running and healthy
- The `dev-browser` plugin available (the browser engine — Rule 8)
- Any credential the project needs for destructive operations (if it has a re-auth gate — Rule 12)

## Instructions

### Checklist

Copy this checklist and track your progress:

- [ ] Ensure the scenarios folder exists (run `init-scenarios-folder.sh` if missing)
- [ ] Read `NEXT_SCEN_NUMBER` and zero-pad to 3 digits
- [ ] Interview user for the required fields (see below)
- [ ] Draft frontmatter with all required fields
- [ ] Draft phases and steps using the exact step format
- [ ] Enforce rules 1, 2, 6, 8, 10, 12, 14 on every Action field
- [ ] Write file to `SCEN-<padded-id>_<slug>.scen.md`
- [ ] Bump `NEXT_SCEN_NUMBER` to `NEXT_N + 1`

### Workflow

1. Verify the scenarios folder exists (run the init script if missing).
2. Read `NEXT_SCEN_NUMBER` and zero-pad to 3 digits (e.g. `7` → `SCEN-007`).
3. Interview the user for the required frontmatter fields.
4. Draft the frontmatter with exact field ordering and quoting.
5. Draft phases and steps using the exact step format.
6. Enforce rules 1, 2, 6, 8, 10, 12, 14 on every Action field.
7. Write the file to `${CLAUDE_PROJECT_DIR}/tests/scenarios/SCEN-NNN_<slug>.scen.md`.
8. Bump `NEXT_SCEN_NUMBER` to `NEXT_N + 1`.

### Rules reference

Canonical rules file: `${CLAUDE_PLUGIN_ROOT}/references/SCENARIOS_TESTS_RULES.md` (the bundled canonical text — 14 mandatory rules). A consuming project MAY override it at `${CLAUDE_PROJECT_DIR}/tests/scenarios/SCENARIOS_TESTS_RULES.md`; prefer the consumer copy when present.

See [Authoring Walkthrough](references/authoring-walkthrough.md) for the full interview question list, step format template, frontmatter template, and rule enforcement checklist.

## Output

```
SCENARIO_CREATED SCEN-<padded-id> <slug>
File: <absolute-path-to-.scen.md>
Next number: <NEXT_N + 1>
```

## Error Handling

| Error | Action |
|-------|--------|
| scenarios folder missing | Run `init-scenarios-folder.sh ${CLAUDE_PROJECT_DIR}` |
| `NEXT_SCEN_NUMBER` missing | Create with content `1` |
| User can't provide a required credential | Stop; tell user to check their project's auth config |
| Action field contains a forbidden token | Rewrite as a UI-only sequence before saving |

## Examples

```
/amwst-create-scenario title-change-lifecycle
/amwst-create-scenario "a scenario for testing marketplace install"
```

## Resources

- [Authoring Walkthrough](references/authoring-walkthrough.md) — full 8-step procedure with interview questions, frontmatter template, step format, and rule enforcement
  - Step 1 — Ensure the scenarios folder exists
  - Step 2 — Assign the next scenario number
  - Step 3 — Interview the user
  - Step 4 — Draft the frontmatter
  - Step 5 — Draft the phases and steps
  - Step 6 — Enforce the rules while drafting
  - Step 7 — Save the scenario file
  - Step 8 — Bump NEXT_SCEN_NUMBER
- `${CLAUDE_PLUGIN_ROOT}/references/SCENARIOS_TESTS_RULES.md` — canonical 14-rule spec (bundled; consumer override at `${CLAUDE_PROJECT_DIR}/tests/scenarios/SCENARIOS_TESTS_RULES.md`)
