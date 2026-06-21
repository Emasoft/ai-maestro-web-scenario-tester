# Create Scenario — Authoring Walkthrough

## Table of contents

- [Step 1 — Ensure the scenarios folder exists](#step-1--ensure-the-scenarios-folder-exists)
- [Step 2 — Assign the next scenario number](#step-2--assign-the-next-scenario-number)
- [Step 3 — Interview the user](#step-3--interview-the-user)
- [Step 4 — Draft the frontmatter](#step-4--draft-the-frontmatter)
- [Step 5 — Draft the phases and steps](#step-5--draft-the-phases-and-steps)
- [Step 6 — Enforce the rules while drafting](#step-6--enforce-the-rules-while-drafting)
- [Step 7 — Save the scenario file](#step-7--save-the-scenario-file)
- [Step 8 — Bump NEXT_SCEN_NUMBER](#step-8--bump-next_scen_number)

## Step 1 — Ensure the scenarios folder exists

Check for `${CLAUDE_PROJECT_DIR}/tests/scenarios/` (or the path in `scenarios.config.json` `scenariosDir`). A project that has already been bootstrapped has this folder set up (`SCEN-*.scen.md`, `SCENARIOS_TESTS_RULES.md`, `NEXT_SCEN_NUMBER`, `state/`, `scripts/`, etc.), so this step is normally a no-op. If the folder or any required subdirectory is missing, run `init-scenarios-folder.sh ${CLAUDE_PROJECT_DIR}` to bootstrap it (it seeds the rules doc from the bundled copy, creates `NEXT_SCEN_NUMBER=1`, and the empty `state/` + `reports/scenarios-runner/` dirs).

If a consumer copy of the rules doc is expected at `${CLAUDE_PROJECT_DIR}/tests/scenarios/SCENARIOS_TESTS_RULES.md` but is missing, fall back to the bundled canonical at `${CLAUDE_PLUGIN_ROOT}/references/SCENARIOS_TESTS_RULES.md`. Do NOT try to regenerate the rules text by hand; the canonical version ships with the plugin.

## Step 2 — Assign the next scenario number

Read `${CLAUDE_PROJECT_DIR}/tests/scenarios/NEXT_SCEN_NUMBER`. The content is a plain integer (e.g. `19`). Store this as `NEXT_N`.

Zero-pad to 3 digits: `NEXT_N=7` → `SCEN-007`. This padded form is the scenario ID.

Do NOT bump the file yet — wait until the scenario file is saved in Step 7.

## Step 3 — Interview the user

Ask the user a structured set of questions. Do not dump them all at once — interleave questions with what you already know from `$ARGUMENTS`. The fields you need to lock down before drafting:

1. **name** — short, kebab-case or human-readable (e.g. `title-change-lifecycle`)
2. **description** — 2-4 sentences telling the story: what the user does, what they see, what gets verified
3. **client** — which app/runner is under test, if the project distinguishes (otherwise omit or set a single value)
4. **interhosts** — true if remote hosts participate, false otherwise
5. **device** — `desktop`, `tablet`, or `smartphone`
6. **subsystems** — list of backend modules exercised (pick from the project's actual modules — ask the user, do not guess)
7. **ui_sections** — list of UI areas touched, in `Section -> Tab -> Element` arrow notation
8. **data_produced** — every artifact created during the test, with lifecycle notes
9. **prerequisites** — testable preconditions (server up, credential set, CLI binary installed, etc.)
10. **credential** (if the project has a re-auth gate — Rule 12) — the actual value in quotes, referenced verbatim in steps
11. **phases** — the sequence of test phases (always start with Phase 0 SAFE-SETUP and end with Phase CLEANUP)
12. **steps** — the numbered sequence of steps within each phase (S001, S002, ...)

If the project has a credential/re-auth concept, ask the user for the value verbatim. Do not invent or guess — it must be referenced verbatim in steps.

## Step 4 — Draft the frontmatter

Use the exact field set from the rules file. Required fields: `number`, `name`, `version`, `description`, `client`, `interhosts`, `device`, `subsystems`, `ui_sections`, `data_produced`, `rewipe-list`, `git-fixtures`, `dir-fixtures`, `browser_stack`, `prerequisites`, the project credential field (if the project uses a re-auth gate), `commit`, and optionally `author`.

The browser stack is **dev-browser** (Rule 8). Set:

```yaml
browser_stack: dev-browser
```

Do NOT add a `required_tools:` list — the chrome-devtools MCP tool list is the deprecated pre-2026-04-15 shape and must not be used in new scenarios. The runner drives the app through the `dev-browser` CLI (loaded via the `dev-browser:dev-browser` skill), not through chrome-devtools MCP.

Set `commit: TBD` and `version: "1.0"` for new scenarios. Leave `git-fixtures: []` / `dir-fixtures: []` unless the scenario needs external fixtures (in which case prepare the local clone/tag first — see the canonical rules doc).

## Step 5 — Draft the phases and steps

Phases use `##` heading level and start at Phase 0. The last phase is always `Phase CLEANUP: Restore Original State`. Between phases, use `---` horizontal rules.

Each step is a `####` heading with this exact structure:

```markdown
#### S<NNN>: <imperative action description>
- **Action:** <exact UI sequence — button labels, field values, credentials verbatim>
- **Goal:** <one verifiable assertion>
- **Creates:** <list of artifacts or "nothing">
- **Modifies:** <list of state changes or "nothing">
- **Verify:** <how to confirm — read-only API check, screenshot match, accessibility-snapshot text>
```

Number steps sequentially **across all phases** (S001, S002, ..., never restarting). Do not add non-standard fields (Timeout, Note, Failure handling) inside step blocks — put context in a blockquote before the step or phase.

## Step 6 — Enforce the rules while drafting

Every step you draft must comply with:

- **Rule 1 CLEAN-AFTER-YOURSELF** — the last phase reverts everything created
- **Rule 2 0-IMPACT** — use test-prefixed names (`scen-test-*`, `scen-<name>-*`) for all created artifacts; never mutate existing user resources
- **Rule 6 STICK-TO-UI** — every Action must be a UI interaction (click, fill, wait). No `rm`, `mv`, `kill`, `curl -X POST|PUT|DELETE|PATCH`, or `echo ... >` in Action fields. Read-only state verification via API or `cat` is allowed in Verify fields only.
- **Rule 8 DEV-BROWSER** — every UI interaction is driven through the `dev-browser` CLI; snapshot the accessibility tree before interacting. No chrome-devtools MCP steps.
- **Rule 10 PHOTOSTORY** — every step must have a timestamped screenshot saved under the project-root `reports/scenarios-runner/screenshots/`; the Verify field references the screenshot filename
- **Rule 12 SUDO-MODE** — if the step hits a destructive operation (delete, change credential, etc.) and the project has a re-auth gate, the Action must include the credential re-entry sub-step
- **Rule 14 REPORTS-TO-PROJECT-ROOT** — any report/screenshot path the scenario references resolves under the MAIN project-root `reports/`, never a worktree-local path

Scan every Action field you draft for forbidden tokens before saving. If you find any, rewrite the Action as a UI-only sequence.

## Step 7 — Save the scenario file

Write the file to:

```
${CLAUDE_PROJECT_DIR}/tests/scenarios/SCEN-<padded-id>_<slug>.scen.md
```

The slug is derived from the `name` field (lowercase, kebab-case, 2-5 words). Example: `SCEN-019_marketplace-install-uninstall.scen.md`. The `.scen.md` extension is mandatory (a bare `*.md` scenario is wrong).

## Step 8 — Bump NEXT_SCEN_NUMBER

After the file is written, write `NEXT_N + 1` to `${CLAUDE_PROJECT_DIR}/tests/scenarios/NEXT_SCEN_NUMBER`. This reserves the next integer for the next scenario author.
