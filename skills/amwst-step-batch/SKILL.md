---
name: amwst-step-batch
description: >-
  Run MANY scenario UI steps in ONE dev-browser call (one turn) instead of one
  tool-call per action. A declarative {action, assertion} step list executes
  sequentially in a single sandbox execution and STOPS at the first failed
  assertion, so FIX-AS-YOU-GO stays intact. Use to collapse the
  snapshot->act->screenshot->verify turn explosion in a scenario run. Preloaded
  via the amwst-scenario-runner skills frontmatter.
disable-model-invocation: true
---

# Step Batch — many steps, one turn

## Why
Cost = `turns × per-turn-context`. Each dev-browser Bash call is one **turn**, and a
scenario step is usually 3–4 calls (snapshot, act, screenshot, verify). A 40-step
scenario → 120–360 turns, each re-reading the full context. **Turns is a linear
cost multiplier** — collapsing the deterministic runs into one turn each cuts it
directly (target ≥40% fewer turns).

## What it does
A driver runs a declarative list of steps **inside one `<<'EOF' … EOF` dev-browser
execution** and returns a compact log `[{i, do, ok, detail?}]` — never raw
snapshots. It **stops at the first failed assertion**, so you always know exactly
which step broke and why, and diagnose from there (FIX-AS-YOU-GO).

## When to batch vs break the turn
- **Batch**: a run of deterministic actions with known expected outcomes (filling a
  wizard, a cleanup sequence, navigating to a page and confirming it loaded).
- **Break the turn (don't batch)**: when the NEXT action depends on reading a
  value/branching on UI state, or after a failure (to diagnose). Keep a batch to one
  logical group (e.g. one wizard page), not the whole scenario — over-batching hides
  where time/failures go.

## The helper — `references/step-driver.js`
Read [`references/step-driver.js`](references/step-driver.js) once at your first
batch, paste `runSteps` into your dev-browser script, call against `page`:

```
const log = await runSteps(page, [
  { do:'click', selector:'#open-form',            expect:{ visible:'[role=dialog]' } },
  { do:'fill',  selector:'#name', value:'scen-x', expect:{ value:{selector:'#name',equals:'scen-x'} } },
  { do:'click', selector:'button[type=submit]',   expect:{ text:'Saved' } },
], { timeout: 8000 })
// -> [{i:0,ok:true},{i:1,ok:true},{i:2,ok:false,detail:'Timeout ... waiting for text "Saved"'}]
```

Step `do`: `click | fill | press | goto | wait | check` (check = assertion-only).
`expect`: `{visible:sel} | {hidden:sel} | {text:'…'} | {value:{selector,equals}} | {role,name?}`.
Actions take a CSS `selector` (get it from your snapshot); `expect` may also match by
ARIA `{role,name}`. Portable Playwright primitives only (`page.click/fill/press/goto/
waitForSelector/waitForFunction`).

## Compose with the other levers
- Take ONE scoped `snapshotForAI()` (region-capture) at the start of a step group to
  get the selectors, then batch the group with `runSteps` — not a snapshot per action.
- Capture the per-run screenshot for the group with the `captureRegion` helper
  (clipped), saved to disk, NOT returned in the batch log.
- On a failure the log gives `{i, detail}`; THEN drop to single-step mode to diagnose
  and FIX-AS-YOU-GO.

## Notes
Confirm the dev-browser sandbox exposes `page.click/fill/press/goto/waitForSelector/
waitForFunction/waitForTimeout` (core Playwright; expected present). Add a `sudo` step
type if a password modal needs in-batch handling (otherwise break the turn for it).

## Done when

- [ ] The batch returns its compact log (every step `ok`), OR it stopped at the first failed assertion.
- [ ] On a stop, you have identified which step `{i}` broke and its `detail`.
