---
name: amwst-phase-fixasyougo
description: >-
  The FIX-AS-YOU-GO phase of a UI scenario run — when a step fails because the app
  under test has a real bug, diagnose from real data, fix the root cause, rebuild,
  and retry the same step, cheaply. The amwst-scenario-runner loads this when a
  step assertion fails. Covers scoped source reading, the amwst-leantool.py
  errors-only wrappers for test/lint/typecheck and for logs, and the
  diagnose→fix→rebuild→retry loop. Distinct from the proposals phase.
disable-model-invocation: false
---

# Phase: FIX-AS-YOU-GO — fix the app bug, then resume

A step failed. First re-read the scoped snapshot to rule out a flaky selector; if
the app genuinely has a bug, fix the ROOT cause — no workarounds, no skipped steps
(fail-fast). Keep diagnosis context-cheap (this runs mid-scenario, every retained
blob rides forward).

## 1. Diagnose from real data — scoped, never whole files
- Read ONLY the failing step's block: `amwst-scenario-step.sh <scen.md> S<NNN>`.
- Read server logs with the lean wrapper — error lines only, never `tail`/`cat`:
  ```bash
  python3 "${CLAUDE_PLUGIN_ROOT}/scripts/amwst-leantool.py" log <logfile>
  ```
- Read the relevant SOURCE scoped: locate the symbol (your editor's symbol search
  / grep → file:line), then Read just that range with offset/limit. A whole
  >300-line file read rides forward in context every turn. Do NOT add an MCP server
  just for reads.
- Re-take a fresh SCOPED snapshot of the failing region.

## 2. Fix the root cause
Edit the app source with the Edit tool. Check your fix with the lean wrappers
(errors-only — never the raw tool's pass/progress/banner flood):
```bash
python3 "${CLAUDE_PLUGIN_ROOT}/scripts/amwst-leantool.py" tsc      # or: eslint | vitest | pytest
```
Each prints a count + one line per error and mirrors the tool's exit code (it never
swallows a real failure).

## 3. Rebuild + retry
Run the project's build + restart commands (from `tests/scenarios/scenarios.config.json`
or the conventional command for the stack), wait for health, then retry the SAME
step from the same state. Loop diagnose→fix→rebuild→retry until it passes (no
attempt cap).

## 4. Record it
- In the report: `file:line`, the root cause, and the step id that verified the fix.
- In the runner's MEMORY: a one-line pattern so the next run recognises it instantly.

Then return to `amwst-phase-execute` and continue with the next step.

## Not your job
The 11th-HOUR improvement PROPOSALS are written by a SEPARATE agent
(`amwst-scenario-proposer`, skill `amwst-phase-proposals`) AFTER the run — never
mix proposal-writing into this fix loop.

## Done when

- [ ] The previously failing step passes after the root-cause fix.
- [ ] The fix is recorded (report `file:line` + verifying step id, and a one-line MEMORY pattern).
- [ ] Execution resumes at the next step (back in `amwst-phase-execute`).
