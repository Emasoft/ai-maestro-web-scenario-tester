---
name: amwst-run-scenario
description: >-
  Run ONE (or several) UI scenario test end-to-end in an isolated forked
  subagent context. Use when the user says "run scenario N", "execute
  SCEN-018", "run the maintainer scenario", "test scenario 1", "rerun 1 and
  19", "run the title-change scenario", or anything that names a SCEN file.
  Forks one amwst-scenario-runner per scenario to drive the running web app
  via dev-browser and returns only a 2-line summary.
argument-hint: scenario-number-or-name [more numbers]
disable-model-invocation: false
context: fork
model: opus
agent: web-scenario-tester-main-agent
---

# Run Scenario — single-scenario trigger

## Overview

You are the single-scenario dispatcher. The user names one or more scenarios; you resolve each to its `.scen.md` file and fork the `amwst-scenario-runner` agent **once per scenario** — in parallel when there are several — so each ~150-step UI walkthrough runs in its own isolated context and returns only a 2-line summary. You do NOT drive the UI yourself; the forked runner does.

The run is **two agents per scenario**: the `amwst-scenario-runner` writes ONLY the Rule 9 report and returns its `Report:` path; then you fork an `amwst-scenario-proposer` for that scenario, passing the runner's report path, and IT writes the Rule 11 11th-HOUR proposals and returns its `Improvements:` path. The runner no longer writes the proposals — the proposer does.

For unattended batch / range / `--improve` execution, use `amwst-run-scenarios-batch` instead — this skill is for explicitly-named one-off runs.

## Write-guard sentinel (you OWN it — activate at start, deactivate at end)

This plugin ships a PreToolUse **write-guard** hook (`hooks/hooks.json` →
`scripts/amwst_subagent-write-guard.sh`) that stops scenario subagents from
writing outside the project root / scratch. Because it is plugin-scoped it would
otherwise fire in *every* session, so it is **SENTINEL-GATED**: it does nothing
unless a run-sentinel file exists. **As the run owner, you create that sentinel
at run START and delete it at run END** — that is what arms the guard for the
duration of the run and disarms it afterward.

Sentinel path (gitignored): `${CLAUDE_PROJECT_DIR}/.claude/scenario_is_running.json`

- **At run START (before forking any `amwst-scenario-runner`):**
  1. Ensure the consumer `.gitignore` ignores the sentinel (idempotent — append
     the line `.claude/scenario_is_running.json` only if it is not already
     present; never `git add -A`):
     ```bash
     GI="${CLAUDE_PROJECT_DIR}/.gitignore"
     grep -qxF '.claude/scenario_is_running.json' "$GI" 2>/dev/null \
       || printf '%s\n' '.claude/scenario_is_running.json' >> "$GI"
     ```
  2. Write the sentinel:
     ```bash
     mkdir -p "${CLAUDE_PROJECT_DIR}/.claude"
     printf '{"scenario": "%s", "startedAt": "%s", "owner": "amwst-run-scenario"}\n' \
       "$SCEN_ID" "$(date -u +%Y-%m-%dT%H:%M:%SZ)" \
       > "${CLAUDE_PROJECT_DIR}/.claude/scenario_is_running.json"
     ```
     (For several scenarios in one dispatch, one sentinel covers the whole
     dispatch — set `scenario` to a comma-joined id list or `multiple`.)
- **At run END (success, fail, OR abort/cleanup — ALWAYS):** delete it so the
  guard is never left armed for ordinary work:
  ```bash
  rm -f "${CLAUDE_PROJECT_DIR}/.claude/scenario_is_running.json"
  ```
  Make this the LAST thing you do even when a runner returns FAIL or you abort
  early — a leftover sentinel keeps the write-guard active for every later
  (non-scenario) session in this project.

## Prerequisites

