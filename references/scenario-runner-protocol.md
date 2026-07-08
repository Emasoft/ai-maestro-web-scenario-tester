# Scenario Runner — detailed phase protocol (A–H)

This is the full mechanical protocol behind the `amwst-scenario-runner` agent.
The agent body carries the compact phase map and the hard rules; this reference
carries every operational detail. **The runner reads this file ONCE at Phase A**
(fixed-first load order) via
`${CLAUDE_PLUGIN_ROOT}/references/scenario-runner-protocol.md`.

## Project configuration keys (scenarios.config.json)

All project-specific values are read from
`${CLAUDE_PROJECT_DIR}/tests/scenarios/scenarios.config.json`. Never hardcode any
of them. The keys the runner reads:

- `browserInstance` — the named `dev-browser` Chromium instance shared by every
  scenario in this project (so the persistent `dashboard` page logged in once at
  master setup is reused). Used in every `dev-browser --browser <browserInstance>`
  call.
- `dashboardUrl` — the base URL of the app under test (the page `dev-browser`
  navigates to).
- `healthEndpoint` — a URL that returns 200 when the server is up (used in
  prerequisite checks; reads only, never a mutation).
- `helpersScript` — path (relative to the project root) to the consumer-supplied
  dev-browser DOM helpers that implement this project's login / sudo-modal / CRUD
  flows. The plugin ships a template + the helper contract in `references/`; the
  consuming project provides the concrete script.
- `typeCheckCommand`, `buildCommand`, `testCommand`, `restartCommand` — the
  project's commands, used during FIX-AS-YOU-GO. If a key is absent, auto-detect
  from project markers (`package.json` → npm/yarn, `Cargo.toml` → cargo,
  `go.mod` → go, `pyproject.toml` → python).
- `scenariosDir` — directory holding the scenario `.scen.md` files (defaults to
  `tests/scenarios/`).
- `governancePasswordRef` — how to obtain the credential a destructive operation
  may require (the scenario's own `governance_password` frontmatter field is also
  authoritative per scenario).

If `scenarios.config.json` is missing, fall back to the scenario frontmatter for
per-scenario values (health endpoint, port, auth, password) and auto-detect build
commands — but a project that runs scenarios should ship this config.

## Phase A — Read the inputs

1. Read the project rules at
   `${CLAUDE_PROJECT_DIR}/tests/scenarios/SCENARIOS_TESTS_RULES.md` end-to-end.
   This is the canonical rule spec — the single source of truth, tracked in git
   alongside the scenario files themselves. The rules are non-negotiable. Rule 6
   STICK-TO-UI is the hardest — every mutation goes through the browser
   automation, never via shell or direct API call. If the consuming project has
   not provided its own copy, the canonical doc the plugin ships is at
   `${CLAUDE_PLUGIN_ROOT}/references/SCENARIOS_TESTS_RULES.md`; a consumer
   override at `${CLAUDE_PROJECT_DIR}/tests/scenarios/SCENARIOS_TESTS_RULES.md`
   takes precedence. The rule set: Rule 1 CLEAN-AFTER-YOURSELF, Rule 2 0-IMPACT,
   Rule 3 STATE-WIPE, Rule 4 FIX-AS-YOU-GO, Rule 5 TRACK-AND-REPORT, Rule 6
   STICK-TO-UI, Rule 7 SAFE-SETUP, Rule 8 DEV-BROWSER, Rule 9 REPORT-FORMAT,
   Rule 10 PHOTOSTORY, Rule 11 11th-HOUR, Rule 12 SUDO-MODE, Rule 13
   AUTONOMOUS-PROTOCOL, Rule 14 REPORTS-TO-PROJECT-ROOT, plus the "How-To:
   Running a Scenario" appendix.
2. Read this protocol reference (you are here) and the scenario's FRONTMATTER +
   step LIST only — not the whole file. The frontmatter (prerequisites, expected
   data, phases, cleanup, `governance_password`) is authoritative; get the step
   ids with `bash "${CLAUDE_PLUGIN_ROOT}/scripts/amwst-scenario-step.sh" <scen.md> list`.
   You pull each step's block on demand during Phase C (`… <scen.md> S<NNN>`) —
   never re-read the whole `.scen.md` each turn (token economy).
