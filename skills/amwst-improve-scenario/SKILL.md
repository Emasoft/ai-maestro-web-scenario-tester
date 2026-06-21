---
name: amwst-improve-scenario
description: >-
  Use when a scenario needs post-run analysis. Trigger with "improve SCEN-N",
  "analyze SCEN-N reports", or "strengthen flaky steps in N". Identifies
  patterns and proposes changes.
argument-hint: scenario-number
disable-model-invocation: false
model: opus
---

# Improve Scenario — post-run analysis

## Overview

You are the scenario improver. Look at a scenario's **run history** — its report files and proposed-improvements files — identify patterns, and produce a concrete list of changes to the scenario file (not to the app's source code).

**Distinction:**
- **`amwst-improve-scenario`** (this skill) — proposes edits to the `.scen.md` file itself.
- **`amwst-implement-scenarios-proposals`** — applies the P0 items from `scenario_proposed-improvements_*.md` to the application source code.

## Prerequisites

- At least one report file at `${CLAUDE_PROJECT_DIR}/reports/scenarios-runner/SCEN-<padded-id>_*.report.md`
- Scenario file at `${CLAUDE_PROJECT_DIR}/tests/scenarios/SCEN-<padded-id>_*.scen.md` (the scenarios folder is configurable via `scenarios.config.json` `scenariosDir`; default `tests/scenarios/`)
- Scenario rules file (bundled or project override)

## Instructions

### Checklist

Copy this checklist and track your progress:

- [ ] Parse `$ARGUMENTS` to get scenario number
- [ ] Resolve scenario file via `.scen.md` glob; stop if not found
- [ ] Glob all reports and improvement files for this scenario under `reports/scenarios-runner/`
- [ ] Read reports in chronological order (oldest first)
- [ ] Identify patterns across runs
- [ ] Draft proposed changes with evidence and priority
- [ ] Write analysis report to `${CLAUDE_PROJECT_DIR}/reports/scenarios-runner/`
- [ ] Return 3-line summary

### Workflow

1. Parse `$ARGUMENTS` to get the scenario number.
2. Resolve the scenario file via glob; stop if not found.
3. Glob all report and improvement files for this scenario under `reports/scenarios-runner/`.
4. Read reports in chronological order (oldest first).
5. Identify patterns: flaky steps, repeated bugs, missing coverage, Rule 6 violations, cleanup drift.
6. Draft proposed changes with pattern, evidence, proposed edit, and priority.
7. Write the analysis report to `${CLAUDE_PROJECT_DIR}/reports/scenarios-runner/`.
8. Return a 3-line summary.

### Rules reference

Canonical rules file: `${CLAUDE_PLUGIN_ROOT}/references/SCENARIOS_TESTS_RULES.md` (the bundled canonical copy of the 14 mandatory rules). A consuming project MAY override it at `${CLAUDE_PROJECT_DIR}/tests/scenarios/SCENARIOS_TESTS_RULES.md` — prefer the consumer copy when it exists, else the bundled one.

See [Analysis Procedure](references/analysis-procedure.md) for the full pattern catalog (8 patterns), 5-step procedure, and report template. Do NOT propose a change without evidence from at least two runs or one catastrophic failure.

## Output

```
ANALYSIS_DONE SCEN-<padded-id> <P0-count>/<P1-count>/<P2-count>/<P3-count> proposals
Runs analyzed: <N>
File: <absolute-path-to-analysis-report>
```

## Error Handling

| Error | Action |
|-------|--------|
| No run history (zero reports) | Tell user to run the scenario first via `amwst-run-scenario <N>` or `amwst-run-scenarios-batch <N>`; stop |
| Scenario file not found | Tell user to check the scenario number; stop |
| Pattern unsupported by evidence | Do not propose; note in report as "insufficient evidence" |

## Examples

```
/amwst-improve-scenario 16
/amwst-improve-scenario SCEN-018
/amwst-improve-scenario 9
```

## Resources

- [Analysis Procedure](references/analysis-procedure.md) — full 5-step procedure: locate history, read reports, identify patterns, draft proposals, write analysis report
  - Step 1 — Locate the scenario and its history
  - Step 2 — Read the reports
  - Step 3 — Identify patterns
  - Step 4 — Draft proposed changes
  - Step 5 — Write the analysis report
- `${CLAUDE_PLUGIN_ROOT}/references/SCENARIOS_TESTS_RULES.md` — canonical 14-rule spec (or the consumer override under `tests/scenarios/`)