- Scenario files at `${CLAUDE_PROJECT_DIR}/tests/scenarios/SCEN-NNN_*.scen.md` (the scenarios folder is configurable via `scenarios.config.json` `scenariosDir`; default `tests/scenarios/`; scenario files always carry the `.scen.md` extension)
- The `dev-browser` plugin available (the browser engine — the runner loads it via the `dev-browser:dev-browser` skill)
- The target web app running and healthy
- Scenario rules file (bundled or project override)

## When the user says…

| User phrase | Scenario file(s) to run |
|-------------|-------------------------|
| "run scenario 16" / "run SCEN-016" | resolve via `${CLAUDE_PROJECT_DIR}/tests/scenarios/SCEN-016_*.scen.md` |
| "run the maintainer scenario" | glob the scenarios folder for a `*.scen.md` whose name or `name:` frontmatter matches "maintainer" |
| "rerun the title scenario" | glob for the `.scen.md` matching "title" |
| "test SCEN-019" | resolve `SCEN-019_*.scen.md` |
| "rerun 1 and 19" / "run 16, 18, 19" | resolve EACH number to its `SCEN-<padded>_*.scen.md`; fork one runner per scenario, in parallel |

If the user names multiple scenarios, fork ONE `amwst-scenario-runner` agent **per scenario, in parallel** — never serialize. Each fork gets its own ~150-step budget without contaminating the main conversation. Resolve a by-name match by globbing `${CLAUDE_PROJECT_DIR}/tests/scenarios/*.scen.md` and matching the filename slug or the `name:` frontmatter; if more than one matches, ask the user to disambiguate.

## Instructions

### Checklist

Copy this checklist and track your progress:

- [ ] Parse `$ARGUMENTS` into a list of scenario identifiers (numbers and/or names)
- [ ] Resolve each identifier to its `.scen.md` file via glob; report any that don't resolve
- [ ] Resolve the canonical rules-file path (consumer override else bundled)
- [ ] **Activate the write-guard:** ensure `.gitignore` ignores the sentinel, then write `.claude/scenario_is_running.json`
- [ ] Fork `amwst-scenario-runner` once per scenario (parallel for multiple) via the Agent tool
- [ ] Collect each runner's 2-line summary, capturing its `Report:` path
- [ ] For each returned report, fork `amwst-scenario-proposer` (parallel for multiple) via the Agent tool, passing the scenario path + project dir + the runner's report path
- [ ] Collect each proposer's 2-line summary, capturing its `Improvements:` path
- [ ] **Deactivate the write-guard:** delete `.claude/scenario_is_running.json` (always — even on FAIL/abort)
- [ ] Return the per-scenario summaries to the user — BOTH the `Report:` and `Improvements:` lines (do NOT paste report bodies)

### Workflow

1. Parse `$ARGUMENTS` into a list of scenario identifiers (numbers like `16`, padded IDs like `SCEN-016`, or names like "maintainer").
2. Resolve each identifier to its scenario file via glob. If an identifier does not resolve, report it and skip that one (do not abort the others).
3. Resolve the rules-file path: prefer `${CLAUDE_PROJECT_DIR}/tests/scenarios/SCENARIOS_TESTS_RULES.md` if it exists, else `${CLAUDE_PLUGIN_ROOT}/references/SCENARIOS_TESTS_RULES.md`.
4. **Activate the write-guard (run START):** ensure the sentinel is gitignored, then write `${CLAUDE_PROJECT_DIR}/.claude/scenario_is_running.json` (see "Write-guard sentinel" above). This ARMS the plugin's sentinel-gated write-guard for the whole run.
5. For EACH resolved scenario, spawn an `amwst-scenario-runner` agent via the Agent tool (see runner spawn template below). When there is more than one scenario, issue all the Agent calls in the SAME turn so they run in parallel.
6. Collect the 2-line summary each runner returns, and parse out its `Report:` path.
7. For EACH runner that returned a report, spawn an `amwst-scenario-proposer` agent via the Agent tool (see proposer spawn template below), passing the scenario file path, `${CLAUDE_PROJECT_DIR}`, and that runner's report path. When several reports came back, issue all the proposer Agent calls in the SAME turn so they run in parallel too.
8. Collect the 2-line summary each proposer returns, and parse out its `Improvements:` path.
9. **Deactivate the write-guard (run END):** delete `${CLAUDE_PROJECT_DIR}/.claude/scenario_is_running.json`. Do this ALWAYS — after success, after FAIL, and on any early abort/error path — so the guard is never left armed for ordinary work. It is the LAST thing you do, after both the runner and proposer summaries are collected.
10. Return the per-scenario summaries to the user — BOTH the runner's `Report:` line AND the proposer's `Improvements:` line. Do not paste report content, step tables, or screenshots inline — just the summaries and the paths.

