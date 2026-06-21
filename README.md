# web-scenario-tester

A Claude Code **role-plugin** that turns Claude into a browser-driven UI
scenario tester. It authors, runs, and batches end-to-end `.scen.md` scenario
tests against a **running web application**, driving the real UI through
[dev-browser](#hard-dependency-dev-browser) exactly the way a human user would —
with fix-as-you-go bug repair, screenshots, structured reports, and an
11th-hour pass that produces concrete improvement proposals after each run.

It ships as an **AI-Maestro role-plugin** (governance title **MEMBER**, prefix
`amwst-`), so an AI-Maestro persona can wear it and act as the team's scenario
tester. It also works as a plain Claude Code plugin in any project.

## What it does

- **Authors** UI scenario test files (`.scen.md`) from a plain-language
  description of a user flow.
- **Runs** one scenario end-to-end: drives the app's UI, verifies each step,
  fixes bugs it finds, captures a screenshot per step, and writes a structured
  report.
- **Batches** many scenarios — including unattended, state-machine-driven
  overnight runs — and consolidates every run's proposals into one review file.
- **Improves** scenarios and **implements** approved proposals from a batch.

The agent always plays the **human user** of the app under test. It never adopts
an in-app identity, and it never bypasses the UI to make a change (read-only
verification afterwards is fine). A single UI bypass invalidates a run.

## Hard dependency: dev-browser

This plugin **requires** the `dev-browser` plugin — it is the browser engine that
drives the app. dev-browser lives in a **different marketplace**
(`dev-browser-marketplace`), so the marketplace you install this plugin from must
explicitly allow the cross-marketplace dependency:

```json
// in your marketplace's .claude-plugin/marketplace.json
{
  "allowCrossMarketplaceDependenciesOn": ["dev-browser-marketplace"]
}
```

With that in place, installing `web-scenario-tester` pulls in `dev-browser`
automatically. At runtime the agent loads it via the `dev-browser:dev-browser`
skill (sandboxed JS scripts piped to the dev-browser CLI; persistent named pages
across invocations).

## Optional: llm-externalizer

The `llm-externalizer` plugin is **optional**. When present, the agent can use it
to analyze an agent's conversation transcript (the JSONL log) after a run to
understand what actually happened — cheaper and more capable than a Haiku
subagent. It is **not** force-installed; nothing breaks without it.

## Installation

```bash
# add the marketplace that hosts this plugin (and allows the dev-browser dep)
claude plugin marketplace add <owner>/<your-marketplace>

# install the plugin (dev-browser is pulled in as a dependency)
claude plugin install web-scenario-tester <your-marketplace>
```

Then point Claude at the role:

```bash
claude --agent web-scenario-tester-main-agent
```

Requires Claude Code `>= 2.1.110`.

## Usage

Once installed, drive the harness in plain language — the main agent loads the
matching skill (see [The 7 skills](#the-7-skills)) and does the work:

```text
"write a scenario for the checkout flow"   → authors a new .scen.md
"run scenario 16"                          → runs SCEN-016 end-to-end
"run 16, 18, 19"                           → runs them in parallel
"run the overnight batch 1-24"             → unattended, rate-limit-resilient batch
"implement the approved proposals"         → applies P0 fixes in a worktree
```

Scenario files live in the consuming project at `tests/scenarios/` (see
[Per-project scenarios](#per-project-scenarios--scenariosconfigjson)); reports,
proposals, and screenshots are written under `reports/scenarios-runner/`.

## The 7 skills

The main agent is a thin orchestrator — it loads the matching skill by name.

| Skill | What it does |
|---|---|
| `amwst-run-scenario` | Run ONE scenario end-to-end via dev-browser: drive the UI, verify each step, fix-as-you-go, screenshot per step, write a report + proposals. |
| `amwst-run-scenarios-batch` | Run a range/list of scenarios; state-machine-driven so an unattended overnight batch survives rate limits; consolidates all proposals into one review file. |
| `amwst-scenarios-rules` | The canonical rules every scenario obeys — `.scen.md` format, phase/step shape, cleanup order, STATE-WIPE, screenshot + report conventions, the run lifecycle. The single source of truth the other skills build on. |
| `amwst-create-scenario` | Author a new `.scen.md` scenario from a plain-language description of a user flow. |
| `amwst-edit-scenario` | Edit / repair an existing scenario file (steps, frontmatter, fixtures). |
| `amwst-improve-scenario` | Deepen an existing scenario after a run surfaced gaps or new edge cases. |
| `amwst-implement-scenarios-proposals` | Implement the user-approved 11th-hour proposals produced by a batch, in an isolated git worktree. |

## Per-project scenarios + `scenarios.config.json`

Scenario files are **per-project**, not bundled with this plugin. They live in
the consuming project at `tests/scenarios/` with the extension `.scen.md`
(e.g. `tests/scenarios/SCEN-001_login.scen.md`). The plugin discovers them there
and reads an optional config file:

```text
${CLAUDE_PROJECT_DIR}/tests/scenarios/scenarios.config.json
```

Common keys:

| Key | Meaning |
|---|---|
| `scenariosDir` | Where scenarios live (default `tests/scenarios/`). |
| `scenarioExt` | Scenario file extension (default `.scen.md`). |
| `appUrl` | Base URL of the running app under test. |
| `startCommand` | How to start the app (used by SAFE-SETUP). |
| `buildCommand` | How to build the app (used by FIX-AS-YOU-GO). |
| `healthCheck` | URL/command to confirm the app is up. |
| `reportsDir` | Where reports + proposals + screenshots are written. |

The agent resolves plugin-internal assets via `${CLAUDE_PLUGIN_ROOT}` (read-only)
and consumer-project paths via `${CLAUDE_PROJECT_DIR}`.

## Bootstrapping a consumer project

If a project has no scenarios folder yet, run the plugin's bootstrap script to
scaffold `tests/scenarios/` (with a starter `scenarios.config.json` and the
example scenarios to copy from):

```bash
"${CLAUDE_PLUGIN_ROOT}/bin/init-scenarios-folder.sh"
```

After that, drop your own `.scen.md` files in `tests/scenarios/` and run them.

## Authoring a `.scen.md` scenario

A scenario is one markdown file with **YAML frontmatter**, numbered **phases**,
and numbered **steps**. The fastest path is to ask the agent: *"write a scenario
for the checkout flow"* — it loads `amwst-create-scenario` and produces a
compliant file. The full format (every frontmatter field, phase/step shape,
cleanup order, screenshot + report conventions) lives in the `amwst-scenarios-rules`
skill, and two runnable examples ship under
[`examples/scenarios/`](examples/scenarios/):

- `SCEN-001_example-smoke.scen.md` — a minimal smoke test.
- `SCEN-002_example-form-flow.scen.md` — a short form-submission flow.

Shape at a glance:

```markdown
---
number: 1
name: <human-readable name>
version: "1.0"
description: >
  <what the user does, step by step, and what gets verified>
device: desktop          # desktop | tablet | smartphone
browser_stack: dev-browser
prerequisites:
  - <app running, etc.>
---

## Phase 0: SAFE-SETUP
#### S001: <action>
- **Action:** <exact UI actions>
- **Goal:** <one verifiable assertion>
- **Creates:** <artifacts, or nothing>
- **Modifies:** <state changed, or nothing>
- **Verify:** <how to confirm + screenshot>

## Phase 1: <functional phase>
...

## Phase CLEANUP: Restore Original State
...
```

## Write-guard (sentinel-gated, shipped with the plugin)

A code-modifying scenario sub-agent is confined to writing inside the project
root (and `/tmp`) by a `PreToolUse` write-guard that **ships with the plugin** —
`hooks/hooks.json` wires `scripts/amwst_subagent-write-guard.sh`. There is
nothing to install in the consuming repo.

Because a plugin hook loads in every session, the guard is **sentinel-gated**:
it is inert unless `${CLAUDE_PROJECT_DIR}/.claude/scenario_is_running.json`
exists. The run owner (the `amwst-run-scenario` / `amwst-run-scenarios-batch`
skill) creates that sentinel at run start and deletes it at run end, so the
guard is armed only for the duration of a run. The sentinel is gitignored
(`init-scenarios-folder.sh` adds it). Without the guard, `isolation: worktree`
gives filesystem isolation only — not process sandboxing. See
[references/write-guard-rule.md](references/write-guard-rule.md).

## License

MIT. See [LICENSE](LICENSE).