3. Read your own `MEMORY.md` for relevant prior-run context.
4. Verify prerequisites via Bash: the scenario's `prerequisites` list is testable
   (e.g., `which <cli>`, `curl -s -f <healthEndpoint>`, etc.). The health
   endpoint, port, and auth method come from `scenarios.config.json` or the
   scenario frontmatter — never hardcoded.

## Phase B — SAFE-SETUP (Rule 7)

The parent harness's master setup (per Rule 13) has already provisioned fixtures
and the dev-browser daemon is already running with the persistent `dashboard`
page logged in. Your per-scenario SAFE-SETUP is lighter:

1. `git status` to record `commit_start`
2. Generate a `RUN_ID` in ISO 8601 basic format:
   `RUN_ID=$(date -u +%Y%m%dT%H%M%SZ)`
3. **Heartbeat self-check (MANDATORY):** before doing anything else, look for a
   stale prior-run heartbeat at
   `${CLAUDE_PROJECT_DIR}/tests/scenarios/state/runner-heartbeat-SCEN-${NNN}.txt`.
   If the file exists:
   - **Fresh heartbeat (< 10 min old):** another runner is actively processing
     this scenario right now. Exit immediately with
     `[DUPLICATE-RUNNER-DETECTED] another runner heartbeat is fresh, refusing to
     double-dispatch`. Do NOT touch state.json. Do NOT proceed to setup.
   - **Stale heartbeat (≥ 10 min old):** a prior runner died. Per Rule 6
     (state-mutating bypass invalidates the run), the prior run is INVALIDATED.
     Delete the stale heartbeat file, log
     "RECOVERY <SCEN-NNN> resumed from stale-heartbeat" to `state/recovery.log`,
     and proceed to a fresh setup starting from S001 — never attempt to "resume"
     the prior run mid-step. Restart from the beginning, per Rule 6's
     invalidation semantics.
4. **Initial heartbeat write:** write the current epoch to the heartbeat file in
   this exact format (first-line `epoch=` is what `state-machine-tick.sh`
   parses):
   ```
   epoch=$(date +%s)
   scenario=SCEN-${NNN}
   phase=phase_b
   started_at=${RUN_ID}
   ```
5. **Run the per-scenario setup script (MANDATORY):** invoke
   ```
   bash "${CLAUDE_PROJECT_DIR}/tests/scenarios/scripts/setup-SCEN-${NNN}.sh"
   ```
   Capture stdout and stderr. The script ends with `SETUP_OK` on success or
   `SETUP_FAIL <reason>` on failure.

   **If the script fails (non-zero exit or any `SETUP_FAIL` line), the scenario
   MUST NOT start.** Diagnose the underlying cause and fix it — never bypass,
   never work around. Typical causes:
   - `git-fixture[n] <url> — expected local clone at <path>`: the fixture fork
     hasn't been cloned locally. Clone it and create the `scenario-start` tag,
     then retry setup.
   - `git-fixture[n] <path> missing tag 'scenario-start'`: the baseline tag is
     missing. Check out the author-intended baseline commit, tag it, retry.
   - `dir-fixture[n] <path> missing`: the scenario author must prepare the
     folder. If it's an author-error, add the folder with sensible baseline
     content, then retry.
   - `'yq' not on PATH`: install yq (`brew install yq`), retry.
   - Missing file in `rewipe-list`: correct the frontmatter path typo, retry.

   After every fix, re-run the setup script. Repeat until you get `SETUP_OK`.
   ONLY then proceed.
6. Sanity-check the dev-browser daemon by listing pages and confirming the
   `dashboard` page is on the `dashboardUrl` from `scenarios.config.json`. If
   not, the master setup is broken — abort with a clear error rather than trying
   to fix it yourself.
7. Take a baseline screenshot at
   `${MAIN_PROJECT_ROOT}/reports/scenarios-runner/screenshots/SCEN-${NNN}_${RUN_ID}/S000_${RUN_ID}_baseline.jpg`
   (Rule 14: `${MAIN_PROJECT_ROOT}` is the main repo root — resolve it per
   Phase G below).

## Phase C — Execute the scenario

**Load the execute-phase skill now:** `Skill(skill: "amwst-phase-execute")`. It
carries the full cheap-execution mechanics — fixed-first load order, reading ONE
step at a time via `amwst-scenario-step.sh`, scoped snapshots, the
region-capture + step-batch helpers, clipped per-step screenshots, and sudo
handling. Follow it for every step. The essentials (the skill expands each):

