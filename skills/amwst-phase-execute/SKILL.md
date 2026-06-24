---
name: amwst-phase-execute
description: >-
  The EXECUTE phase of a UI scenario run — how to drive the steps cheaply. The
  amwst-scenario-runner loads this when it reaches step execution (after
  SAFE-SETUP). Covers fixed-first load order, reading ONE step at a time with
  amwst-scenario-step.sh (never re-reading the whole .scen.md), scoped snapshots,
  the region-capture + step-batch helpers, per-step clipped screenshots, and
  sudo-modal handling. Token economy is the point — load only this phase.
disable-model-invocation: false
---

# Phase: EXECUTE — drive the scenario steps, cheaply

You enter this phase after SAFE-SETUP. Goal: perform every numbered step, verify
it, screenshot it — while keeping per-turn context tiny (cost = turns ×
per-turn-context, multiplied across ~150 steps).

## 1. Load order — read fixed inputs ONCE
The rules and the scenario frontmatter are FIXED — read them once at the start of
the run, never again. NEVER re-read the whole `.scen.md` each step (a re-read
appends a copy that rides forward every turn).

## 2. Read ONE step at a time (greppable — never the whole file)
The scenario is step-greppable. Get the id list once, then pull only the step you
are executing:
```bash
bash "${CLAUDE_PLUGIN_ROOT}/scripts/amwst-scenario-step.sh" <scen.md> list   # once: all step ids
bash "${CLAUDE_PLUGIN_ROOT}/scripts/amwst-scenario-step.sh" <scen.md> S007   # just S007's block
```
A step block carries **Action / Goal / Creates / Modifies / Verify**. Read S007,
do it, drop it; pull S008 next. The whole `.scen.md` never rides forward in context.

## 3. Per step: snapshot → act → verify → screenshot
1. **Snapshot SCOPED**, never whole-page — `snapshotForAI()` scoped to the subtree
   under test (use a track for incremental updates). A whole-page a11y tree is
   5–20K tokens and rides forward every turn.
2. **Act** via dev-browser Playwright methods.
3. **Verify** from the scoped a11y text (preferred) or a read-only state check.
4. **Screenshot** the region (not the page — §5), save to the per-run dir (§6),
   then DROP the image from context.

## 4. Batch deterministic step-groups into ONE turn
For a run of known-outcome steps (a wizard page, a cleanup sequence), drive the
whole group in one dev-browser call with the step-batch helper — it stops at the
first failed assertion, so FIX-AS-YOU-GO stays intact:
- read `${CLAUDE_PLUGIN_ROOT}/skills/amwst-step-batch/references/step-driver.js`
  once, paste `runSteps`, drive the group (see the `amwst-step-batch` skill).
Break the turn only when the next action depends on reading fresh UI state.

## 5. Verify visually with CLIPPED captures, not full pages
For any CSS/layout check, use the region-capture helper:
- read `${CLAUDE_PLUGIN_ROOT}/skills/amwst-region-capture/references/region-capture.js`
  once; `scopedAria()` (text, the default) / `captureRegion()` (clipped image) /
  `captureLandmarks()` (global). See the `amwst-region-capture` skill.
NEVER `Read`/`cat` a `.css`/`.js` source or snapshot a log/terminal pane's full
on-page text — read ONE computed value with `getComputedStyle(el).<prop>` instead.

## 6. Screenshots → the per-run dir (Rule 10)
`reports/scenarios-runner/screenshots/SCEN-<NNN>_<RUN_ID>/S<step>_<RUN_ID>_<desc>.jpg`
— one per step, clipped, dropped from context after saving.

## 7. Sudo / re-auth modals (Rule 12)
A destructive op may pop a password modal (`role="dialog" aria-modal="true"`),
possibly several times if the app uses one-shot tokens. For EACH occurrence: detect
the dialog via the scoped snapshot, fill the scenario's `governance_password`
(frontmatter), submit, wait for it to close. If the app under test has no such
modal, skip this.

## On a step failure
STOP and load `amwst-phase-fixasyougo` — do not continue past a broken step.