### Rules reference

Canonical rules file: `${CLAUDE_PLUGIN_ROOT}/references/SCENARIOS_TESTS_RULES.md` (the bundled canonical copy of the 14 mandatory rules — Rule 6 STICK-TO-UI, Rule 8 DEV-BROWSER, Rule 10 PHOTOSTORY, Rule 11 11th-HOUR, Rule 12 SUDO-MODE, Rule 13 AUTONOMOUS-PROTOCOL, Rule 14 REPORTS-TO-PROJECT-ROOT). A consuming project MAY override it at `${CLAUDE_PROJECT_DIR}/tests/scenarios/SCENARIOS_TESTS_RULES.md` — prefer the consumer copy when it exists, else the bundled one. Pass the resolved path into every runner prompt.

### Agent spawn templates

The run is two agents per scenario, in order: first the `amwst-scenario-runner` (writes ONLY the Rule 9 report), then the `amwst-scenario-proposer` (reads that report + the scenario and writes the Rule 11 11th-HOUR proposals). Both agents are defined in the plugin's `agents/` folder and carry their own fork-isolation + opus model in their frontmatter — you do not set those here, you just spawn them.

**1. Runner spawn template** — one per scenario, in parallel for multiple:

```
Agent(
    description: "Run SCEN-<NNN>",
    subagent_type: "amwst-scenario-runner",
    prompt: "Run the UI scenario at <absolute-path-to-SCEN-NNN_*.scen.md>. Project: ${CLAUDE_PROJECT_DIR}. Rules file: <resolved-rules-path>. Follow the 14 rules end-to-end: read the rules + the scenario, do Phase 0 SAFE-SETUP (git status, STATE-WIPE backup, health check, baseline screenshot), execute every step via the dev-browser plugin (load the dev-browser:dev-browser skill; take a fresh snapshotForAI before each action; screenshot every step), apply Rule 4 FIX-AS-YOU-GO for any bug, handle the Rule 12 sudo modal on strict ops, run the CLEANUP phase via the UI, write ONLY the Rule 9 report under ${CLAUDE_PROJECT_DIR}/reports/scenarios-runner/ (do NOT write the 11th-hour proposals — a separate proposer agent does that). Return ONLY the 2-line summary, including the `Report:` path."
)
```

**2. Proposer spawn template** — one per returned report, AFTER the runner hands back its `Report:` path, in parallel for multiple:

```
Agent(
    description: "Propose SCEN-<NNN>",
    subagent_type: "amwst-scenario-proposer",
    prompt: "Read the scenario at <absolute-path-to-SCEN-NNN_*.scen.md> and the runner's Rule 9 report at <runner-report-path>. Project: ${CLAUDE_PROJECT_DIR}. Do the Rule 11 11th-HOUR deep analysis: from the report's bugs, issues, and observed behavior, write concrete improvement proposals (bug fixes, API/script/plugin improvements, workflow/governance rule changes, new scenarios), each with problem, root cause, proposed change, and priority P0-P3. Write them to ${CLAUDE_PROJECT_DIR}/reports/scenarios-runner/scenario_proposed-improvements_<NNN>_<timestamp>.md. Return ONLY the 2-line summary, including the `Improvements:` path."
)
```

When the user names several scenarios, emit one runner `Agent(...)` call per scenario in a single turn (parallel); then, once each runner returns its report path, emit one proposer `Agent(...)` call per report in a single turn (parallel).

