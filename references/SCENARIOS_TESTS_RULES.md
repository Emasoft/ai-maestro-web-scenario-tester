# Scenario Tests Rules

## Purpose

The ultimate aim of UI scenario tests is NOT just to verify that features work. The real value is the **11th-HOUR analysis** (Rule 11): after each scenario run, a deep investigation produces **concrete improvement proposals** — bug fixes, API redesigns, governance rule changes, workflow optimizations, and new scenarios. These proposals are the primary deliverable. The test steps are the instrument; the improvements are the product.

Every scenario run should produce a `scenario_proposed-improvements_<NNN>_<datetime>.md` report with actionable proposals. These proposals are then reviewed, prioritized, and implemented before the next scenario batch. Over time, this creates a virtuous cycle: tests find issues, issues get fixed, fixes get verified by re-running the same scenarios.

All UI scenario tests in AI Maestro MUST follow these 14 rules. No exceptions.

---

## Rule 0 — Who you are in a scenario (CRITICAL)

**You are the HUMAN USER of AI Maestro. You are NOT an agent. You are NEVER an agent. Not even partially.**

Scenarios are always played from the user's seat — the user who opens a browser, logs in to the dashboard, and drives the app through forms, buttons, and the **chat section** of an agent's view. No scenario, no phase, no step, no subagent, no "just this once" exception lets the runner adopt an agent identity.

### What the human user has, and does not have

A human user of AI Maestro:
- Logs in to the dashboard in a web browser.
- Clicks buttons, fills forms, types in the **chat section** of an agent's view.
- Has NO AI Maestro identity: no AID, no governance title, no agent registry entry, no `~/agents/<you>/` folder, no tmux session owned by the app.
- Cannot — and must not — use the **terminal section** of an agent's view for their own actions. That section is a live read-only stream of what an agent is doing. The user observes there; the user never drives agents there. Scenarios that need to push instructions into an agent do so through the agent's **chat section** (typed-message UI), not by writing into the terminal stream.

**The scenario runner (this agent and any of its forked subagents) plays the role of that human user.** It drives the web UI via `dev-browser` exactly as a human would. It does NOT:
- Talk to agents through their terminal section.
- Create an agent-identity for itself, request an AID, or register itself with the app.
- Write into any file inside `~/agents/<anything>/` directly (all agent mutations go through the UI).
- Use CLI tools such as `aimaestro-agent.sh`, `amp-send.sh`, or direct API calls to affect agents — those are agent-to-agent tooling, not user tooling.

### The "every agent lives in ~/agents/" hard invariant

**Every agent that a scenario creates, modifies, or touches lives under `~/agents/<name>/`. No title is exempt. No test mode is exempt. No import flow is exempt.**

Specifically:
- MANAGER test agents → `~/agents/<name>/`
- CHIEF-OF-STAFF test agents → `~/agents/<name>/`
- MEMBER, ARCHITECT, ORCHESTRATOR, INTEGRATOR, MAINTAINER, AUTONOMOUS test agents → `~/agents/<name>/`
- The auto-COS that the system creates when a team is created → `~/agents/<name>/`
- Any agent the runner imports via the Wizard's "Import from existing folder" option → the source folder for that import MUST itself be prepared in advance as a fixture under `~/agents/<name>/` (see the fixture rule below). Importing from outside `~/agents/` is forbidden.