1. **Pull ONLY the step you're on** —
   `bash "${CLAUDE_PLUGIN_ROOT}/scripts/amwst-scenario-step.sh" <scen.md> S<NNN>`
   (its block carries Action / Goal / Creates / Modifies / Verify). Never re-read
   the whole `.scen.md`.
2. **Snapshot SCOPED** — `page.snapshotForAI()` (track: "main" after the first),
   scoped to the subtree under test, never whole-page.
3. **Act** via Playwright; **verify** from the scoped a11y text or a read-only
   state check (`curl GET` — reads allowed, writes not — Rule 6).
4. **Screenshot the REGION** (region-capture helper, clipped — not the full
   page) to
   `${MAIN_PROJECT_ROOT}/reports/scenarios-runner/screenshots/SCEN-${NNN}_${RUN_ID}/S<step>_${RUN_ID}_<short-desc>.jpg`,
   then DROP the image from context.
5. **Append a row** to the in-progress report (screenshot relative path).
6. **Heartbeat refresh (MANDATORY):** at every step boundary AND before any
   long-running operation (any wait > 60s, any sub-process call > 60s, any
   inter-agent message wait):
   ```
   cat > "${CLAUDE_PROJECT_DIR}/tests/scenarios/state/runner-heartbeat-SCEN-${NNN}.txt" <<HBEOF
   epoch=$(date +%s)
   scenario=SCEN-${NNN}
   phase=phase_c
   step=S<NNN>
   HBEOF
   ```
   Atomic write is fine — partial-line risk is acceptable because the cron's
   stale-detection is forgiving (>90 min default). The point is a freshness
   signal, not bullet-proof transactional state.

Batch deterministic step-groups into ONE dev-browser call (step-batch helper) to
cut turns. For the dev-browser API specifics, refer to the dev-browser skill
loaded at the start — the runner does NOT duplicate that documentation.

## Phase D — FIX-AS-YOU-GO (Rule 4)

When a step fails, **load the fix skill:**
`Skill(skill: "amwst-phase-fixasyougo")` and follow it. In short:

1. STOP — don't continue past the broken step (first re-read the scoped snapshot
   to rule out a flaky selector).
2. Diagnose SCOPED: the failing step block only
   (`amwst-scenario-step.sh … S<NNN>`); server logs via
   `python3 "${CLAUDE_PLUGIN_ROOT}/scripts/amwst-leantool.py" log <logfile>`
   (error lines only, never `tail`/`cat`); the relevant SOURCE read ranged
   (locate the symbol → offset/limit Read), never whole files.
3. Check `MEMORY.md` for a prior fix to the same pattern.
4. Edit the source with the Edit tool; check the fix with the lean wrappers:
   `python3 "${CLAUDE_PLUGIN_ROOT}/scripts/amwst-leantool.py" tsc|eslint|vitest|pytest`
   (errors only, exit-code faithful). Use `typeCheckCommand`/`testCommand` from
   `scenarios.config.json` when set, else auto-detect from project markers.
5. Build + restart (`buildCommand`/`restartCommand` from config, or the stack's
   conventional command), poll `healthEndpoint`, retry the SAME step. Loop
   diagnose→fix→retry until pass (no attempt cap).
6. Record the fix in the report (file:line, root cause, verifying step id) and
   note the recurring pattern as one line in your own project-memory notes
   (`MEMORY.md`).

## Phase E — Handle sudo / re-auth modals (Rule 12)

If the app implements a sudo / re-auth layer, destructive operations may trigger
a `role="dialog" aria-modal="true"` password modal, possibly multiple times in a
cleanup batch (one-shot tokens). Process each occurrence by calling the
project's sudo-modal helper from the `helpersScript` (the contract requires a
`<prefix>_sudo_modal`-style helper), passing the credential from the scenario's
`governance_password` frontmatter field (or `governancePasswordRef` from
config). If the app has no such layer, this phase is a no-op.

## Phase F — CLEANUP (Rules 1, 2, 3)

Execute the scenario's CLEANUP phase steps via the UI. The scenario file will
have numbered cleanup steps — follow them exactly. Cleanup is mandatory AND must
go through the UI (Rule 1).

After the UI cleanup, **run the per-scenario cleanup script**:

```
bash "${CLAUDE_PROJECT_DIR}/tests/scenarios/scripts/cleanup-SCEN-${NNN}.sh"
```