## Output

Return only the per-scenario summaries — one block per scenario, combining the runner's verdict + `Report:` line with the proposer's `Improvements:` line:

```
[PASS|FAIL|PARTIAL] SCEN-<NNN> — <one-line result>            ← from the runner
Report: ${CLAUDE_PROJECT_DIR}/reports/scenarios-runner/SCEN-<NNN>_<timestamp>.report.md   ← from the runner
[PROPOSALS] SCEN-<NNN> — <N proposals (a P0, …)>             ← from the proposer
Improvements: ${CLAUDE_PROJECT_DIR}/reports/scenarios-runner/scenario_proposed-improvements_<NNN>_<timestamp>.md   ← from the proposer
```

Do NOT paste the report body, proposal body, step tables, or screenshots into the main conversation.

## Error Handling

| Error | Action |
|-------|--------|
| Identifier does not resolve to a `.scen.md` file | Report it, list the scenarios that DO exist, skip that one, continue the rest |
| Ambiguous by-name match (more than one file) | Ask the user to disambiguate by number; do not guess |
| Runner returns FAIL | Surface the runner's 2-line FAIL summary + report path; do not retry silently. Still fork the proposer on the report so its 11th-HOUR analysis runs on the failure evidence |
| Proposer fails / returns no `Improvements:` path | Surface the runner's `Report:` line anyway; note the proposals are missing; do not retry silently |
| Target app not running / unhealthy | The runner reports it during Phase 0 SAFE-SETUP — surface that summary to the user |

## Examples

```
/amwst-run-scenario 16
/amwst-run-scenario SCEN-018
/amwst-run-scenario the maintainer scenario
/amwst-run-scenario 1 19
```

**Example — single scenario.** User: "run scenario 16" → resolve `SCEN-016_*.scen.md`, fork one `amwst-scenario-runner`; when it returns its `Report:` path, fork one `amwst-scenario-proposer` on that report; return both 2-line summaries.

**Example — parallel.** User: "run 16, 18, 19" → resolve all three, emit three `Agent(amwst-scenario-runner, ...)` calls in one turn (parallel), collect three `Report:` paths; then emit three `Agent(amwst-scenario-proposer, ...)` calls in one turn (parallel) on those reports; return six 2-line summaries (a runner + a proposer pair per scenario).

## Hard rules

1. **Do NOT drive the UI yourself.** This skill only resolves files and forks the `amwst-scenario-runner` and `amwst-scenario-proposer` agents; all browser actions happen inside the runner fork via dev-browser (Rule 8 DEV-BROWSER — chrome-devtools MCP is deprecated and must NOT be used).
2. **Runner FIRST, then proposer.** Per scenario, the `amwst-scenario-runner` writes ONLY the Rule 9 report; the separate `amwst-scenario-proposer` writes the Rule 11 11th-HOUR proposals AFTER the runner returns its report path. The runner does NOT write proposals.
3. **One fork per scenario per phase; parallel for multiple.** Never serialize independent scenarios into one fork — spawn runners in parallel, then proposers in parallel.
4. **Reports and proposals land under `${CLAUDE_PROJECT_DIR}/reports/scenarios-runner/`** (Rule 14), never inside the scenarios folder or a worktree-local path.
5. **Return only the 2-line summaries** (the runner's + the proposer's, per scenario). Never paste report bodies, proposal bodies, step tables, or screenshots inline.

## Resources

- `${CLAUDE_PLUGIN_ROOT}/references/SCENARIOS_TESTS_RULES.md` — canonical 14-rule spec (or the consumer override under `tests/scenarios/`)
- The `amwst-scenario-runner` agent — the forked worker that executes one scenario end-to-end and writes the Rule 9 report
- The `amwst-scenario-proposer` agent — the forked worker that reads a scenario's report and writes its Rule 11 11th-HOUR proposals
- The `dev-browser:dev-browser` skill — the browser engine the runner drives (sandboxed JS piped to the dev-browser CLI; persistent named pages across invocations)
