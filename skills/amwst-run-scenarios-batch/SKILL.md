---
name: amwst-run-scenarios-batch
description: >-
  Use when the user wants unattended batch execution of scenario files.
  Trigger with "run scenarios 16-20" or "batch 5-10 --improve". Accepts a
  range, comma list, or single number.
argument-hint: range [--improve]
disable-model-invocation: false
model: opus
---

# Run Scenarios Batch — the conductor

## Overview

You are the conductor for unattended UI scenario batches. Orchestration only — you parse the range, spawn `amwst-scenario-runner` subagents, aggregate results. The `amwst-scenario-improvement-implementer` subagent (if `--improve`) needs `isolation: worktree`.

## Write-guard sentinel (batch owns it: master-setup → master-cleanup)

The plugin ships a sentinel-gated PreToolUse **write-guard**
(`hooks/hooks.json` → `scripts/amwst_subagent-write-guard.sh`) that confines
scenario subagents to the project root / scratch. It is INERT unless the
run-sentinel `${CLAUDE_PROJECT_DIR}/.claude/scenario_is_running.json` exists.
**For a batch, the sentinel spans the WHOLE batch** — you ARM it once at
master-setup (before the main loop) and disarm it once at master-cleanup (after
the loop), so every runner subagent in between is guarded.

- **master-setup (run START, before the main loop):** ensure the sentinel is
  gitignored (idempotent `.gitignore` append of `.claude/scenario_is_running.json`),
  then write it:
  ```bash
  GI="${CLAUDE_PROJECT_DIR}/.gitignore"
  grep -qxF '.claude/scenario_is_running.json' "$GI" 2>/dev/null \
    || printf '%s\n' '.claude/scenario_is_running.json' >> "$GI"
  mkdir -p "${CLAUDE_PROJECT_DIR}/.claude"
  printf '{"scenario": "batch-%s", "startedAt": "%s", "owner": "amwst-run-scenarios-batch"}\n' \
    "$RANGE" "$(date -u +%Y-%m-%dT%H:%M:%SZ)" \
    > "${CLAUDE_PROJECT_DIR}/.claude/scenario_is_running.json"
  ```
- **master-cleanup (run END, after the loop / aggregation):** delete it so the
  guard is disarmed for ordinary work. For **autonomous** batches (Rule 13) the
  bundled `master-cleanup.sh` already deletes it as its first step — so if you
  drive cleanup through that script you are covered; otherwise delete it
  yourself:
  ```bash
  rm -f "${CLAUDE_PROJECT_DIR}/.claude/scenario_is_running.json"
  ```
  Disarm on EVERY exit path (success, abort after a failed preflight, or any
  error) — a leftover sentinel keeps the write-guard armed for later sessions.

## Prerequisites

- A project with `${CLAUDE_PROJECT_DIR}/tests/scenarios/SCEN-NNN_*.scen.md` files (the scenarios folder is configurable via `scenarios.config.json` `scenariosDir`; default `tests/scenarios/`)
- The `dev-browser` plugin available (the browser engine — loaded via the `dev-browser:dev-browser` skill)
- The target web app running and healthy
- Optional: `${CLAUDE_PROJECT_DIR}/tests/scenarios/scenarios.config.json` for preflight config

## Instructions

### Checklist

Copy this checklist and track your progress:

