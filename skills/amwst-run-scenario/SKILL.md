---
name: amwst-run-scenario
description: >-
  Run ONE (or several) UI scenario test end-to-end in an isolated forked
  subagent context so the main conversation never pays for the ~150-step UI
  walkthrough. Use when the user says "run scenario N", "execute SCEN-018",
  "run the maintainer scenario", "test scenario 1", "rerun 1 and 19", "run the
  title-change scenario", or anything that names a SCEN file. Each forked
  amwst-scenario-runner agent reads its scenario file, follows the 14 rules in
  SCENARIOS_TESTS_RULES.md, drives the running web app via the dev-browser
  plugin, fixes any bug it finds mid-scenario before continuing, writes a
  structured report plus 11th-hour improvement proposals under
  reports/scenarios-runner/, and returns only a 2-line summary.
argument-hint: scenario-number-or-name [more numbers]
disable-model-invocation: false
model: opus
agent: web-scenario-tester-main-agent
---

# Run Scenario — single-scenario trigger

## Overview

You are the single-scenario dispatcher. The user names one or more scenarios; you resolve each to its `.scen.md` file and fork the `amwst-scenario-runner` agent **once per scenario** — in parallel when there are several — so each ~150-step UI walkthrough runs in its own isolated context and returns only a 2-line summary. You do NOT drive the UI yourself; the forked runner does.

For unattended batch / range / `--improve` execution, use `amwst-run-scenarios-batch` instead — this skill is for explicitly-named one-off runs.

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
- [ ] Fork `amwst-scenario-runner` once per scenario (parallel for multiple) via the Agent tool
- [ ] Collect each runner's 2-line summary
- [ ] Return the per-scenario summaries to the user (do NOT paste report bodies)

### Workflow

1. Parse `$ARGUMENTS` into a list of scenario identifiers (numbers like `16`, padded IDs like `SCEN-016`, or names like "maintainer").
2. Resolve each identifier to its scenario file via glob. If an identifier does not resolve, report it and skip that one (do not abort the others).
3. Resolve the rules-file path: prefer `${CLAUDE_PROJECT_DIR}/tests/scenarios/SCENARIOS_TESTS_RULES.md` if it exists, else `${CLAUDE_PLUGIN_ROOT}/references/SCENARIOS_TESTS_RULES.md`.
4. For EACH resolved scenario, spawn an `amwst-scenario-runner` agent via the Agent tool (see spawn template below). When there is more than one scenario, issue all the Agent calls in the SAME turn so they run in parallel.
5. Collect the 2-line summary each runner returns.
6. Return the per-scenario summaries to the user. Do not paste report content, step tables, or screenshots inline — just the summaries and the report paths.

### Rules reference

Canonical rules file: `${CLAUDE_PLUGIN_ROOT}/references/SCENARIOS_TESTS_RULES.md` (the bundled canonical copy of the 14 mandatory rules — Rule 6 STICK-TO-UI, Rule 8 DEV-BROWSER, Rule 10 PHOTOSTORY, Rule 11 11th-HOUR, Rule 12 SUDO-MODE, Rule 13 AUTONOMOUS-PROTOCOL, Rule 14 REPORTS-TO-PROJECT-ROOT). A consuming project MAY override it at `${CLAUDE_PROJECT_DIR}/tests/scenarios/SCENARIOS_TESTS_RULES.md` — prefer the consumer copy when it exists, else the bundled one. Pass the resolved path into every runner prompt.

### Agent spawn template

Each scenario is dispatched to its own forked `amwst-scenario-runner` agent. The runner agent is defined in the plugin's `agents/` folder and carries the fork-isolation + opus model in its own frontmatter — you do not set those here, you just spawn it:

```
Agent(
    description: "Run SCEN-<NNN>",
    subagent_type: "amwst-scenario-runner",
    prompt: "Run the UI scenario at <absolute-path-to-SCEN-NNN_*.scen.md>. Project: ${CLAUDE_PROJECT_DIR}. Rules file: <resolved-rules-path>. Follow the 14 rules end-to-end: read the rules + the scenario, do Phase 0 SAFE-SETUP (git status, STATE-WIPE backup, health check, baseline screenshot), execute every step via the dev-browser plugin (load the dev-browser:dev-browser skill; take a fresh snapshotForAI before each action; screenshot every step), apply Rule 4 FIX-AS-YOU-GO for any bug, handle the Rule 12 sudo modal on strict ops, run the CLEANUP phase via the UI, write the Rule 9 report + the Rule 11 11th-hour proposals under ${CLAUDE_PROJECT_DIR}/reports/scenarios-runner/. Return ONLY the 2-line summary."
)
```

When the user names several scenarios, emit one such `Agent(...)` call per scenario in a single turn so they run concurrently.

## Output

Return only the per-scenario summaries the runners hand back — one block per scenario:

```
[PASS|FAIL|PARTIAL] SCEN-<NNN> — <one-line result>
Report: ${CLAUDE_PROJECT_DIR}/reports/scenarios-runner/SCEN-<NNN>_<timestamp>.report.md
Improvements: ${CLAUDE_PROJECT_DIR}/reports/scenarios-runner/scenario_proposed-improvements_<NNN>_<timestamp>.md
```

Do NOT paste the report body, step tables, or screenshots into the main conversation.

## Error Handling

| Error | Action |
|-------|--------|
| Identifier does not resolve to a `.scen.md` file | Report it, list the scenarios that DO exist, skip that one, continue the rest |
| Ambiguous by-name match (more than one file) | Ask the user to disambiguate by number; do not guess |
| Runner returns FAIL | Surface the runner's 2-line FAIL summary + report path; do not retry silently |
| Target app not running / unhealthy | The runner reports it during Phase 0 SAFE-SETUP — surface that summary to the user |

## Examples

```
/amwst-run-scenario 16
/amwst-run-scenario SCEN-018
/amwst-run-scenario the maintainer scenario
/amwst-run-scenario 1 19
```

**Example — single scenario.** User: "run scenario 16" → resolve `SCEN-016_*.scen.md`, fork one `amwst-scenario-runner`, return its 2-line summary.

**Example — parallel.** User: "run 16, 18, 19" → resolve all three, emit three `Agent(amwst-scenario-runner, ...)` calls in one turn (parallel), collect three 2-line summaries.

## Hard rules

1. **Do NOT drive the UI yourself.** This skill only resolves files and forks `amwst-scenario-runner` agents; all browser actions happen inside the fork via dev-browser (Rule 8 DEV-BROWSER — chrome-devtools MCP is deprecated and must NOT be used).
2. **One fork per scenario; parallel for multiple.** Never serialize independent scenarios into one fork.
3. **Reports land under `${CLAUDE_PROJECT_DIR}/reports/scenarios-runner/`** (Rule 14), never inside the scenarios folder or a worktree-local path.
4. **Return only the 2-line summaries.** Never paste report bodies, step tables, or screenshots inline.

## Resources

- `${CLAUDE_PLUGIN_ROOT}/references/SCENARIOS_TESTS_RULES.md` — canonical 14-rule spec (or the consumer override under `tests/scenarios/`)
- The `amwst-scenario-runner` agent — the forked worker that executes one scenario end-to-end
- The `dev-browser:dev-browser` skill — the browser engine the runner drives (sandboxed JS piped to the dev-browser CLI; persistent named pages across invocations)
