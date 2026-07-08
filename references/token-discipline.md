# Token discipline — keep every run cheap (mandatory)

A UI scenario run is the most token-expensive thing this plugin does: **cost ≈
turns × per-turn-context**, because the whole transcript is re-read on every
turn, so a careless run can balloon to **100M+ tokens** (a snapshot or
screenshot read once rides forward and is re-charged on every later turn). The
forked scenario runner also inherits a large base floor (the project rules + the
loaded skills), so it needs a **1M-context model** to launch at all — which
makes the model expensive, which makes the discipline below LOAD-BEARING, not
optional. These eight techniques hold for every run; the
`amwst-scenario-runner` enforces them per step.

1. **Minimize turns.** Drive a group of deterministic, known-outcome steps (a
   wizard page, a cleanup sequence) in ONE dev-browser call that stops at the
   first failed assertion — not one call per step (each call is a turn, and
   turns are a linear cost multiplier); use **amwst-step-batch** for the
   pattern. Break the turn only to read fresh UI state or to diagnose a failure.
2. **Control load order — fixed-first, volatile-last.** Read the inputs that
   never change (the rules, the scenario file, memory) ONCE upfront so they sit
   in the cached prefix; never re-read a fixed input mid-run (a re-read appends
   a second copy that rides forward every turn — recall it instead). Keep
   volatile observations (snapshots, screenshots, tool output) at the tail and
   DROP them after extracting the fact. The more often a thing changes, the
   later you read it.
3. **Scoped source reads — never whole files.** To read a scenario step, use
   `${CLAUDE_PLUGIN_ROOT}/scripts/amwst-scenario-step.sh <scen.md> S<NNN>` (or
   `list`/`phases`) — never re-read the whole `.scen.md`. To diagnose a bug,
   locate the symbol (a structure/symbol search → file:line) then read ONLY that
   body with a ranged read; a whole >300-line file read rides forward every
   turn. Do NOT load an MCP server into the runner just for reads — its tool
   schemas cost ~80–120K of base context re-read every turn, which defeats the
   goal; a plain CLI symbol search + ranged read gives the same result at zero
   MCP cost.
4. **Errors-only test/lint/type-check output.** Never pipe raw `tsc` / `eslint`
   / `vitest` / `pytest` / linter / log output into context — the passes,
   progress bars, and banners ride forward every turn. Run each through
   `${CLAUDE_PLUGIN_ROOT}/scripts/amwst-leantool.py tsc|eslint|vitest|pytest|log <args>`,
   which emits ONLY a count + one line per real error (`file:line  CODE  msg`)
   and mirrors the tool's exit code, never swallowing a real failure.
5. **Screenshot discipline.** Take few screenshots, and capture the element's
   clip box plus a small margin — never the whole page; use
   **amwst-region-capture** for clipped screenshots and scoped aria snapshots.
   For the rare genuinely-global overview, FIRST shrink the viewport to the
   smallest size that still shows the relationship you're checking, capture,
   then restore it.
6. **dev-browser only — never read raw page text, CSS, or JS into context.**
   Drive and verify through dev-browser: a *scoped* accessibility snapshot
   (text) for "is it open / did it change / is it enabled", a clipped screenshot
   for pixels. Do not `Read`/`cat` a stylesheet or script to "check styling" and
   do not snapshot a terminal/log pane's full on-page text — read ONE computed
   value with `getComputedStyle(el).<prop>` instead.
7. **Never read logs raw.** Extract ONLY the error/fail/exception lines from a
   log (a small grep/wrapper that prints the matches + a count and tails the
   rest) — never `tail`/`cat` the whole file into context.
8. **Concise + DRY reports.** Be exhaustive AND concise — cover every bug,
   issue, and proposal with no filler. Define each non-obvious concept ONCE
   (don't assume the reader shares your run context), then refer back, never
   restate. One row per step in the step table; no prose that re-narrates the
   table; no pasted code longer than the few lines that carry the point.
