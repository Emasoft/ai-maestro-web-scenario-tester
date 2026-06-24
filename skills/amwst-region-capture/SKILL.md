---
name: amwst-region-capture
description: >-
  Token-cheap visual verification for UI scenarios. Capture DOM/ARIA-scoped
  CLIPPED screenshots (target element + margin) and SCOPED aria snapshots instead
  of full-page captures — using the live ARIA/DOM tree as the guide for what to
  clip. Use whenever a scenario step must visually check CSS/layout (truncated
  text, misaligned elements, wrong gradient, missing highlight/focus ring,
  elements bleeding out of their container, obstructing overlays). Preloaded via
  the amwst-scenario-runner skills frontmatter.
disable-model-invocation: true
---

# Region Capture — DOM/ARIA-guided, token-cheap visual checks

## Why this exists

A full-page screenshot is ~1,365 tokens (a retina page resizes to the ~1.15MP cap
≈ ~1,540); a full-page `snapshotForAI()` accessibility tree is 5–20K tokens. Both
land in the append-only transcript and are **re-read every later turn**, so over a
long run they dominate cost. The fix is NOT to stop verifying — CSS bugs are
invisible to text and genuinely need pixels. The fix is to **observe only the
region under test**, located via the DOM/ARIA tree. Image tokens scale with area
`(w·h)/750`, so clipping collapses the cost:

| capture | tokens |
|---|---|
| full page (1280×800) | ~1,365 |
| sidebar div (300×800) | ~320 |
| toolbar (1280×80) | ~137 |
| one button + 24px margin | ~37 |
| **scoped aria subtree (text)** | **~0.2–2K vs 5–20K full** |

## The principle: the ARIA/DOM tree is the map

You already discover the page via `snapshotForAI()` — that IS the ARIA map. Pick
the region to verify **by role + accessible name** (the `toolbar`; the `dialog`
named "Delete item"; the `navigation`), resolve it to a bounding box from the live
DOM, clip to it. Never guess pixel coordinates; never capture the whole page unless
the check is truly global.

## Decision order (cheapest first)

1. **Can the accessibility tree answer it?** (present? enabled? what text? what
   aria-state?) → `scopedAria(target)` — TEXT, no image. **Most checks stop here.**
2. **Does it need pixels?** (gradient, alignment, truncation, bleed, focus ring,
   z-index) → `captureRegion(target, {margin})` — a clipped image of that element.
3. **Is the check genuinely page-wide?** (cross-viewport stacking, modal obscuring
   everything) → `captureLandmarks()` — N small per-landmark clips, not one big
   page. A bare full-page `page.screenshot()` is the last resort; if you must take
   one, shrink the viewport first.

## Defect → what to capture

| defect | target | margin |
|---|---|---|
| truncated text/line-clamp, wrong gradient, missing highlight, focus ring | the element | small (~16px) |
| misaligned siblings | the parent container holding them | ~16–24px |
| **bleed-out / overflow / clipped shadow** | the element | **generous (~32px) — the margin IS the test** |
| obstructing overlay / z-index / modal-over-page | the overlap region, or `captureLandmarks()` | ~16px |

## The helper — `references/region-capture.js`

The implementation lives in [`references/region-capture.js`](references/region-capture.js).
**Read that file ONCE at your first capture in a run, then paste the function(s)
you need into your dev-browser `<<'EOF' … EOF` script and call them against the
live `page`.** (It is kept out of this SKILL body on purpose — loading code you
aren't using yet would defeat the token saving this skill exists for.)

API (all accept a `target` of `{selector}` | `{role, name?}` | `{text}`):

- `await scopedAria(page, target)` → a compact ARIA text tree of just that subtree.
  The DEFAULT for verification.
- `await captureRegion(page, target, {margin=24, path})` → clipped screenshot of
  the element + margin (saved to `path`, or returned as a buffer).
- `await captureLandmarks(page, {margin=16, dir, runTag})` → one small clip per
  ARIA landmark (banner/navigation/main/complementary/contentinfo/dialog) — use
  instead of a full-page shot for global checks.

It uses only portable primitives (`page.evaluate`, `page.screenshot({clip})`) with
a try/catch fast-path for `locator.ariaSnapshot()`, so it works regardless of which
Playwright surface the dev-browser build exposes.

## Integration with the scenario runner

- This **replaces** a bare full-page `page.screenshot()` for any **verification**
  capture.
- Default to `scopedAria()`; reach for `captureRegion()` only for genuinely
  pixel-level checks.
- A clipped image is the right input for a vision model/agent — send it the
  ~40–320-token clip + one focused question, not a full page.
- Save clips under the per-run dir (see `amwst-scenarios-rules` Rule 10:
  `reports/scenarios-runner/screenshots/SCEN-<NNN>_<RUN_ID>/`), then DROP the image
  from your working context — do not re-read it unless a later step genuinely needs it.

## API notes

- `page.screenshot({clip})` and `page.evaluate(fn, arg)` are core Playwright and
  reliably present in the sandbox.
- `locator.ariaSnapshot()` / `getByRole()` are newer; the helper only uses them on a
  try/catch fast path and falls back to `page.evaluate`, so nothing breaks.
- If `page.viewportSize()` is absent the helper defaults to 1280×800 — override for
  `device: tablet`/`smartphone` scenarios.
