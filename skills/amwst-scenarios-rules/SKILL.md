---
name: amwst-scenarios-rules
description: >-
  The 14 mandatory scenario rules every runner MUST follow.
  Use when running, editing, or implementing a scenario. Trigger
  with "run scenario NNN" or "execute SCEN-NNN", or preloaded via
  subagent skills frontmatter.
disable-model-invocation: true
---

# Scenarios Rules — 14 Mandatory Constraints

## Overview

Scenario rules for browser-driven UI testing of any web project. Every scenario runner and improvement implementer MUST follow them. Preloaded into subagents via the `skills:` frontmatter field, so the rules are always in context before the runner opens the scenario file.

Single source of truth: `${CLAUDE_PLUGIN_ROOT}/references/SCENARIOS_TESTS_RULES.md` (the bundled canonical text). A consuming project MAY override it with its own copy at `${CLAUDE_PROJECT_DIR}/tests/scenarios/SCENARIOS_TESTS_RULES.md` — prefer the consumer copy when it exists, else read the bundled one. Update the canonical doc, not this summary.

## Prerequisites

- Project with `tests/scenarios/SCEN-NNN_*.scen.md` files (the scenarios folder is configurable via `scenarios.config.json` `scenariosDir`; default `tests/scenarios/`)
- A running app under test with the `dev-browser` plugin available (the browser engine — Rule 8)

## Instructions

### Checklist

Copy this checklist and track your progress:

- [ ] Read the full rules at startup
- [ ] CLEAN-AFTER-YOURSELF at end of scenario
- [ ] Never mutate existing user resources (0-IMPACT)
- [ ] Backup configs at start (STATE-WIPE CHECKPOINT-SAVE)
- [ ] Fix bugs on the fly (FIX-AS-YOU-GO loop)
- [ ] Log every step and fix (TRACK-AND-REPORT)
- [ ] Never bypass the UI (STICK-TO-UI)
- [ ] Timestamp every screenshot (PHOTOSTORY)
- [ ] Do 11th-hour analysis at the end
- [ ] Write every report under the project-root `reports/` (REPORTS-TO-PROJECT-ROOT)

### The 14 rules (summary)

1. **CLEAN-AFTER-YOURSELF** — Revert to pre-test state. Undo efficiently, not step-by-step.
2. **0-IMPACT** — Never mutate existing user resources. Create test-prefixed elements, delete on cleanup.
3. **STATE-WIPE** — Backup config files at start, restore at end via UI first, files second.
4. **FIX-AS-YOU-GO** — STOP → DIAGNOSE → FIX → REBUILD → RETRY → LOOP → RESUME. No abandonment.
5. **TRACK-AND-REPORT** — Log every step, bug, issue in the scenario report with IDs, status, screenshots.
6. **STICK-TO-UI** — All interactions via browser. No curl mutations, no direct file edits, no bash deletions.
7. **SAFE-SETUP** — Commit, record hash, build, start server, verify health, kill orphans BEFORE Phase 1.
8. **DEV-BROWSER** — Drive the app via the `dev-browser` CLI (loaded via the `dev-browser:dev-browser` skill). Always snapshot the accessibility tree before interacting.
9. **REPORT-FORMAT** — Follow the structured markdown template with frontmatter, steps, bugs, verification.
10. **PHOTOSTORY** — Every step screenshot in timestamped dir+filename, JPEG 97%, never compress mid-session; auto-purge after a verified-fixed PASS.
11. **11th-HOUR** — Deep analysis + improvement proposals. This is the primary deliverable.
12. **SUDO-MODE** — Destructive ops may trigger a re-authentication prompt. Re-enter the credential and confirm.
13. **AUTONOMOUS-PROTOCOL** — How a long unattended overnight batch is structured (durable cron + idempotent state file + per-scenario heartbeat).
14. **REPORTS-TO-PROJECT-ROOT** — Every report/proposal/screenshot/log resolves under the MAIN project-root `reports/` (never a worktree-local path).

## Output

Preloaded skill — no direct output. Visible artifacts are the scenario report, timestamped screenshots, and improvement proposals file.

## Error Handling

| Violation | Action |
|-----------|--------|
| Rule 6 breach (about to use curl for cleanup) | STOP, find the UI path, or report as a BUG |
| Rule 10 breach (missing or untimestamped screenshot) | Redo the step with correct path, continue |
| Rule 4 breach (giving up on a failing step) | Re-enter the fix-retry loop, no abandonment |
| Rule 3 breach (file restore before UI delete) | Stop, delete via UI first, then compare files |
| Rule 14 breach (report written to a worktree-local path) | Re-resolve to the MAIN project-root `reports/` and rewrite |
| Any rule conflicts with a faster shortcut | Rules win. Rules cannot be weakened. |

## Examples

**Example 1 — Rule 6 cleanup**:
Input: runner needs to delete a test resource at end of scenario.
Output: open the resource's UI → delete control → confirm (re-authenticate if Rule 12 prompts) → confirm again.
Incorrect: issuing a direct DELETE request to the API from the command line — that bypasses the production surface and any re-auth gate.

**Example 2 — Rule 10 screenshot path**:
Input: step 14 of SCEN-009 at run time 2026-04-14T14:30:00Z.
Output: `${CLAUDE_PROJECT_DIR}/reports/scenarios-runner/screenshots/SCEN-009_20260414T143000Z/S014_20260414T143000Z_task-sent.jpg`
Incorrect: `screenshots/SCEN-009/baseline.png` — no timestamp, wrong format, cross-run contamination risk.

## Resources

- [references/SCENARIOS_TESTS_RULES.md](references/SCENARIOS_TESTS_RULES.md) — a pointer to the canonical rules doc bundled at the plugin root (`${CLAUDE_PLUGIN_ROOT}/references/SCENARIOS_TESTS_RULES.md`).
  - Where the canonical rules live
  - Consumer override location
- The canonical full-length doc at `${CLAUDE_PLUGIN_ROOT}/references/SCENARIOS_TESTS_RULES.md` carries the frontmatter format, device emulation presets, phase templates, directory structure, scenario file format, and the non-negotiable cleanup order. It contains all 14 rules:
  - Rule 0: Who you are in a scenario (you are the human user, not an agent)
  - Rule 1: CLEAN-AFTER-YOURSELF
  - Rule 2: 0-IMPACT
  - Rule 3: STATE-WIPE
  - Rule 4: FIX-AS-YOU-GO
  - Rule 5: TRACK-AND-REPORT
  - Rule 6: STICK-TO-UI
  - Rule 7: SAFE-SETUP
  - Rule 8: DEV-BROWSER
  - Rule 9: REPORT-FORMAT
  - Rule 10: PHOTOSTORY
  - Rule 11: 11th-HOUR
  - Rule 12: SUDO-MODE
  - Rule 13: AUTONOMOUS-PROTOCOL
  - Rule 14: REPORTS-TO-PROJECT-ROOT
- A consuming project MAY override the canonical doc at `${CLAUDE_PROJECT_DIR}/tests/scenarios/SCENARIOS_TESTS_RULES.md` (seeded by `init-scenarios-folder.sh` from the bundled copy). Prefer the consumer copy when present.