- [ ] Parse `$ARGUMENTS` into scenario IDs list and `improve` flag
- [ ] Run optional preflight (config file + health probe)
- [ ] **master-setup: ARM the write-guard** — gitignore + write `.claude/scenario_is_running.json`
- [ ] For each scenario: check resume state → run setup script → spawn runner subagent → spawn proposer subagent (reads the runner's report, writes the proposals file) → run cleanup script → log result
- [ ] Aggregate batch report
- [ ] If `--improve`: spawn implementer subagent for P0 proposals
- [ ] **master-cleanup: DISARM the write-guard** — delete `.claude/scenario_is_running.json` (always; `master-cleanup.sh` does this for autonomous batches)
- [ ] Return 3-line final summary

### Workflow

1. Parse `$ARGUMENTS` into scenario IDs list and `improve` flag.
2. Run optional preflight: read config file, probe health endpoint.
3. **master-setup — ARM the write-guard:** ensure the sentinel is gitignored, then write `${CLAUDE_PROJECT_DIR}/.claude/scenario_is_running.json` (see "Write-guard sentinel" above). This guards every runner subagent for the whole batch.
4. For each scenario: check resume state, run setup script, spawn the `amwst-scenario-runner` subagent (it writes ONLY the Rule 9 report and returns its Report path), then spawn the `amwst-scenario-proposer` subagent (it reads that report + the scenario and writes the 11th-HOUR proposals file), run cleanup script, log result.
5. Aggregate results into the batch report.
6. If `--improve`: spawn the implementer subagent for P0 proposals.
7. **master-cleanup — DISARM the write-guard:** delete `${CLAUDE_PROJECT_DIR}/.claude/scenario_is_running.json` (for autonomous batches `master-cleanup.sh` already does this first). Do it on every exit path — including an aborted batch after a failed preflight.
8. Return a 3-line final summary.

### Rules reference

Canonical rules file: `${CLAUDE_PLUGIN_ROOT}/references/SCENARIOS_TESTS_RULES.md` (the bundled canonical copy of the 14 mandatory rules; Rule 13 = AUTONOMOUS-PROTOCOL, Rule 14 = REPORTS-TO-PROJECT-ROOT). A consuming project MAY override it at `${CLAUDE_PROJECT_DIR}/tests/scenarios/SCENARIOS_TESTS_RULES.md` — prefer the consumer copy when it exists, else the bundled one. Pass the resolved path into every subagent prompt.

### Argument formats

| Input | Expands to |
|-------|-----------|
| `18` | `ids=[18] improve=false` |
| `16-20` | `ids=[16,17,18,19,20] improve=false` |
| `16-20 --improve` | `ids=[16,17,18,19,20] improve=true` |
| `1,5,8 --improve` | `ids=[1,5,8] improve=true` |

See [Detailed Procedure](references/procedure-details.md) for all 6 steps, the subagent spawn template with full prompt format, and the improvement loop implementation.

## Output

```
BATCH_DONE <range> <P>/<F>/<X> <aggregated-report-path>
Per-scenario reports: <space-separated paths>
Improvements: <branch-name or "skipped">
```

Where `P` = pass, `F` = fail, `X` = partial.

Each scenario produces two files: the `amwst-scenario-runner` writes the Rule 9 report (`SCEN-NNN_<ts>.report.md`) and the `amwst-scenario-proposer` writes the 11th-HOUR proposals file (`scenario_proposed-improvements_NNN_<ts>.md`), both under `${CLAUDE_PROJECT_DIR}/reports/scenarios-runner/`.

Aggregated batch report is saved under the project-root `reports/` directory (Rule 14):
`${CLAUDE_PROJECT_DIR}/reports/scenarios-runner/scenario-batch-<range>_<timestamp>.md`

Progress log is appended to:
`${CLAUDE_PROJECT_DIR}/tests/scenarios/state/batch-progress.log`

## Error Handling

| Error | Action |
|-------|--------|
| Scenario file missing | Skip, log `SCENARIO_MISSING <N>` in progress log, continue |
| Preflight health probe fails | Log failure, abort batch with clear error |
| Subagent returns FAIL | Log in progress log, continue to next scenario |
| Implementer returns IMPLEMENTATIONS_FAIL | Log reason in batch report, do not abort |

## Examples

```
/amwst-run-scenarios-batch 18
/amwst-run-scenarios-batch 16-20
/amwst-run-scenarios-batch 1,5,8,12 --improve
/amwst-run-scenarios-batch 16-20 --improve
```

## Resources

- [Detailed Procedure](references/procedure-details.md) — full 6-step procedure with preflight, main loop, improvement loop, and final output format
  - Step 1 — Parse arguments
  - Step 2 — Optional preflight
  - Step 3 — Main loop
  - Step 4 — Aggregate the batch report
  - Step 5 — Optional improvement loop
  - Step 6 — Final output
