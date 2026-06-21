# Run Scenarios Batch — Detailed Procedure

## Table of contents

- [Step 1 — Parse arguments](#step-1--parse-arguments)
- [Step 2 — Optional preflight](#step-2--optional-preflight)
- [Step 3 — Main loop](#step-3--main-loop)
- [Step 4 — Aggregate the batch report](#step-4--aggregate-the-batch-report)
- [Step 5 — Optional improvement loop](#step-5--optional-improvement-loop)
- [Step 6 — Final output](#step-6--final-output)

## Step 1 — Parse arguments

Parse `$ARGUMENTS` into:
- An ordered list of scenario IDs (integers, expanded from a range or comma list)
- An `improve` boolean (true if `--improve` is present)

Examples:
- `18` → `ids=[18] improve=false`
- `16-20` → `ids=[16,17,18,19,20] improve=false`
- `16-20 --improve` → `ids=[16,17,18,19,20] improve=true`
- `1,5,8,12 --improve` → `ids=[1,5,8,12] improve=true`

Skip IDs whose `${CLAUDE_PROJECT_DIR}/tests/scenarios/SCEN-NNN_*.scen.md` file is missing and log that in the progress log.

## Step 2 — Optional preflight

Check for a project config file at `${CLAUDE_PROJECT_DIR}/tests/scenarios/scenarios.config.json`. If it exists, parse the following optional fields:

- `preflight_command` — a shell command to run once before the batch (e.g. restart a dev server, reset fixtures)
- `base_url` — the URL used for health checks (e.g. `http://localhost:3000`)
- `health_endpoint` — path appended to `base_url` to probe readiness (default `/`)

If the config file is present, run the `preflight_command` via Bash (single one-shot invocation), then probe `base_url + health_endpoint` with curl. If the probe fails, log the failure in the progress log and abort the batch with a clear error.

If no config file exists, skip preflight entirely. The per-scenario Phase 0 SAFE-SETUP in each scenario file is responsible for its own readiness checks.

## Step 3 — Main loop

For each scenario ID `N` in the parsed list, in numeric order:

1. **Check resume state.** Read `${CLAUDE_PROJECT_DIR}/tests/scenarios/state/batch-progress.log` (create the directory if missing). If it already contains a `SCENARIO_DONE <N>` line from a previous run in this batch window, skip this scenario and move to the next.

2. **Per-scenario pre-setup script (MANDATORY).** Run `${CLAUDE_PROJECT_DIR}/tests/scenarios/scripts/setup-SCEN-<padded-id>.sh` via Bash. Every scenario MUST have this script (they are generated from a template — see `scenario-setup.sh`). The script reads the scenario's `rewipe-list`, `git-fixtures`, `dir-fixtures` frontmatter and prepares the environment.

   **If the setup script fails (non-zero exit), the scenario MUST NOT start.** Log the failure in `batch-progress.log` as `SCENARIO_SETUP_FAIL <N> <reason>`, skip this scenario, and continue to the next one. The setup failure is a scenario-author problem (missing fixture, missing tag, bad path) — not something the batch conductor should paper over. Do NOT spawn the runner subagent when setup fails; it would just restart the scenario from step 1 in an uninitialized environment.

3. **Spawn the `amwst-scenario-runner` subagent** via the Agent tool:
   ```
   Agent(
       description: "Run SCEN-<padded-id> end-to-end",
       subagent_type: "amwst-scenario-runner",
       prompt: "Run scenario number <N>. Scenario file: ${CLAUDE_PROJECT_DIR}/tests/scenarios/SCEN-<padded-id>_*.scen.md. Rules file: <resolved-rules-path>. Follow rules 1-14, drive the app via the dev-browser CLI (Rule 8 — loaded via Skill(skill: 'dev-browser:dev-browser')), write the report + proposals under ${CLAUDE_PROJECT_DIR}/reports/scenarios-runner/, and return a 2-line summary."
   )
   ```
   Wait for the subagent to return. Parse the 2-line result into pass/fail/partial + report path.

4. **Per-scenario cleanup script (MANDATORY).** Run `${CLAUDE_PROJECT_DIR}/tests/scenarios/scripts/cleanup-SCEN-<padded-id>.sh` via Bash. This delegates to `scenario-restore.sh` which verifies and replays the MANIFEST.sha256. If it fails, log `SCENARIO_CLEANUP_FAIL <N> <reason>` in `batch-progress.log`, but continue to the next scenario (cleanup failures are noted for operator review, not fatal to the batch).

5. **Append progress.** One line to `${CLAUDE_PROJECT_DIR}/tests/scenarios/state/batch-progress.log`:
   ```
   SCENARIO_DONE <padded-id> <pass|fail|partial> <report-path> <duration-seconds>
   ```

6. **Move to the next scenario.**

## Step 4 — Aggregate the batch report

After the loop completes, write an aggregated summary to `${CLAUDE_PROJECT_DIR}/reports/scenarios-runner/scenario-batch-<range>_<timestamp>.md` with:

- Per-scenario result table (ID, status, bugs found, bugs fixed, duration, report path)
- Aggregated P0 proposal count (parse each `scenario_proposed-improvements_NNN_*.md` header)
- Open issues not covered by P0 proposals
- Recommended-for-implementer section naming which scenarios produced P0 proposals worth implementing

## Step 5 — Optional improvement loop

If `improve=true` AND there are P0 proposal files from scenarios in this batch, spawn the `amwst-scenario-improvement-implementer` subagent:

```
Agent(
    description: "Implement P0 proposals from batch <range>",
    subagent_type: "amwst-scenario-improvement-implementer",
    prompt: "Implement P0 items from scenario_proposed-improvements_*_<batch-timestamp>.md for scenarios <comma-separated-list>. Files: <explicit list of absolute paths>. Rules file: <resolved-rules-path>. Report back with IMPLEMENTATIONS_DONE or IMPLEMENTATIONS_FAIL."
)
```

The implementer runs in a git worktree automatically because its frontmatter has `isolation: worktree`. Wait for its 1-line completion marker. Parse the branch name.

If `IMPLEMENTATIONS_DONE`, write the branch name to the aggregated report so the user can merge it after a verification re-run. **Do NOT merge automatically from the skill** — merging is the user's decision.

If `IMPLEMENTATIONS_FAIL`, log the failure reason in the aggregated report and continue (the worktree is automatically cleaned up by the Agent tool).

## Step 6 — Final output

Return ONE 3-line summary as your final message:

```
BATCH_DONE <range> <P>/<F>/<X> <aggregated-report-path>
Per-scenario reports: <space-separated paths>
Improvements: <branch-name or "skipped">
```

Where `P` = pass count, `F` = fail count, `X` = partial count.

## Hard rules

1. **NEVER spawn `claude -p`, `claude --print`** or any subprocess claude invocation — use Agent tool exclusively.
2. **NEVER nest skill invocations** — use Agent tool with `subagent_type: amwst-scenario-runner`.
3. **NEVER use `git add -A` or `git add .`** — stage files by explicit name.
4. **NEVER push to remote** — the user pushes, not the conductor.
5. **NEVER merge the implementer's worktree branch** — leave that for the user.
6. **NEVER hardcode project paths** — always use `${CLAUDE_PROJECT_DIR}`.