**Paths that no scenario ever creates or modifies an agent inside:**
- `~/ai-maestro/` (the source tree / where a controller Claude Code may be running)
- `~/.claude/` (the human user's Claude Code config)
- `~/.aimaestro/` (server-state files only — never an agent workdir)
- `/tmp`, `/var`, system folders
- Any other user-owned source, config, or notes folder

**The Wizard is the enforcement surface.** Every scenario creates and modifies agents only via the Agent Creation Wizard (or equivalent UI dialogs). The Wizard writes to `~/agents/<name>/` and rejects any other target (G03-ENFORCE + G03-SAFETY in `services/element-management-service.ts:5074-5129`). If during a scenario step you see any UI that would let an agent be created or edited to live outside `~/agents/`, that is a critical security bug — STOP, record it as BUG-001 in the report, file a P0 proposal, and fail the scenario (do not proceed).

**Belt-and-braces at delete time.** `DeleteAgent` in `services/element-management-service.ts:4771-4786` refuses `alsoDeleteFolder=true` when `agent.workingDirectory` is not under `~/agents/`. This means that even if a stale registry entry exists with `workingDirectory = ~/ai-maestro/` (as happened with legacy `_aim-*` service agents), clicking "Delete Agent with folder" on that entry CANNOT destroy the ai-maestro source tree — the pipeline refuses and only removes the registry entry. Still, a scenario must NEVER intentionally click delete on such an entry — it's a Rule 0 violation. The app guard is the second line; the first line is: don't go there.

**The hard blacklist — agents the runner must never interact with:**

- Any agent whose `workingDirectory` is NOT under `~/agents/` — these are user-owned real agents (see explicit list below). Verify via `GET /api/agents?includeDeleted=false` before any interaction.
- Legacy `_aim-*` service agents whose workdir is still `~/ai-maestro/` (registry drift from older AI Maestro versions) — report and skip.
- The user's pre-existing real agents by explicit name: `alexandre`, `luckas-bot`, `jhonny-bot`, `jack-bot`, `genny-bot`, `teseo-bot`, `sergei`, `barry`, `ecos-chief-of-staff-one`, `backend-infrastructure-engineer`, `tmux-test-audit`, `default`, and anything in `~/Code/*` or `~/agents/jvs-*`, `~/agents/swift-*`, `~/agents/my-*`, `~/agents/integrator-rex`.

The ONLY scenario that legitimately interacts with an `_aim-*` agent is **SCEN-004 (Haephestos plugin creation)** — the scenario exists specifically to test that flow. Even then, the runner must (a) verify the Haephestos workdir is under `~/agents/haephestos/` before any click, (b) halt and file P0 if it's anywhere else.

**Why this matters for safety.** Cleanup (Rule 1) deletes every test agent AND its working folder via the UI's "Also delete agent folder" checkbox. If a test agent's folder ever landed outside `~/agents/`, cleanup would destroy that folder. Inside `~/ai-maestro/` that means the project source. Inside `~/.claude/` that means the human user's Claude Code config. These must be impossible by construction.

### Import-from-existing-folder scenarios

When a scenario exercises the Wizard's "Import from existing folder" flow:
1. The fixture folder MUST already exist on disk at a path inside `~/agents/` (for example `~/agents/scen-NNN-import-fixture/`), BEFORE the scenario starts.
2. The fixture MUST be declared in the scenario's frontmatter under `dir-fixtures:` and referenced in the step body as `FOLDFIX[n]`.
3. The scenario author prepares the fixture in advance (populates files, optional `scenario-start` git tag). The shared setup script resets it if tagged.
4. The Wizard's "Import" field is typed with the `FOLDFIX[n]` path.
5. Cleanup deletes the imported agent via the UI (folder-delete included). The fixture path itself is preserved for the next run — it is a fixture, not a per-run artifact.
6. The fixture path is NEVER under `~/ai-maestro/`, `~/.claude/`, or any other source/config folder. If the app lets you point "Import" at an outside path, that is a critical security bug — same treatment as above.

### Consequence for rewipe-list

The default rewipe-list does NOT contain `~/.claude/*` files. Those belong to the human user, not to any scenario. A scenario may add `~/.claude/settings.json` to its rewipe-list ONLY if its explicit purpose is to test user-scope plugin install/uninstall behavior — and even then, the scenario author commits to reverting every mutation through the UI before cleanup runs. The default rewipe-list only covers `~/.aimaestro/*` server-state files that the app itself owns.

---

## Table of Contents

0. [Rule 0: Who you are in a scenario](#rule-0--who-you-are-in-a-scenario-critical) — You are the human user, not an agent
1. [Rule 1: CLEAN-AFTER-YOURSELF](#rule-1-clean-after-yourself) — Revert system to pre-test state
2. [Rule 2: 0-IMPACT](#rule-2-0-impact) — Never use existing user resources
3. [Rule 3: STATE-WIPE](#rule-3-state-wipe) — Backup and restore config files
4. [Rule 4: FIX-AS-YOU-GO](#rule-4-fix-as-you-go) — Fix bugs immediately during test
5. [Rule 5: TRACK-AND-REPORT](#rule-5-track-and-report) — Record every step and bug
6. [Rule 6: STICK-TO-UI](#rule-6-stick-to-ui) — All actions through the browser
7. [Rule 7: SAFE-SETUP](#rule-7-safe-setup) — Commit, build, verify before test
8. [Rule 8: DEV-BROWSER](#rule-8-dev-browser) — Use the `dev-browser` CLI (sandboxed JS) for ALL UI automation
9. [Rule 9: REPORT-FORMAT](#rule-9-report-format) — Structured markdown report
10. [Rule 10: PHOTOSTORY](#rule-10-photostory) — Screenshot at every critical step + auto-purge after fix verification
11. [Rule 11: 11th-HOUR](#rule-11-11th-hour) — Post-scenario deep analysis and improvement proposals
12. [Rule 12: SUDO-MODE](#rule-12-sudo-mode) — Password re-entry for destructive operations
13. [Rule 13: AUTONOMOUS-PROTOCOL](#rule-13-autonomous-protocol) — How a long unattended overnight batch is structured
14. [How-To: Running a Scenario](#how-to-running-a-scenario) — Practical guidance for the test executor

---

## Rule 1: CLEAN-AFTER-YOURSELF

The **last phase** of every scenario MUST revert the system to the exact state it was in before the test started. Every team created, title changed, plugin installed, agent created, group added, or setting modified during the test MUST be undone.

**Undo efficiently, not step-by-step.** If you created a plugin in 30 steps (selecting skills, subagents, MCP, rules, hooks, etc.), you undo it in ONE step: delete the plugin. The goal is to reach the original state, not to reverse-replay every action. Find the shortest path to cleanup.

The cleanup phase steps are numbered and verified just like test steps — they are NOT optional. If a cleanup step fails, it MUST be fixed before the scenario is considered complete.

**Verification:** After cleanup, take a screenshot and compare with the pre-test screenshot. The UI must look identical.

---

## Rule 2: 0-IMPACT

**Never use existing user-created resources** (agents, teams, groups, plugins) for testing. Instead:

1. Create NEW elements specifically for the test (with clearly test-prefixed names, e.g. `scen-test-agent-01`, `scen-test-team-alpha`)
2. Use those test elements for all test operations
3. Remove them completely during cleanup (Rule 1)

This prevents test runs from corrupting the user's real configuration, data, or agent state. After a scenario completes, the system must be indistinguishable from one where the test never ran.

**Exception:** Reading existing state is allowed (e.g., checking how many agents exist). Only MUTATION of existing resources is forbidden.

---

## Rule 3: STATE-WIPE

Configuration files can be modified by side effects (settings.json, settings.local.json, governance.json, etc.). These must be captured and restored.

**CHECKPOINT-SAVE and CHECKPOINT-RESTORE are performed by the shared setup/restore scripts** at `tests/scenarios/scripts/scenario-setup.sh` and `scenario-restore.sh`. The list of files to back up is declared per-scenario in the `rewipe-list` frontmatter field. The shared setup reads that list, copies each file to `tests/scenarios/state-backups/SCEN-<NNN>_<timestamp>/` with an integrity `MANIFEST.sha256`, and the shared restore verifies and replays the manifest.

**Two mandatory checkpoints:**

1. **CHECKPOINT-SAVE (before test begins):** Run the per-scenario wrapper `setup-SCEN-<NNN>.sh`. It delegates to `scenario-setup.sh <NNN>`, which reads `rewipe-list` from the scenario frontmatter and backs up every listed file. The default safe list covers only app-owned server state:
   - `~/.aimaestro/governance.json`
   - `~/.aimaestro/agents/registry.json`
   - `~/.aimaestro/teams/teams.json`
   - `~/.aimaestro/teams/groups.json`

   **Files OUTSIDE the default list (add only with strong justification):**
   - `~/.claude/settings.json` / `~/.claude/settings.local.json` — these belong to the HUMAN USER's Claude Code. Touch them only if the scenario's entire purpose is to test user-scope plugin install/uninstall, and revert every mutation through the UI before cleanup.
   - Any `~/agents/<test-agent>/.claude/settings.local.json` — these are inside test-agent working directories, which are deleted during cleanup anyway. Only add if the scenario checks a specific setting mid-run.

   Backups are saved to `tests/scenarios/state-backups/SCEN-<NNN>_<timestamp>/` (gitignored).

2. **CHECKPOINT-RESTORE (during cleanup):**

   **IMPORTANT: Cleanup MUST use the UI, not file restoration.**

   The correct cleanup order is:
   1. **Delete teams via UI** (Teams tab → Delete Team → enter governance password → check "Delete Agents Too" → Delete Team)
   2. **Remove governance titles via UI** (Profile → title badge → AUTONOMOUS → password)
   3. **Delete remaining agents via UI** (Profile → Advanced → Danger Zone → Delete Agent → check "Also delete agent folder" → type name → Delete Forever)
   4. **Purge cemetery entries via UI** (Settings → Cemetery → Purge for each test agent)
   5. **Verify via API** that all test artifacts are gone (no test agents in registry, no test teams in teams.json, no test entries in cemetery)
   6. **THEN restore config files** from backup — ONLY for files that may have been modified by side effects (settings.json, settings.local.json, governance.json). Do NOT restore registry.json or teams.json — the UI deletions already cleaned those.

   **Why UI-first:** Restoring registry.json removes agents from the registry but leaves their tmux sessions running and agent folders on disk. These orphan sessions cause resource leaks and phantom entries on the next server poll. The UI Delete button correctly kills the tmux session, removes the registry entry, AND deletes the agent folder (when "Also delete agent folder" is checked).

   **NEVER use bash/CLI to delete agent folders.** That is a Rule 6 violation. The "Also delete agent folder" checkbox in the Delete Agent dialog handles folder cleanup. If agent folders remain after UI deletion, that is a BUG to report — not a reason to use bash.

   After restoration, verify file contents match the backup byte-for-byte. `scenario-restore.sh` performs this SHA256 check automatically for every file in the MANIFEST.

The scenario report MUST include the backup file list and restoration verification.

### Fixture fields (git-fixtures, dir-fixtures)

In addition to `rewipe-list`, scenarios may declare two fixture arrays in frontmatter:

- **`git-fixtures`** — URLs of GitHub repositories the scenario uses. Each must exist as a local clone at `tests/scenarios/fixtures/git/<repo-name>/` AND carry a `scenario-start` tag. The shared setup script `git reset --hard`s each fixture to that tag before the scenario runs (scenario author prepares the fork and the tag in advance — the scripts never clone for you). In scenario steps, reference fixtures as `GITFIX[n]` where `n` is the 0-based index.
- **`dir-fixtures`** — Absolute paths to local folders the scenario uses. Each must exist. If the path is a git repo with a `scenario-start` tag, the setup resets it. Referenced in steps as `FOLDFIX[n]`.

Fixture creation is NOT automated — the scenario author must:
1. Fork the upstream repo, clone locally under `tests/scenarios/fixtures/git/`.
2. Commit the baseline state and tag it `scenario-start`.
3. Document the fork URL in `git-fixtures`.

For directory fixtures, prepare the folder (with its initial file set or git baseline + `scenario-start` tag) in advance of the first run. Fixtures persist across runs and are reset by the shared setup on each scenario start.

---

## Rule 4: FIX-AS-YOU-GO

When a step fails due to a bug or unexpected behavior:

1. **STOP** the scenario at that step
2. **DIAGNOSE** the issue (read logs, check state, inspect DOM)
3. **FIX** the code immediately
4. **REBUILD** (`yarn build`) and restart the server if needed
5. **RETRY** the failed step from the exact same state
6. **LOOP** steps 2-5 until the step passes — no limit on attempts
7. **RESUME** the scenario from the next step

Every fix attempt is logged in the report (Rule 5). The scenario is never abandoned — it either completes fully or runs out of context window.

**This is Phase 1 of the two-phase protocol.** Rule 4 bug fixes are **IMMEDIATE** and land **in place on the current branch** — never in a worktree, never as a PR. They are committed during the overnight run alongside the scenario's report. The cron protocol (Rule 13) enforces this: Phase 1 only creates bug-fix commits on the current branch, never branches or PRs. Delayed work (improvements, redesigns, governance changes) goes into Rule 11, NOT here. If a change is too big for an in-place fix on the current branch, write it as a Rule 11 proposal instead and keep the scenario moving.

---

## Rule 5: TRACK-AND-REPORT

The scenario report (`reports/scenarios-runner/<scenario-name>_<timestamp>.report.md`) records:

### For every step:
- Step ID and description
- PASS / FAIL / FIXED status
- Screenshot filename (if taken)
- Timestamp

### For every bug found and fixed:
- Step ID where discovered
- Description of the bug
- Root cause analysis
- Files modified to fix
- Fix verified by: (step ID that passed after fix)

### For every issue noticed but not blocking:
- Step ID where noticed
- Description and severity (WARN / INFO)
- Potential impact if left unfixed
- Suggested fix or investigation

### Report header:
- Scenario name and version
- Commit hash at start
- Commit hash at end (if fixes were committed)
- Start/end timestamps
- Total steps: passed / failed / fixed / skipped
- CLEAN-AFTER-YOURSELF verification: PASS / FAIL
- STATE-WIPE verification: PASS / FAIL

---

## Rule 6: STICK-TO-UI

**NEVER bypass the UI** to achieve a step's goal. All interactions must go through the browser:

- Click buttons, fill forms, select options — via `dev-browser` per Rule 8. Legacy chrome-devtools-mcp support is deprecated.
- Do NOT call API endpoints directly with `curl` (except for state verification AFTER a UI action)
- Do NOT modify settings files directly
- Do NOT run CLI commands to achieve what the UI should do

If the UI cannot accomplish a step, that is a **BUG** — fix it (Rule 4), don't bypass it.

**Exception:** State verification (reading API responses, checking files) is allowed after a UI action to confirm the backend state matches what the UI shows. Reads never violate Rule 6.

**Additional allowed surface:** pre/post-scenario fixture scripts (`setup-SCEN-NNN.sh`, `cleanup-SCEN-NNN.sh`) that run OUTSIDE the scenario step sequence. Prefer UI-driven setup/restore; use these only when a UI path is genuinely unavailable.

### Bypass invalidates the entire run — restart from step 1

If the runner bypasses the UI even ONCE during the scenario step sequence
(for any reason — a broken element, a technical shortcut, a "just this
one call" workaround), **the scenario run is INVALIDATED.** The runner
MUST:

1. Stop the current run immediately.
2. Record the bypass in the in-progress report under a section titled
   `Rule 6 violation detected — run INVALIDATED`, naming the step and the
   bypass method.
3. Perform the CLEANUP phase (Rule 1) to restore original state.
4. Restart the scenario from step S001.

Partial credit does not exist. A single bypass means the code path under
test was not actually exercised through the production surface, so the
test proved nothing about that step. Additionally, AI Maestro uses
immutable ledgers + strong security infrastructure — out-of-band
mutations may be DETECTED and reacted to by the system, potentially
corrupting state that is hard to restore.

"But the UI has a bug here" is a **Rule 4 FIX-AS-YOU-GO trigger**, never a
Rule 6 bypass excuse. Repair the UI/API so the UI works, then resume.
Read-only state verification remains fully allowed at any time — the
invalidation rule applies only to state-mutating bypasses.

---

## Rule 7: SAFE-SETUP

Before starting a scenario:

1. **COMMIT** all uncommitted changes: `git add <files> && git commit -m "pre-scenario: <name>"`
2. **RECORD** the commit hash in the scenario report
3. **OPTIONALLY** run in a git worktree for full isolation: `git worktree add ../scen-<name> HEAD`
4. **BUILD** the project: `yarn build`
5. **START** the server: `pm2 restart ai-maestro` (or `yarn dev`)
6. **VERIFY** the server is healthy: check `GET /api/sessions` returns 200
7. **KILL ORPHAN TEST SESSIONS:** Kill any tmux sessions from previous test runs:
   ```bash
   tmux list-sessions | grep '^scen-' | cut -d: -f1 | xargs -I{} tmux kill-session -t {}
   tmux list-sessions | grep '^cos-scen-' | cut -d: -f1 | xargs -I{} tmux kill-session -t {}
   ```
   This prevents dead sessions from interfering with the test or cluttering the UI.
8. **RUN THE PER-SCENARIO SETUP SCRIPT (MANDATORY):** Invoke `tests/scenarios/scripts/setup-SCEN-<NNN>.sh`. This runs the shared `scenario-setup.sh` which:
   - Reads the scenario's `rewipe-list`, `git-fixtures`, `dir-fixtures` from frontmatter.
   - Creates `state-backups/SCEN-<NNN>_<timestamp>/` with a SHA256 `MANIFEST`.
   - Backs up every file in `rewipe-list`.
   - Resets every `git-fixture` repo to the `scenario-start` tag.
   - Verifies every `dir-fixture` exists (and resets it if it's a git repo with `scenario-start`).

   **If the setup script exits non-zero, the scenario MUST NOT start.** The runner investigates the root cause (missing fixture? missing tag? unreadable file?), fixes the underlying problem (not by bypassing — by making the script's original intent succeed), then re-runs the setup. Common causes:
   - Fixture fork not cloned locally → cloning is the scenario author's job, do it now.
   - Fixture missing `scenario-start` tag → author must create the baseline commit + tag.
   - `rewipe-list` file path typo → fix the frontmatter.
   - `yq` missing → install yq.

   Never edit the shared scripts to "skip" a failing fixture. Fix the fixture.

If running in a worktree, all scenario artifacts (screenshots, reports, backups) are saved inside the worktree, then copied to the main tree on completion.

### Auto-COS creation on team creation (authoring note)

When a scenario creates a team via the UI Create Team dialog and does NOT specify
a `chiefOfStaffId`, the CreateTeam pipeline **auto-creates a new agent** named
`cos-<teamslug>` with a random robot persona name (Tatiana, Aria, Mia, etc.) and
installs `ai-maestro-chief-of-staff@ai-maestro-plugins` at that agent's local
scope. That auto-COS satisfies the "no team without a COS, no COS without a
team" invariant (R3 + R11).

Every scenario that creates a team MUST:

1. **Declare the auto-COS in the `data_produced` frontmatter field** with
   lifecycle "temporary, created and deleted". Don't claim the COS comes
   from one of your member agents — it doesn't.
2. **List the auto-COS in the prerequisites** with a note that its persona
   name is RANDOM and its folder is deterministically `cos-<teamslug>`.
3. **Clean up the auto-COS explicitly**. Either use "Delete Agents Too"
   on team deletion (which cascades), or delete it separately via UI after
   deleting the team. Its tmux session name will also be `cos-<teamslug>`.
4. **Never hardcode the auto-COS persona name** in verification steps.
   Use `team.chiefOfStaffId` from the API response to look the agent up.

An agent becomes COS only at the moment of team creation; no AUTONOMOUS
agent is a COS until it's assigned to a team. Scenarios must NOT treat
the auto-COS as pre-existing — it is produced by the CreateTeam pipeline.

---

## Rule 8: DEV-BROWSER

**Scenario tests MUST use the `dev-browser` plugin for ALL browser automation.** chrome-devtools MCP is deprecated for production scenario runs as of 2026-04-15.

### Mandatory entry point — load the skill FIRST, then call the CLI

At the very start of every scenario run, the runner MUST invoke the dev-browser skill via the Skill tool:

```
Skill(skill: "dev-browser:dev-browser")
```

The loaded skill provides the authoritative API documentation (`browser.getPage`, `page.snapshotForAI`, `saveScreenshot`, the QuickJS sandbox boundaries, etc.). **This rule does NOT duplicate that API documentation** — read the skill content for everything to do with how to write a `dev-browser` script. This rule covers ONLY the AI Maestro-specific conventions on top of the skill.

Never hardcode any path under `~/.claude/plugins/cache/dev-browser-marketplace/` — that directory is ephemeral and may be cleared by a plugin reload at any time. Always go through the Skill tool.

### AI Maestro conventions for every dev-browser invocation

Every scenario `dev-browser` call MUST use these flags:

```bash
dev-browser --browser ai-maestro-scenarios --headless --timeout 60 <<'EOF'
... script ...
EOF
```

| Flag | Why |
|---|---|
| `--browser ai-maestro-scenarios` | All scenarios in this project share ONE named Chromium instance, so the persistent `dashboard` page (logged in once at master setup) is reused by every scenario. Other dev-browser usage on the same machine uses a different `--browser` name and is fully isolated. |
| `--headless` | Required for unattended overnight runs — no GUI, no window flashes, no memory penalty. Drop this flag only for interactive debugging. |
| `--timeout 60` | Default 30 s is too short for some heavier dashboard pages (agent-creation wizard, kanban load). 60 s is the scenario default; bump per-script when a specific page needs longer. |

For `device: smartphone` / `device: tablet` scenarios, use `--browser ai-maestro-scenarios-smartphone` (or `-tablet`) instead, then call `page.setViewportSize({width, height})` once in master setup. The AI Maestro frontend uses width-based media queries, so width alone triggers the mobile component set.

### Reusable AI Maestro helpers

To avoid every scenario reimplementing the login flow, sudo modal handling, etc., the runner sources `tests/scenarios/scripts/dev-browser-helpers/aim-helpers.sh` before every scenario. That file exports shell functions (`aim_login`, `aim_screenshot`, `aim_sudo_modal`, `aim_create_agent`, `aim_delete_agent`, …) that wrap their own `dev-browser <<'EOF' ... EOF` calls. Add new helpers there when a scenario needs a UI sequence that's likely to be reused.

### Daemon lifecycle is master-level, not per-scenario

Per-scenario runners NEVER stop the dev-browser daemon. The master setup phase (Rule 13) implicitly auto-spawns it on the first call, and the master cleanup phase shuts it down with `dev-browser stop`. Note: there is NO `daemon start/stop` subcommand — the daemon auto-spawns on first invocation. Use `dev-browser status` to check, `dev-browser stop` to shut down.

### Reading agent terminal history (unchanged)

Claude Code uses the xterm alternate screen buffer — `tmux capture-pane` only captures the visible pane. To read what a Claude Code agent actually did during a scenario:

1. Find the conversation log: `ls -lt ~/.claude/projects/-Users-<user>-agents-<name>/*.jsonl | head -1`
2. Analyze with LLM Externalizer: `code_task` with instructions to extract actions, errors, and outcomes
3. This is the **authoritative source** — not terminal screenshots (which may only show the final idle prompt)

---

## Rule 9: REPORT-FORMAT

The scenario report file follows this exact structure:

```markdown
---
scenario: <scenario-name>
version: <scenario-version>
commit_start: <git-hash>
commit_end: <git-hash-or-same>
started_at: <ISO-timestamp>
completed_at: <ISO-timestamp>
result: PASS | FAIL | PARTIAL | STUCK
steps_total: <N>
steps_passed: <N>
steps_failed: <N>
steps_fixed: <N>
bugs_found: <N>
bugs_fixed: <N>
issues_noticed: <N>
cleanup_verified: true | false
state_wipe_verified: true | false
screenshots_purged: true | false
---

# Scenario Report: <scenario-name>

## Summary
<1-3 sentence summary of what was tested and the outcome>

## Environment
- Server: http://localhost:23000
- Build: <yarn build output summary>
- Browser: Chrome via CDP

## Steps

### Phase N: <phase-name>

| Step | Action | Expected | Actual | Status | Screenshot |
|------|--------|----------|--------|--------|------------|
| S001 | ... | ... | ... | PASS | scen-001.png |

## Bugs Found & Fixed

### BUG-001: <title>
- **Discovered at:** Step S<NNN>
- **Symptom:** ...
- **Root cause:** ...
- **Fix:** <file>:<lines> — <description>
- **Verified at:** Step S<NNN> (retry)

## Issues Noticed (Non-Blocking)

### ISSUE-001: <title>
- **Noticed at:** Step S<NNN>
- **Severity:** WARN | INFO
- **Description:** ...
- **Suggested fix:** ...

## Cleanup Verification

| Action | Expected | Actual | Status |
|--------|----------|--------|--------|
| Remove test team | Team deleted | Confirmed via API | PASS |
| ... | ... | ... | ... |

## State-Wipe Verification

| File | Backup hash | Restored hash | Match |
|------|-------------|---------------|-------|
| ~/.claude/settings.json | abc123 | abc123 | YES |
| ... | ... | ... | ... |
```

---

## Scenario File Format

Scenario files are saved in `tests/scenarios/` with the naming convention:

```
SCEN-<NNN>_<scenario-name>.scen.md
```

Where `<NNN>` is a zero-padded unique number (001, 002, ...). This allows referencing scenarios by number: "run scenario 14" → `SCEN-014_*.scen.md`.

Example: `SCEN-001_title-change-lifecycle.scen.md`

**Numbering rules:**
- Numbers are assigned sequentially and never reused (even if a scenario is deleted)
- The current highest number is tracked in `tests/scenarios/NEXT_SCEN_NUMBER` (plain text, e.g. `4`)
- Each scenario's number is also in its YAML frontmatter (`number: 1`)

### Frontmatter (YAML):

All fields are **required** unless marked (optional).

```yaml
---
number: <unique integer>            # Matches filename SCEN-<NNN>. Never reused.
name: <human-readable scenario name> # Short title, no quotes needed
version: "1.0"                      # Semver string. Bump on breaking step changes.
description: >                      # Multi-line. Tell the user's story: what they
  <What the user does step by step> # do, what they see, what gets verified.
client: claude                      # AI client(s) under test. One of:
                                    # "claude", "codex", "gemini", or a list
                                    # for multi-client scenarios: [claude, codex]
interhosts: false                   # true if agents from remote hosts participate.
                                    # Requires Tailscale + hosts.json with peers.
device: desktop                     # Browser viewport: "desktop", "tablet", or
                                    # "smartphone". Controls window size and which
                                    # component set is tested (standard vs touch).
                                    # desktop=1280x800, tablet=1024x768, smartphone=390x844
subsystems:                         # Backend services/modules exercised.
  - governance                      # Pick from: governance, teams, agent-registry,
  - role-plugins                    # element-management-service, agent-messaging,
  - agent-registry                  # role-plugins, kanban, cross-client-conversion-service,
                                    # sessions-service, groups-service
ui_sections:                        # Every UI area the scenario touches.
  - Sidebar -> Agents tab           # Use arrow notation: Section -> Tab -> Element
  - Agent Profile -> Overview tab -> Governance Title
  - Title Assignment Dialog (radio cards, password prompt)
data_produced:                      # Every artifact created during the test.
  - 2 test agents (temporary)       # Format: <count> <what> (<lifecycle>)
  - 1 test team (temporary)         # Lifecycle: "temporary, created and deleted"
  - Plugin settings modifications   # or "temporary, restored via STATE-WIPE"
rewipe-list:                        # Files backed up by setup-SCEN-<NNN>.sh and
  - ~/.aimaestro/governance.json    # restored by cleanup-SCEN-<NNN>.sh.
  - ~/.aimaestro/agents/registry.json # Default: only app-owned server state.
  - ~/.aimaestro/teams/teams.json   # Never add ~/.claude/* unless scenario
  - ~/.aimaestro/teams/groups.json  # tests user-scope plugins (see Rule 0).
git-fixtures: []                    # Array of GitHub URLs. Local clone MUST exist at
                                    # tests/scenarios/fixtures/git/<repo-name>/ with
                                    # tag scenario-start. Reference as GITFIX[0], GITFIX[1].
dir-fixtures: []                    # Array of absolute local paths. MUST exist.
                                    # Reference as FOLDFIX[0], FOLDFIX[1].
browser_stack: dev-browser          # Canonical. See Rule 8.
# Legacy scenarios may still carry the pre-2026-04-15 chrome-devtools-mcp
# required_tools list. That list is deprecated; new scenarios MUST use
# browser_stack: dev-browser. The old shape is kept here for reference:
# required_tools:
#   - mcp__chrome-devtools__navigate_page
#   - mcp__chrome-devtools__take_snapshot
#   - mcp__chrome-devtools__take_screenshot
#   - mcp__chrome-devtools__click
#   - mcp__chrome-devtools__fill
#   - mcp__chrome-devtools__wait_for
prerequisites:                      # Conditions that must be true BEFORE Phase 0.
  - AI Maestro server running at http://localhost:23000 (dev-browser handles browser launch)
  - Governance password set
  - ai-maestro-plugins marketplace registered
  - <any scenario-specific requirements, e.g. "Codex CLI installed">
governance_password: "<password>"   # The actual password value, in quotes.
                                    # Every step that needs it must reference it
                                    # verbatim — never write just "password".
commit: <git-hash or TBD>          # Hash at time of writing. Updated after first run.
author: <who wrote the scenario>    # (optional) Person or team name.
# NOTE: `client` goes between `description` and `subsystems` (see above).
# For multi-client scenarios use YAML list: client: [claude, codex]
---
```

**Field rules:**

| Field | Type | Required | Notes |
|-------|------|----------|-------|
| `number` | integer | yes | Must match `SCEN-<NNN>` in filename. Unique, never reused. |
| `name` | string | yes | Short, descriptive. Used in report headers. |
| `version` | string | yes | Always quoted (`"1.0"`). Bump on step changes. |
| `description` | multiline | yes | Use `>` folded scalar. Tell the user's story. |
| `client` | string or list | yes | AI client(s) under test: `claude`, `codex`, `gemini`, or `[claude, codex]`. |
| `interhosts` | boolean | yes | `true` if scenario involves agents on remote hosts (Tailscale mesh). |
| `device` | string | yes | Browser viewport: `desktop` (1280x800), `tablet` (1024x768), or `smartphone` (390x844). Determines which component set is tested (standard vs touch-friendly). |
| `subsystems` | list | yes | Backend modules exercised. At least 1. |
| `ui_sections` | list | yes | UI areas touched. Use `->` arrow notation. |
| `data_produced` | list | yes | Every artifact created. Include lifecycle note. |
| `rewipe-list` | list of strings | yes | File paths to back up before the scenario and restore after. May be `[]` but the standard 6 config files are the recommended minimum. Paths support `~` and `$VARS`. |
| `git-fixtures` | list of strings | yes | GitHub URLs. Local clone at `tests/scenarios/fixtures/git/<repo-name>/` with `scenario-start` tag MUST exist before the run. Scripts never clone for you. Referenced in steps as `GITFIX[n]` (0-indexed). |
| `dir-fixtures` | list of strings | yes | Absolute paths to local folders/repos used during the run. Setup resets git repos with the `scenario-start` tag. Referenced in steps as `FOLDFIX[n]` (0-indexed). |
| `browser_stack` | string | yes | `dev-browser` per Rule 8. New scenarios MUST set this field. |
| `required_tools` | list | no | Legacy chrome-devtools-mcp list from pre-2026-04-15 scenarios. Deprecated; do NOT add to new scenarios. |
| `prerequisites` | list | yes | Testable conditions. Include CLI checks (e.g., `which codex`). |
| `governance_password` | string | yes | Actual password in quotes. Referenced verbatim in steps. |
| `commit` | string | yes | Git hash or `TBD`. Updated after first successful run. |
| `author` | string | no | Person or team. |

### Phase format:

Phases are numbered starting at 0. Use `##` heading level. Phase 0 is always `SAFE-SETUP`. The last phase is always `CLEANUP`.

```markdown
## Phase 0: SAFE-SETUP
## Phase 1: <name>
## Phase 2: <name>
...
## Phase CLEANUP: Restore Original State
```

A `---` horizontal rule separates each phase.

Between phases, you may add a `> **Note:**` blockquote to explain context, known discrepancies, or what to observe. These are documentation — not executable steps.

### Step format:

Steps are numbered sequentially across all phases: S001, S002, ... S028. Never restart numbering within a phase. Use `####` heading level.

**Regular steps (creating, modifying, or verifying):**

```markdown
#### S<NNN>: <imperative action description>
- **Action:** <exact UI actions — button names, field values, passwords verbatim>
- **Goal:** <what must be true after this step — one verifiable assertion>
- **Creates:** <list of elements created, or "nothing">
- **Modifies:** <list of existing state modified, or "nothing">
- **Verify:** <how to confirm — API check, screenshot, text match in snapshot>
```

**Rules for each field:**

| Field | Required | Content |
|-------|----------|---------|
| `Action` | yes | Exact UI sequence. Spell out button labels, input values, passwords. Never write "enter password" — write `enter password \`mYkri1-xoxrap-gogtan\``. |
| `Goal` | yes | Single verifiable assertion. Not a wish — a testable fact. |
| `Creates` | yes | List of artifacts created, or `nothing`. Include where (registry, filesystem, tmux). |
| `Modifies` | yes | List of state changes, or `nothing`. Be specific (field names, file paths). |
| `Verify` | yes | How to confirm. API endpoint + expected value, screenshot filename, or snapshot text match. |

**Do NOT add** non-standard fields (Timeout, Note, Failure handling, etc.) to steps. If context is needed, put it in a blockquote before the step or phase.

**Cleanup steps (deleting, removing, restoring):**

```markdown
#### S<NNN>: Revert <what>
- **Action:** <exact UI actions to undo>
- **Goal:** <element removed / state restored>
- **Removes:** <what is being removed — replaces Creates/Modifies>
- **Verify:** <confirmation — API 404, file hash match, screenshot comparison>
```

**The last cleanup step is always STATE-WIPE:**

```markdown
#### S<LAST>: STATE-WIPE — Restore configuration files
- **Action:** Compare current config files with backups from S002. Restore any that differ.
- **Goal:** All config files match pre-test state
- **Removes:** nothing
- **Verify:** File hash comparison — all 6 files match
```

**The final step is always a post-test screenshot:**

```markdown
#### S<LAST+1>: Post-test screenshot
- **Action:** `take_screenshot` of full page
- **Goal:** UI identical to Phase 0 baseline
- **Creates:** nothing
- **Modifies:** nothing
- **Verify:** Screenshot saved. Visual comparison with baseline screenshot.
```

---

## Rule 10: PHOTOSTORY

**Every step MUST have a screenshot saved** as proof of completion. If a scenario has 40 steps, there must be 40 screenshots — no exceptions.

**Naming convention (timestamped — both directory and file):**

At the very start of each scenario run, the runner MUST generate a single run identifier in ISO 8601 basic format:

```
RUN_ID=$(date -u +%Y%m%dT%H%M%SZ)
# example: RUN_ID=20260414T143000Z
```

Every screenshot for that run is then saved under a **timestamped per-run subdirectory** AND the file itself **also carries the same timestamp**, so both the dir and the file are unambiguous even if someone moves or copies them:

```
reports/scenarios-runner/screenshots/SCEN-<NNN>_<RUN_ID>/S<NNN>_<RUN_ID>_<short-desc>.jpg
```

Examples (for a scenario run started at 2026-04-14T14:30:00Z):

```
reports/scenarios-runner/screenshots/SCEN-009_20260414T143000Z/S014_20260414T143000Z_task-sent.jpg
reports/scenarios-runner/screenshots/SCEN-009_20260414T143000Z/S033_20260414T143000Z_manager-removed.jpg
```

**Output directory note:** as of 2026-04-19, scenario outputs (reports + proposals + screenshots) live under project-root `reports/scenarios-runner/` which is **git-tracked**. The janitor plugin migrates content older than 48 hours to `reports_dev/scenarios-runner/` (gitignored) automatically. The prior path `tests/scenarios/screenshots/` is deprecated — do NOT save new screenshots there.

**Format: JPEG 97%** — not PNG. UI screenshots compress well as JPEG 97% with no visible quality loss, and saves ~50 MB per 22-scenario batch vs PNG. If your browser automation MCP only produces PNG, convert each file immediately after capture using `sips -s format jpeg -s formatOptions 97 <file>.png --out <file>.jpg && rm <file>.png`, or call `tests/scenarios/scripts/compress-screenshots.sh` at the end of your run to batch-convert. The canonical on-disk format is `.jpg`.

**Why both dir AND filename carry the timestamp:**

- The directory ensures each run has its own isolated namespace — no overwrite, no mixing, no cruft from old runs
- The filename carries the same timestamp as a safety net for when someone moves, copies, or extracts a single file outside its dir (the file still self-identifies)
- Sorting by filename puts all steps of a given run next to each other chronologically
- Multiple runs of the same scenario are trivially comparable (diff their run dirs)

**When to capture:**
- **After** the step's action is completed and the expected result is visible
- For steps that modify UI state: capture the UI showing the new state
- For API-verification steps: capture the profile panel or sidebar showing the verified data
- For cleanup steps: capture the UI confirming the artifact is removed

**The screenshot is part of the step's verification.** A step without a screenshot is considered incomplete. The report's step table must include the screenshot filename for every row.

**Why:** Screenshots create an unambiguous audit trail. When reviewing scenario results weeks later, screenshots prove what actually happened at each step, preventing false PASS claims AND preventing cross-run contamination when the same scenario is run multiple times.

### Auto-purge after fix verification (added 2026-04-15)

Screenshots are heavyweight (~50 MB per 22-scenario batch even at JPEG 97%). Once a scenario PASSES (its bugs are fixed AND verified by a re-run that landed on the same fixed code), its screenshots have served their purpose: the audit trail can be reconstructed from git history alone if needed. **In an autonomous overnight batch (Rule 13), the runner MUST auto-purge per-run screenshot directories after the scenario's fixes are confirmed verified.**

**The exact rule:** at the END of every scenario run, the runner inspects the verdict. If the verdict is `PASS` AND every bug found during the run was fixed AND the fix was verified (the previously failing step now passes), the runner deletes its own per-run screenshot directory:

```bash
rm -rf "${CLAUDE_PROJECT_DIR}/tests/scenarios/screenshots/SCEN-${NNN}_${RUN_ID}"
```

**Exceptions where screenshots MUST be kept** (do NOT delete in any of these cases):
- Verdict is `FAIL`, `PARTIAL`, or `STUCK` — the screenshots are evidence for the postmortem
- The scenario found a bug it could NOT fix (deferred to a P0 proposal) — screenshots are evidence for the proposal
- The verification re-run was NOT performed (single-pass run only) — keep until the next batch confirms
- The scenario is a smoke test or baseline run with no bugs found — screenshots are baseline evidence and stay

**The runner reports the deletion in its summary line** so the parent batch conductor can verify (the report's `screenshots_purged: true|false` field). The conductor logs total disk reclaimed at the end of the batch.

**Why this is safe:** the per-run screenshot directory uses the timestamped naming convention from earlier in this rule (`SCEN-NNN_<RUN_ID>/...`). A purge of one run's directory cannot ever affect a different run's screenshots, even for the same scenario. The git-tracked report file (`reports/scenarios-runner/SCEN-NNN_<timestamp>.report.md`) survives the purge — it records every step, every bug, every fix, and the path to the (now-deleted) screenshots, so the audit trail is intact even if a future investigation needs to re-create the visual evidence (which can be done by re-running the scenario).

---

## Rule 11: 11th-HOUR

After the scenario test completes and the report is saved, execute an **in-depth analysis** of the results. Think deeply about unsolved problems and propose concrete solutions.

**The analysis must cover:**
1. Bugs found during the run that remain unfixed
2. Pre-existing issues that interfered with the test
3. Workflow inefficiencies observed in agent behavior
4. Governance rule gaps or ambiguities exposed by the test
5. API design issues that caused agents to fail or retry

**Proposed solutions must use one or more of these methods:**

| Category | Examples |
|----------|----------|
| **Bug fixes** | Fix root cause in ai-maestro code, UI, or API (no workarounds) |
| **API improvements** | New endpoints, new options on existing endpoints, better error messages |
| **Script improvements** | New options or fixes in ai-maestro CLI scripts |
| **ai-maestro-plugin improvements** | New/improved skills, hooks, scripts in the main plugin |
| **Role-plugin improvements** | Improve main-agent .md, sub-agents, skills, or other elements |
| **Workflow rule changes** | Modify/add rules for agents with specific titles |
| **Cross-title workflow changes** | Coordinated rule changes across multiple title agents |
| **Governance rule proposals** | Changes to docs/GOVERNANCE-RULES.md |
| **Test infrastructure** | New tracking/debugging methods for scenario UI tests |
| **New scenarios** | Propose new scenarios focused on investigating specific issues |

**Output:** Save the writeup to:
```
reports/scenarios-runner/scenario_proposed-improvements_<NNN>_<datetime>.md
```

The file must reference the scenario report it is based on. Each proposal must include: problem description, root cause analysis, proposed solution with specific files/changes, and priority (P0-P3).

**This is Phase 2 / Phase 3 of the two-phase protocol.** Rule 11 proposals are **DELAYED** — they wait for explicit user approval before ANY implementation. During the overnight run (Phase 1), the scenario runner MUST ONLY write these proposals to disk. It MUST NOT implement them, MUST NOT create worktrees for them, MUST NOT open PRs for them. At end-of-batch, proposals from every scenario are consolidated into a single `CONSOLIDATED_PROPOSALS_<batch_id>.md` file (Rule 13). The user reviews that file, marks approvals, and only then does the `scenario-improvement-implementer` agent run in Phase 3 — one worktree per approved proposal, against a now-bug-free codebase. This separation is what Rule 13 enforces and why the overnight cron NEVER auto-implements Rule 11 output.

---

## Rule 12: SUDO-MODE

AI Maestro implements a **sudo-mode** layer (SEC-PHASE-3..5, v3.5.0+). Every
API route classified `strict` in `security-registry.json` rejects requests
that don't carry a fresh `X-Sudo-Token` earned by re-entering the governance
password within the last 60 seconds. The token is one-shot — it's consumed
on the first request that uses it.

### What this means for scenarios

Whenever a scenario step performs a destructive operation (delete agent,
delete team, uninstall plugin, change title, stop session, restart session,
change password, etc.), the **UI will pop a sudo password modal** the first
time you click the destructive button within a 60-second window. The modal
is implemented by `contexts/SudoContext.tsx` and handled transparently by
`lib/sudo-fetch.ts`. Every `fetch(...)` call that targets a strict route
MUST be routed through `sudoFetch` so the retry loop works.

### Scenarios MUST include the sudo step

Any step that hits a strict operation MUST also include a
**password re-entry sub-step** in its action list:

> **Action:** Click "Delete Agent" in the Danger Zone. When the sudo
> password modal appears, enter the governance password
> `mYkri1-xoxrap-gogtan` and click Confirm. Then type the agent name
> in the confirmation field and click Delete Forever.

If the scenario does NOT show the sudo modal appearing, that is a BUG
(Rule 4: fix it immediately) — either the caller is not using sudoFetch,
or the route is not classified as strict when it should be.

### List of routes classified strict

Canonical source: `security-registry.json` at the project root. At
v3.6.0 the strict routes are:

| Route | Used by scenarios |
|-------|-------------------|
| `DELETE /api/agents/[id]` | Every scenario's cleanup phase |
| `DELETE /api/teams/[id]` | SCEN-001, SCEN-002, SCEN-005, SCEN-009, SCEN-010, SCEN-014 |
| `DELETE /api/agents/cemetery` | Cleanup phase of every scenario that deletes an agent |
| `POST /api/governance/password` | SCEN-001 governance password setup |
| `DELETE /api/settings/marketplaces` | SCEN-019 cleanup |
| `DELETE /api/agents/role-plugins/install` | SCEN-019, SCEN-020, SCEN-021 cleanup |
| `PATCH /api/agents/[id]/title` | SCEN-001 title lifecycle |
| `POST /api/sessions/[id]/stop` | SCEN-011 stop session tests |
| `POST /api/sessions/[id]/restart` | Element restart queue tests |
| `PATCH /api/settings/security` | Security settings updates |

When a NEW strict route is added to `security-registry.json`, update
this table AND every scenario that touches that route.

### Sudo modal recognition pattern (dev-browser + legacy chrome-devtools-mcp)

The same DOM structure is used in both automation stacks — the modal has
`role="dialog"` and `aria-modal="true"`, so it is reliably locatable via
the accessibility tree in either stack.

**With `dev-browser` (current, Rule 8):**

```
page.snapshotForAI()      → locate modal with text "Confirm with password"
page.click(passwordInput) → focus
page.fill(passwordInput)  → type governance password
page.click("Confirm")     → submit
page.waitForModalGone()   → modal disappears
```

**With chrome-devtools-mcp (legacy, deprecated 2026-04-15):**

```
take_snapshot          → find modal with text "Confirm with password"
click (password input) → focus
fill (password input)  → type governance password
click "Confirm" button → submit
wait_for               → modal disappears
```

### 60-second window caveat

If a scenario performs multiple strict operations in a row, only the
FIRST one triggers the modal — subsequent operations within 60 seconds
of the previous sudo-token acquisition re-prompt because sudo tokens are
**one-shot**. Each strict operation needs its own fresh token. If you
batch 10 deletes in a cleanup phase, expect to see 10 modals. This is
by design (sudo-mode rejects replayed tokens) and the scenario should
plan for it accordingly.

### Team delete uses an inline password — no modal

`DELETE /api/teams/[id]` is the one exception: the existing Delete Team
dialog already collects the governance password inline before any
destructive action (because team deletion pre-dates sudo-mode and uses
the password in the request body for the governance-service layer). The
client code in `components/sidebar/TeamListView.tsx` exchanges that
inline password for a sudo token BEFORE the DELETE call, so the sudo
modal does NOT appear on top of the team delete dialog. The inline
dialog IS the sudo check.

---

## Rule 13: AUTONOMOUS-PROTOCOL

This rule defines how a long unattended scenario batch is structured so it can run for 6-12 hours without human supervision and survive every API rate-limit window the user's Pro Max 20× subscription throws at it. The protocol below is the proven 3-component cron architecture documented in TRDD-1222f06a §9.

### The two-phase workflow (IMPORTANT — read this first)

An autonomous scenario batch has **three distinct phases**, and only Phase 1 runs in the overnight cron. The earlier (failed) overnight batch tried to collapse everything into one phase by making the runner create PRs for both bug fixes AND proposal implementations — the result was that the main branch drifted so far from the PR branches that merging was impossible without burning millions of tokens on conflict resolution. This rule makes the separation absolute.

| Phase | When | What runs | What the agent is allowed to do | Output |
|---|---|---|---|---|
| **Phase 1 — Scenario execution** | Overnight, unattended | cron fires, spawns `run-scenario-test` skill per scenario | Edit source files to fix bugs **in place on the current branch** (Rule 4 FIX-AS-YOU-GO). Commit fixes per scenario. Save proposals as reports on disk. | Each scenario commits bug fixes on the current branch. Each scenario writes `SCEN-NNN_<ts>.report.md` + `scenario_proposed-improvements_<NNN>_<ts>.md`. Master cleanup writes `CONSOLIDATED_PROPOSALS_<batch_id>.md`. |
| **Phase 2 — User approval** | When the user wakes up | Interactive — the user reads the consolidated proposals file | Review proposals, edit the file to mark which P0/P1/P2/P3 items are approved, reject, or deferred. | Annotated `CONSOLIDATED_PROPOSALS_<batch_id>.md` with approvals — or an explicit `APPROVED_PROPOSALS_<batch_id>.md` file listing approved proposal IDs. |
| **Phase 3 — Proposal implementation** | After user approval, unattended but fast | The user invokes `/run-scenarios-batch --improve <range>` OR a dedicated implementer entry point. The `scenario-improvement-implementer` agent runs in `isolation: worktree` for each approved proposal. | Worktree-isolated edits for approved proposals only. Each P0 gets its own commit. Returns worktree branch name. | Each worktree branch becomes a draft PR (or the user merges the worktree back directly). Because Phase 1 already landed bug fixes on the current branch, the implementer sees a clean bug-free codebase and conflicts are minimal. |

**The overnight cron does Phase 1 ONLY.** No worktrees. No PR creation. No fork pushes. No implementer spawning. The ONLY output of Phase 1 is bug-fix commits on the current branch + report files + the consolidated proposals file.

**Why this separation exists:** the last overnight batch created ~20 worktree PRs while the main branch also accumulated ~40 bug-fix commits. Rebasing or merging each worktree PR against the drifted main branch was a ~2-hour per-PR nightmare. By deferring proposal implementation until AFTER the user approves and after the codebase is bug-free, Phase 3 becomes a fast series of clean PRs on a stable base.

### Background — why the process stays alive

Claude Code does NOT exit on rate-limit / API errors. Only the current TURN ends. The Node.js event loop, the in-memory cron scheduler, the shared dev-browser daemon, the Chromium pages — all keep running. When the rate-limit window clears (or the account switcher rotates to a fresh OAuth token), the next scheduled cron fire becomes a fresh API call that succeeds, and work resumes from where state.json left off.

### The 3 components of Phase 1

1. **Passive account switcher** — at least 2 OAuth tokens stored in `~/.claude/account-switcher/`. When the active token hits a 429, the switcher rotates instantly. The switcher does NOT wake claude — it just makes the next API call use a fresh token.

2. **Recurring durable cron** — created via `CronCreate` with `durable: true` at a 5-20 min interval. **The cron IS the wake-up mechanism.** Every fire becomes a fresh user turn. Fires that hit 429 cooldown queue and deliver in batch when the REPL goes back to idle. The cron persists in `.claude/scheduled_tasks.json` so it survives `claude --continue` restarts.

3. **Idempotent state file + run-one-step prompt** — the state file at `tests/scenarios/state/autonomous-batch-state.json` tracks which scenarios are pending / in-progress / done / failed. The cron prompt is short and idempotent: "read state, run the next pending scenario via the run-scenario-test skill, update state, exit". Each cron fire executes ONE scenario. If the same fire is delivered twice (rate-limit queue artifact), the idempotent state read makes the second fire a no-op.

### The autonomous batch state file

Path: `tests/scenarios/state/autonomous-batch-state.json` (gitignored — runtime artifact)

```json
{
  "batch_id": "auto-2026-04-15T12-00-00Z",
  "started_at": "2026-04-15T12:00:00Z",
  "completed_at": null,
  "base_branch": "feature/team-governance",
  "scenario_list": ["SCEN-001", "SCEN-002", ..., "SCEN-022"],
  "current_index": 0,
  "phase": "master_setup | running | master_cleanup | consolidated | failed",
  "scenarios": {
    "SCEN-001": {
      "status": "pending | in_progress | passed | failed | partial | stuck",
      "started_at": null,
      "completed_at": null,
      "verdict": null,
      "report_path": null,
      "improvements_path": null,
      "bugs_found": 0,
      "bugs_fixed": 0,
      "bug_fix_commit_shas": [],
      "p0_proposals_count": 0,
      "p1_proposals_count": 0,
      "p2_proposals_count": 0,
      "p3_proposals_count": 0,
      "screenshots_purged": false
    },
    ...
  },
  "consolidated_proposals_path": null,
  "rate_limit_events": []
}
```

Note: there are NO fields for `fix_branch`, `pr_url`, `pr_state` — those belong to Phase 3 and are produced by the implementer, not by the overnight cron. The overnight cron only records `bug_fix_commit_shas` (the SHAs of the Rule 4 FIX-AS-YOU-GO commits on the current branch).

The cron prompt mutates this file atomically (write to `.tmp`, then rename) at every transition.

### The cron fire prompt (verbatim — this IS the Phase 1 autonomous loop)

The cron prompt is intentionally short — it delegates the state machine to `tests/scenarios/scripts/state-machine-tick.sh`, which encapsulates stale-detection, queue advancement, and phase transitions. The cron's only job is to read the script's verdict and act on it.

```
[scenario-batch-cron]
NEXT="$(bash ${CLAUDE_PROJECT_DIR}/tests/scenarios/scripts/state-machine-tick.sh)"

case "$NEXT" in
  RUN\ *)
    SCEN="${NEXT#RUN }"
    Spawn the scenario-runner agent via the Agent tool for that SCEN.
    Wait for the runner's 2-line return. Parse verdict.
    Update tests/scenarios/state/autonomous-batch-state.json:
      scenarios.<SCEN>.status = "done"
      scenarios.<SCEN>.completed_at = now ISO 8601
      scenarios.<SCEN>.verdict = parsed
      scenarios.<SCEN>.report_path / improvements_path = parsed
      scenarios.<SCEN>.bugs_found / bugs_fixed / bug_fix_commit_shas = parsed
    Atomic write (.tmp + rename).
    If runner edited source files (Rule 4 FIX-AS-YOU-GO), commit them on the
    CURRENT branch by explicit file name only:
      `fix(scen-NNN): <summary>`
    Then a separate commit for the report + proposals:
      `docs(scen-NNN): add scenario report and proposals`
    If verdict==PASS with all bugs verified-fixed, purge the per-run screenshot
    directory per Rule 10 auto-purge.
    Stop. Exit this cron fire. The next fire picks up the next pending entry.
    ;;
  WAIT\ *)
    A scenario is in_progress with a fresh heartbeat. Another runner is
    actively working on it. Do nothing this fire — exit silently.
    ;;
  CLEANUP)
    Run the master cleanup phase (one-time):
      1. Stop dev-browser with `dev-browser stop`.
      2. STATE-WIPE restore per Rule 3.
      3. Generate reports/scenarios-runner/CONSOLIDATED_PROPOSALS_<batch_id>.md
         from all scenario_proposed-improvements_*.md produced this batch.
      4. Stage and commit the consolidated proposals file by explicit name.
      5. Update state.json to phase="consolidated".
      6. Optionally CronDelete this cron (next fire would otherwise no-op).
    ;;
  DONE)
    Phase is "consolidated" or "failed". Nothing to do — exit silently.
    ;;
  ERROR\ *)
    Print the error verbatim. Do NOT mutate state. The user reads the cron
    output and decides whether to repair the state file manually.
    ;;
esac

NEVER call any other skill or tool except as instructed above. NEVER drive the
UI yourself — that is the scenario-runner agent's job. NEVER run multiple
scenarios in one fire. NEVER create branches, worktrees, PRs. NEVER push.
NEVER spawn scenario-improvement-implementer — Phase 3 is user-triggered.
```

The cron prompt is intentionally rigid AND minimal. The state machine logic lives in `state-machine-tick.sh` (single source of truth, testable by hand with `--dry-run`). The cron's job is reduced to dispatching what the script told it to do. Idempotent. Resumable. Inspectable.

### state-machine-tick.sh — the brain

This script is the SINGLE SOURCE OF TRUTH for the autonomous batch state machine. Both the cron prompt above AND the `run-scenarios-batch` skill should call it before any decision. Its contract:

| Stdout | Meaning | Side effect |
|---|---|---|
| `RUN SCEN-NNN` | Dispatch this scenario via scenario-runner | Caller marks it `in_progress` after the runner spawns |
| `WAIT SCEN-NNN` | A runner is actively working; leave alone | None — fresh heartbeat detected |
| `CLEANUP` | No more pending; advance to master_cleanup | If phase was `running`, atomically advances to `master_cleanup` |
| `DONE` | Phase is `consolidated` or `failed` | None |
| `ERROR <reason>` | Something is wrong | None — caller must investigate |

Stale-run detection:

- Runs `python3` to introspect each `in_progress` entry
- Reads `state/runner-heartbeat-SCEN-NNN.txt` if present
- If heartbeat > 90 min (default; override with `--stale-min N`), or no heartbeat with `started_at` > 90 min, the entry is reset to `pending`, retries++ , the heartbeat file is removed, and `state/recovery.log` is appended
- Recovery is logged to stderr so the cron operator sees it; stdout stays clean for the caller

Run it any time, by hand, to inspect state without mutating: `bash tests/scenarios/scripts/state-machine-tick.sh --dry-run`

### Master setup phase (one-time, per batch)

1. `git status` must be clean — if not, abort with "working tree dirty, commit or stash first"
2. Backup config files per Rule 3 STATE-WIPE
3. `yarn build` once
4. `pm2 restart ai-maestro` once
5. First `dev-browser --browser ai-maestro-scenarios --headless --timeout 60 <<EOF ... EOF` call — this auto-spawns the daemon AND logs the dashboard in (via the aim_login helper from `tests/scenarios/scripts/dev-browser-helpers/aim-helpers.sh`). The named page `dashboard` in instance `ai-maestro-scenarios` now holds the login cookie for the rest of the batch.
6. Take a baseline screenshot of the logged-in dashboard
7. Set `phase="running"` in state.json
8. Exit the cron fire — the next fire starts running scenarios

This phase runs ONLY ONCE per batch. Per-scenario runners assume the daemon is up and the dashboard is logged in.

### Per-scenario runner (one cron fire = one scenario)

The cron fire spawns the `run-scenario-test` skill with the next pending scenario. The skill (and ultimately the `scenario-runner` agent it invokes) does Phases A-H from the runner agent definition: loads dev-browser, reads the scenario file, runs the steps, applies FIX-AS-YOU-GO for any bug found (editing source in place on the current branch), writes the scenario report, writes the proposals report, returns a 2-line verdict.

The cron fire then:
- Updates state.json with the scenario's verdict and report paths
- `git add` the explicit modified source files
- `git commit -m "fix(scen-NNN): <summary>"` — one commit for bug fixes per scenario, on the current branch
- `git add reports/scenarios-runner/SCEN-NNN_<ts>.report.md reports/scenarios-runner/scenario_proposed-improvements_<NNN>_<ts>.md`
- `git commit -m "docs(scen-NNN): add scenario report and proposals"` — separate commit for the reports
- If verdict==PASS with all bugs verified fixed, delete the per-run screenshot dir per Rule 10 auto-purge
- Exit the cron fire

No branch creation. No worktree. No `git push`. No PR draft. All of that is Phase 3.

### Master cleanup phase (one-time, at end of batch)

1. `dev-browser stop` (cleanly shuts down Chromium; note: no `daemon stop` subcommand — use `dev-browser stop`)
2. Run the project's cleanup script (kill scen* tmux sessions, restore registry/teams)
3. STATE-WIPE restore from backups
4. Generate `reports/scenarios-runner/CONSOLIDATED_PROPOSALS_<batch_id>.md` with the format below
5. Commit the consolidated file
6. Set `phase="consolidated"` in state.json — this is the terminal state, the cron will see it and stop firing
7. Optionally delete the durable cron via CronDelete

### CONSOLIDATED_PROPOSALS file format

This is the ONE file the user reads when they wake up. Its purpose is to let the user approve / reject every proposal from the entire batch in a single reading session, with all the context they need to make the decision.

```markdown
# Autonomous Batch <batch_id> — Consolidated Proposals

**Started:** <iso-ts>
**Completed:** <iso-ts>
**Base branch:** <branch-name-batch-started-on>
**Total scenarios:** <N>
**Pass:** <N>  **Fail:** <N>  **Partial:** <N>  **Stuck:** <N>
**Bugs fixed in place (Phase 1):** <N>
**Proposals pending approval (this file):** <N> P0, <N> P1, <N> P2, <N> P3
**Rate-limit events survived:** <N>

---

## Phase 1 summary — bug fixes already committed

These bug fixes were applied in-place to branch `<base_branch>` during the
overnight run, per Rule 4 FIX-AS-YOU-GO. They are already on disk and in
git history. No action required from you on these — they are the baseline
the Phase 3 implementer will build on.

| # | Scenario | Verdict | Bugs fixed | Fix commit SHAs |
|---|----------|---------|-----------|-----------------|
| 1 | SCEN-001 | PASS | 2 | abc1234, def5678 |
| 2 | SCEN-005 | PASS | 1 | 9abcdef |
...

## Phase 2 — your turn: approve proposals for Phase 3 implementation

Below is every P0/P1/P2/P3 proposal from every scenario in this batch.
**To approve a proposal, mark it with `[x]` in the checkbox next to it.**
Save this file when you are done. Then run the Phase 3 command at the bottom.

### P0 proposals (highest priority, will be implemented first)

#### SCEN-001: <proposal title>
- [ ] **Approve**
- **Scenario:** SCEN-001 — <scenario name>
- **Source report:** `reports/scenarios-runner/scenario_proposed-improvements_001_<ts>.md`
- **Problem:** <one paragraph>
- **Root cause:** <one paragraph>
- **Proposed fix:** <one paragraph — file paths, line ranges, what to change>
- **Verification:** <how Phase 3 should verify the fix landed correctly>
- **Estimated risk:** LOW | MED | HIGH
- **Dependencies:** <none / depends on P0-<other>>

#### SCEN-005: <proposal title>
- [ ] **Approve**
...

### P1 proposals

...

### P2 proposals

...

### P3 proposals

...

## Phase 3 — implement approved proposals (runs after you save this file)

After you have checked every `[x]` for the proposals you approve, run:

```bash
/run-scenarios-batch --improve <batch_id>
```

This spawns the `scenario-improvement-implementer` agent for each approved
proposal. Each implementation runs in an ISOLATED git worktree (so the
current branch is never touched during implementation), commits the change
in the worktree, and returns the worktree branch name. The parent session
(you, when the implementer returns) merges each successful worktree back
into the current branch — or discards it on failure.

Because Phase 1 already landed all bug fixes on the current branch, the
implementer in Phase 3 sees a CLEAN bug-free codebase. Conflicts between
worktrees should be minimal. Implementation is fast.

## Failed / stuck scenarios (investigate manually)

### SCEN-018 FAIL
- **Reason:** <one-line>
- **Report:** reports/scenarios-runner/SCEN-018_<ts>.report.md
- **Screenshots:** tests/scenarios/screenshots/SCEN-018_<RUN_ID>/ (kept because verdict != PASS)
- **Recommended action:** re-run manually after investigating, or delete the scenario if it's no longer relevant

## Rate-limit events during this batch

| Time (UTC) | Active account | Recovery delay | Cron fires queued |
|---|---|---|---|
| 2026-04-15T14:23 | emanuele | 8 min | 3 |
...
```

This file is what the user reads when they wake up. One file, every proposal in priority order, with approve checkboxes. No hunting through 22 separate proposal files.

### Hard rules for Phase 1 (the overnight cron)

1. **One cron fire = one atomic state machine step.** Never run multiple scenarios in one fire. Never run setup AND a scenario in one fire.
2. **Read state.json before EVERY action.** Never assume the previous fire left the system in a known state.
3. **Write state.json AFTER every action atomically** (write to `.tmp`, then rename).
4. **Bug fixes go on the CURRENT BRANCH.** Never create a branch. Never create a worktree. Never push. Never draft a PR. Never create a PR.
5. **One commit for bug fixes per scenario + one commit for reports per scenario.** Keeps git history readable: two commits per scenario.
6. **Stage files by explicit name.** Never `git add -A`, never `git add .`.
7. **Never auto-implement proposals.** The improvements file lists them; the cron never reads them except to count P0..P3 for state tracking. Implementation is Phase 3, triggered manually by the user.
8. **Never delete a scenario's screenshots if the scenario didn't pass.** Rule 10 auto-purge applies only to verified-fixed PASS runs.
9. **Never spawn the scenario-improvement-implementer agent from the cron.** That agent is invoked only in Phase 3, via the `run-scenarios-batch --improve` skill, by the user.
10. **The cron is durable** (`CronCreate({ durable: true, ... })`). The cron interval is 5-20 minutes, off-minute schedule. Default: `1-59/13 * * * *` (every 13 min starting at minute 1).

### Heartbeat protocol (added 2026-05-04 — fixes the 4-day SCEN-023 stall)

**Why this exists.** Before today, the autonomous batch had no way to distinguish a scenario that was actively running from one whose runner had died mid-execution. SCEN-023's runner died on 2026-04-30 (network drop during a long-running step) and its `status: in_progress` persisted for 4 days, deadlocking the batch via the SEQUENTIALITY GUARD. The fix below makes stale-run detection deterministic and self-healing.

**Heartbeat file (per-scenario):** `${CLAUDE_PROJECT_DIR}/tests/scenarios/state/runner-heartbeat-SCEN-NNN.txt`

```
epoch=<unix-epoch-seconds>
scenario=SCEN-NNN
phase=phase_b|phase_c|phase_d|...
step=S<NNN>     # current step, when in phase_c
```

**Runner contract:**

| When | Action |
|---|---|
| Phase B start | Self-check for prior heartbeat (see below). Write initial heartbeat with `phase=phase_b`. |
| Each step boundary in Phase C | Refresh heartbeat with `phase=phase_c step=S<NNN>`. |
| Before any wait > 60s, sub-process > 60s, or inter-agent message wait | Refresh heartbeat. |
| Clean Phase H return (PASS/FAIL/PARTIAL with reports written) | **Delete the heartbeat file.** |
| Crash, rate-limit, kill, network-drop mid-run | **Do NOT clear the heartbeat.** A leftover heartbeat is the desired signal so the recovery layer can act. |

**Runner self-recovery (Phase B step 3):**

| Heartbeat state | Action |
|---|---|
| Missing | Fresh start. Write initial heartbeat. Continue Phase B normally. |
| Fresh (< 10 min old) | Another runner is alive for this scenario. Exit immediately with `[DUPLICATE-RUNNER-DETECTED]`. Do NOT touch state.json. |
| Stale (≥ 10 min old) | Prior runner died. Per Rule 6, the prior run is INVALIDATED. Delete the stale heartbeat, log to `state/recovery.log`, restart from S001. Never "resume" mid-step. |

**Cron-side stale detection** (same algorithm, longer threshold so we don't fight the runner's own self-recovery):

The autonomous cron prompt invokes `tests/scenarios/scripts/state-machine-tick.sh` first. That script reads the state file, scans for `status: in_progress` entries, and:

1. If a heartbeat exists and is **fresh** (≤ 90 min default, configurable via `--stale-min`): emit `WAIT SCEN-NNN`. Cron leaves it alone.
2. If a heartbeat exists and is **stale** (> 90 min): reset the entry to `pending`, increment `retries`, log to `state/recovery.log`, delete the heartbeat file. Next tick will dispatch a fresh runner.
3. If no heartbeat AND `started_at` is > 90 min ago: same recovery path (treat as crashed before initial heartbeat write).
4. Else (no in_progress, pending list non-empty): emit `RUN SCEN-NNN` for the first pending. Cron dispatches.
5. Else (no pending, no in_progress, phase=running): advance phase to `master_cleanup`, emit `CLEANUP`.
6. Else (phase=master_cleanup or consolidated): emit `CLEANUP` or `DONE`.

**Recovery log format:** `state/recovery.log` is append-only. One line per recovery event:

```
2026-05-04T12:00:00Z STALE_RESET SCEN-023 heartbeat 86400s old (>5400s threshold)
2026-05-04T12:00:00Z PHASE_ADVANCE running -> master_cleanup
```

Operators read `recovery.log` after a long batch to see whether the autonomous layer ever had to step in.

### Failure modes and Phase 1 recovery

| Failure | Detection | Recovery |
|---|---|---|
| Rate limit hits mid-scenario | runner returns STUCK; heartbeat goes stale | next cron tick's `state-machine-tick.sh` resets `in_progress → pending`, dispatches fresh runner from S001 |
| Network drop / runner process killed mid-step | heartbeat goes stale (no graceful Phase H) | same as above — stale-heartbeat detection auto-recovers |
| Two runners try to drive the same scenario | second runner detects fresh heartbeat at Phase B start | second runner exits with `[DUPLICATE-RUNNER-DETECTED]`, no double-dispatch |
| dev-browser daemon crashes | Master setup health probe fails on next cron fire | cron sets `phase=master_setup_recovery`, next fire re-runs master setup |
| pm2 ai-maestro crashes | `curl /api/sessions` returns 5xx | cron sets `phase=master_setup_recovery`, next fire restarts pm2 then continues |
| State file corruption | `state-machine-tick.sh` exits with `ERROR state-file-corrupt` | cron renames corrupted file to `.corrupted-<ts>`, sets `phase=failed`, alerts in consolidated report |
| Scenario leaves the working tree dirty | `git status` after cleanup shows unstaged changes | cron commits them with `chore(scen-NNN): leftover working-tree changes` and continues — do NOT try to reconcile automatically |
| User's both OAuth accounts hit weekly quota | every cron fire fails for hours | wait it out — when one weekly quota resets, the cron picks up exactly where it left off |
| In_progress entry sits unchanged for > 90 min (any reason) | `state-machine-tick.sh` flags stale | auto-reset to `pending`, retry counter bumps, fresh dispatch |

### One last hard rule

**Never include a `claude --print` or `claude -p` invocation in the cron prompt.** The cron prompt runs INSIDE an existing claude session. Shelling out to a NEW claude process from a cron fire would be the kind of recursive nightmare we're explicitly trying to avoid. The whole architecture works because the cron is in-process.

---

## How-To: Running a Scenario

These are practical instructions for the AI assistant executing a scenario test.

### You ARE the user

In a scenario test, you are **impersonating the user**. You sit in front of the browser and interact with the dashboard exactly as a human would. This means:

- You click buttons, fill forms, read what's on screen, and make decisions based on what you see.
- When the scenario says "Create an agent", you use the wizard in the browser — not an API call.
- When you need to verify something, you look at the Profile panel, the sidebar, or the terminal output — not a curl response.

### Talk to your agents

Agents are live Claude Code instances running in tmux sessions. They can read your messages and act on them. When a scenario requires an agent to perform an action:

1. **Select the agent** in the sidebar (click its name)
2. **Type into the terminal** — click the terminal area to focus it, then type. Use arrow keys to navigate menus, Enter to confirm choices, and type text to give instructions.
3. **Or use the Prompt Builder** — the text area at the bottom of the dashboard. Type your instruction and click Send. The Prompt Builder is recommended for longer messages but is not mandatory.
4. **Read the terminal output** to see what the agent is doing and whether it succeeded
5. **Respond to the agent** if it asks questions or needs clarification — type your answer directly into the terminal or use the Prompt Builder

You interact with agents the same way a human user would: typing instructions, accepting plans, approving tool use, pasting URLs or information, navigating CLI menus with arrow keys, and pressing Enter to confirm.

If an agent refuses to do its job, pushes back, or sits idle — **talk to it**. Give it clearer instructions. Push it to act. Don't let agents slack. You are the manager of the test.

### Read what agents write

The terminal shows the agent's real-time output. **Read it.** The agent may:

- Ask for permission (approve it if appropriate for the test)
- Report errors (diagnose and fix per Rule 4)
- Request clarification (answer via the Prompt Builder)
- Show progress (wait for completion before moving to the next step)

Don't blindly move to the next step without confirming the agent completed the current action.

### Read-only monitoring is allowed

Rule 6 forbids **actions** outside the UI. But **read-only operations** to monitor agent behavior are allowed:

- **Read agent working directories** to check if files were created/modified
- **Read conversation logs** (`~/.claude/projects/.../*.jsonl`) to understand what the agent actually did
- **Read config files** to verify state after a UI action
- **Use `tmux list-sessions`** to check which agents are running
- **Use `ls`, `cat`, `grep`** on agent output files

What remains forbidden:
- Calling API endpoints with `curl` to **perform actions** (create, delete, modify)
- Running `tmux send-keys` to bypass the dashboard terminal (type via CDP instead)
- Editing config files directly (use the UI)
- Killing sessions with `tmux kill-session` (use the UI hibernate/delete)

The distinction is: **read = monitoring (allowed), write/action = must go through the browser UI**.

---

## Directory Structure

```
tests/scenarios/
  SCENARIOS_TESTS_RULES.md        ← This file
  NEXT_SCEN_NUMBER                ← Next available scenario number (plain text)
  SCEN-001_<name>.scen.md         ← Scenario definition files
  SCEN-002_<name>.scen.md
  reports/
    SCEN-001_<timestamp>.report.md ← Execution reports
  screenshots/
    SCEN-001/                      ← Screenshots per scenario run
      S001-<description>.png
      S002-<description>.png
  state-backups/
    SCEN-001_<timestamp>/          ← Config file backups for STATE-WIPE
```

---

## WARNING: Cleanup Order Is Non-Negotiable

**The #1 most common scenario test failure is wrong cleanup order.** This has caused orphan tmux sessions, orphan agent folders, and corrupt registry state.

**MANDATORY cleanup order (memorize this):**

```
STEP 1: Delete test AGENTS via UI
         Profile → Advanced → Danger Zone → Delete Agent
         ☑ Check "Also delete agent folder"
         Type agent name → Delete Forever
         (repeat for each test agent)

STEP 2: Delete test TEAMS via UI
         Teams tab → click team → Delete team
         Enter governance password
         ☑ Check "Also delete agents in this team"
         Click Delete Team
         (this also handles agents if Step 1 was skipped)

STEP 3: Purge CEMETERY entries via UI
         Settings → Cemetery tab → Purge (for each test entry)

STEP 4: Verify via API
         Check registry, teams.json, cemetery — no test artifacts

STEP 5: STATE-WIPE restore
         Compare config files with backups
         Restore ONLY files that still differ after UI cleanup
         (usually settings.json, governance.json — NOT registry/teams
          since UI delete already cleaned those)

STEP 6: Post-test screenshot
         Navigate to dashboard, compare with baseline
```

**NEVER use bash/CLI to:**
- Delete agent folders (`rm -rf ~/agents/scen-*`) — Rule 6 violation
- Kill tmux sessions (`tmux kill-session`) — use UI hibernate/delete instead
- Edit registry.json or teams.json directly — use UI or API

**If agent folders remain after UI deletion, that is a BUG (Rule 4: fix it), not a reason to bypass the UI.**

---

## Rule 14: REPORTS-TO-PROJECT-ROOT (added 2026-04-20, tightened 2026-04-21)

**Every report, every proposal, every screenshot, every log that any agent, plugin, MCP tool, skill, hook, or subagent produces MUST be written under `<main-project-root>/reports/` — and NOWHERE ELSE.** No carve-outs. No per-tool exceptions. No worktree-local paths. No `reports_dev/<tool>/` fallbacks. No `/tmp/` landing zones. Even when running inside a git worktree or a plugin cache, output resolves to the MAIN project root's `reports/` folder.

### The one-and-only path convention

```
<$MAIN_ROOT>/reports/<component>/<ts±tz>-<slug>.<ext>
```

Where:

- `<$MAIN_ROOT>` = the main project root (never the worktree — see "How to resolve" below).
- `<component>` = short kebab-case name of the agent/tool/skill producing the report. Examples: `scenarios-runner`, `parallel-tester`, `parallel-worker`, `scenario-improvement-implementer`, `research`, `llm-externalizer`, `caa`, `cpv`, `janitor`, `subconscious-tracker`. One component = one folder.
- `<ts±tz>` = ISO 8601 timestamp with timezone offset, compact form: `20260421T060000Z` (UTC) or `20260421T080000+0200` (local). Lexically sortable. NEVER bare date-only.
- `<slug>` = short kebab-case description of the report. Must be unique within the same timestamp+component.
- `<ext>` = `md` for markdown reports, `jpg`/`png` for screenshots, `log` for raw output, `json` for structured data, `html` for rendered output.

Examples of compliant paths:
- `reports/scenarios-runner/20260421T052926Z-SCEN-012.report.md`
- `reports/scenarios-runner/20260421T052926Z-SCEN-012-proposals.md`
- `reports/scenarios-runner/screenshots/SCEN-012_20260421T052926Z/S014_20260421T052926Z_verify.jpg`
- `reports/parallel-tester/20260421T005826Z-jsonl-phase2_S7_FAIL.log`
- `reports/research/20260421T060542Z-jsonl-browser-comparison-vs-claude-devtools.md`
- `reports/llm-externalizer/20260421T060000Z-code-review-agents-core.md`

Examples of NON-compliant paths (all FORBIDDEN):
- `reports_dev/llm_externalizer/report.md` (wrong top-level folder)
- `<worktree>/reports/component/report.md` (worktree-local — destroyed on cleanup)
- `/tmp/aim-report.log` (outside project)
- `reports/component/report.md` (missing timestamp)
- `reports/component/2026-04-21-report.md` (date-only, not ISO 8601 with time)
- `reports/<tool>/reports/<ts>-report.md` (tool created its own nested folder)

### Gitignore — both folders

Both `<$MAIN_ROOT>/reports/` and `<$MAIN_ROOT>/reports_dev/` are git-ignored to prevent private data (dashboard screenshots with real agent names, governance passwords, conversation transcripts, environment values, API keys in logs) from leaking through commits. This is enforced via `.gitignore` (committed) — if you ever see either folder tracked, fix the `.gitignore` and `git rm --cached -r` the offending paths.

### How to resolve the main project root

For plain agents (not in a worktree): `${CLAUDE_PROJECT_DIR}` is already the main project root. Use it directly.

For worktree-isolated agents (spawned with `isolation: worktree`): `${CLAUDE_PROJECT_DIR}` points at the **worktree**, not the main repo. To reach the main project root from inside a worktree, use:

```bash
MAIN_PROJECT_ROOT="$(cd "$(dirname "$(git rev-parse --git-common-dir)")" && pwd)"
```

`git rev-parse --git-common-dir` returns the shared `.git` directory (which lives in the main working tree, not the worktree). Its parent directory is the main working tree itself.

Every agent that writes a report then uses:

```bash
REPORTS_DIR="${MAIN_PROJECT_ROOT}/reports"
mkdir -p "${REPORTS_DIR}/<per-agent-subfolder>"
# write report files to ${REPORTS_DIR}/<per-agent-subfolder>/...
```

### LLM Externalizer and other MCP tools — no carve-outs

The LLM Externalizer MCP server's internal default `output_dir` is `<project>/reports_dev/llm_externalizer/`. That path is **non-compliant** with Rule 14 and MUST be overridden on EVERY call.

```json
{"tool": "code_task",
 "output_dir": "<$MAIN_ROOT>/reports/llm-externalizer/",
 "instructions": "...",
 "input_files_paths": "..."}
```

The same override requirement applies to every MCP tool, plugin, or skill that has its own default report path. The server/tool's factory default is documentation of the untouched factory state; your `output_dir` override always wins and MUST resolve under `<$MAIN_ROOT>/reports/<component>/`. If a tool has no `output_dir` parameter, that tool is non-compliant and you file a bug instead of using it.

### Why this rule exists

1. **Worktree cleanup erases reports.** Agents in `isolation: worktree` have their worktree destroyed after they return (or on next orchestrator cycle). If the report lives inside the worktree, it's lost.
2. **Private data must never be committed.** Reports often screenshot real governance passwords, agent names tied to user identity, conversation content. Gitignoring `reports/` + `reports_dev/` ensures this data never lands in a public branch.
3. **One location to audit.** A single `reports/` folder at project root is the authoritative place to find every agent output. No hunting across worktrees, across plugin caches, across `/tmp` scratch directories.

### What counts as a "report"

- Scenario run reports (`SCEN-NNN_<ts>.report.md`).
- 11th-HOUR proposal reports (`scenario_proposed-improvements_NNN_<ts>.md`).
- Smoke-test FAIL screenshots.
- Agent log captures, bug autopsies, audit outputs.
- Batch-level aggregation reports.
- Any file an agent produces for human review — if a human would want to read it later, it belongs in `reports/`.

**Not covered by this rule:**
- Ephemeral agent MEMORY (`/path/to/agent/.claude/agent-memory/<name>/MEMORY.md`) — that's agent-local state, not a report.
- Git-tracked design docs (`design/tasks/TRDD-*.md`) — those are committed artifacts, not reports.
- Build output (`.next/`, `dist/`, `target/`) — those have their own gitignored locations.
- User-facing docs (`docs/`) — committed documentation.

### Rollout status

This rule was added 2026-04-20. Implementation phases:

1. **Project-scoped** — done in the commit that introduced this rule:
   - `.gitignore` adds `reports/`.
   - `tests/scenarios/SCENARIOS_TESTS_RULES.md` (this file) documents the rule.
   - `.claude/agents/parallel-worker-agent.md`, `.claude/agents/parallel-tester-agent.md`, `.claude/agents/scenario-runner.md`, `.claude/agents/scenario-improvement-implementer.md` all reference the rule and use `${MAIN_PROJECT_ROOT}/reports/…` paths.
   - `.claude/skills/run-scenarios-batch/**` references the rule.
2. **Role-plugins in external repos** — separate rollout. A TRDD under `design/tasks/` lists the 8 plugin repos that must publish an update: ai-maestro-architect-agent, ai-maestro-assistant-manager-agent, ai-maestro-autonomous-agent, ai-maestro-chief-of-staff, ai-maestro-integrator-agent, ai-maestro-maintainer-agent, ai-maestro-orchestrator-agent, ai-maestro-programmer-agent — plus `ai-maestro-plugin` (the core). Each publish uses the repo's own `scripts/publish.py` workflow.
3. **Third-party plugins** — no enforcement; those plugins either adopt the rule voluntarily or their reports land outside AI Maestro's curated `reports/` tree.

Until Phase 2 completes, role-plugin agents may still write to legacy paths (typically inside their persona's working directory). The main orchestrator must NOT copy those into `reports/` — the source repo must adopt the rule explicitly.