This delegates to `scenario-restore.sh` which verifies and replays the
`rewipe-list` MANIFEST (SHA256-integrity-checked file restore). If it exits
non-zero, diagnose and fix the underlying cause — never bypass.

Finally, take a post-test screenshot and compare with the baseline. Note any
drift in the report.

## Phase G — Report (Rules 9, 14)

**Resolve the main repo root first** (Rule 14 — write reports under the MAIN
repo root, never a worktree-local path):

```bash
if git rev-parse --is-inside-work-tree >/dev/null 2>&1; then
  MAIN_PROJECT_ROOT="$(git worktree list | head -n1 | awk '{print $1}')"
else
  MAIN_PROJECT_ROOT="$CLAUDE_PROJECT_DIR"
fi
```

Write the Rule 9 structured report under
`${MAIN_PROJECT_ROOT}/reports/scenarios-runner/`:

- `SCEN-NNN_<timestamp>.report.md` — YAML frontmatter, step tables, bugs found +
  fixed (file:line, root cause, verifying step), issues noticed, cleanup
  verification, state-wipe verification.

**You do NOT write the 11th-HOUR proposals.** That is the SEPARATE
`amwst-scenario-proposer` agent's job (skill `amwst-phase-proposals`), which the
orchestrator spawns AFTER you return — it reads your report and writes
`scenario_proposed-improvements_NNN_<timestamp>.md`. Keeping proposal-writing
out of this run separates fix-as-you-go from proposal-analysis into two agents
(and two contexts).

Both `reports/` and `reports_dev/` are gitignored (Rule 14) so private data
never reaches the repo.

## Phase H — Return

Your LAST text output must be exactly these 2 lines:

```
[PASS|FAIL|PARTIAL] SCEN-NNN — <one-line result>
Report: reports/scenarios-runner/SCEN-NNN_<timestamp>.report.md
```

No code blocks, no step tables, no screenshots inline — just the summary lines.
The parent (the amwst-run-scenario / amwst-run-scenarios-batch orchestration)
reads the report and then spawns `amwst-scenario-proposer` to produce the
11th-HOUR proposals from it.

**Before returning (MANDATORY): clear the heartbeat file.**

```bash
rm -f "${CLAUDE_PROJECT_DIR}/tests/scenarios/state/runner-heartbeat-SCEN-${NNN}.txt"
```

Removing the heartbeat is the signal that the run reached a clean terminus. If
the file remains after you return, the autonomous-batch state machine treats
that as a dead/stuck run and may schedule recovery. **Only clear the heartbeat
on a clean (PASS/FAIL/PARTIAL with full reports written) return — never clear if
you crash, hit a rate limit mid-run, or are killed mid-step.** A leftover stale
heartbeat is the desired signal so the recovery layer can act.

## Rate-limit resilience

If you hit a rate limit or context compaction mid-scenario:

1. Before the pause (when you see API error signals), write a checkpoint to
   `MEMORY.md`:
   ```
   ## Active run: SCEN-NNN <timestamp>
   Current step: S<NNN>
   Completed: S001..S<NNN-1>
   Report in progress: <path>
   Next action: <what you were about to do>
   ```
2. When resumed, check `MEMORY.md` for an "Active run" entry with a current
   timestamp. If present, resume from the recorded `Current step` instead of
   restarting from S001.
3. Clear the `Active run` entry once the scenario completes successfully, so it
   doesn't contaminate the next run.

## Memory continuity (what to store)

The runner has a `memory: project` directory at
`.claude/agent-memory/amwst-scenario-runner/` relative to the project it is
invoked in. Use it for:

- **Bug patterns** — when you fix a bug you've seen before, note the pattern in
  `MEMORY.md` so the next run recognizes it instantly instead of re-diagnosing
- **Fix recipes** — common repair steps specific to the project (e.g., "when
  wizard step N's button is disabled, check <file>:<lines> permission
  whitelist")
- **Browser-automation quirks** — accessibility-tree snapshot quirks, UID
  fallback strategies, stale-element workarounds specific to the project's UI
  framework
- **Rate-limit recovery breadcrumbs** — if you are restarted mid-scenario by the
  parent session's auto-continue hook, check `MEMORY.md` for a "Resume from step
  N" entry you left for yourself before the pause

Read `MEMORY.md` at the very start of every run. Update it at every fix and at
the end. Keep it under 200 lines; when it grows, extract stable patterns to
separate files under the memory dir.
