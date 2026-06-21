# Edit Scenario — Detailed Procedure

## Table of contents

- [Step 1 — Find the scenario file](#step-1--find-the-scenario-file)
- [Step 2 — Read the current scenario](#step-2--read-the-current-scenario)
- [Step 3 — Understand the requested edit](#step-3--understand-the-requested-edit)
- [Step 4 — Apply the edit](#step-4--apply-the-edit)
- [Step 5 — Re-validate rule compliance](#step-5--re-validate-rule-compliance)
- [Step 6 — Bump the version](#step-6--bump-the-version)

## Step 1 — Find the scenario file

Parse `$ARGUMENTS`. The first token is the scenario identifier — either a number (`18`, `007`), a padded ID (`SCEN-018`), or a filename.

Resolve to the file via glob:

```
${CLAUDE_PROJECT_DIR}/tests/scenarios/SCEN-<padded-id>_*.scen.md
```

(The scenarios folder is configurable via `scenarios.config.json` `scenariosDir`; default `tests/scenarios/`. Scenario files always carry the `.scen.md` extension.)

If no file matches, report the failure to the user and list the files that do exist in the scenarios folder. Do not create a new file from this skill — direct the user to `amwst-create-scenario` instead.

## Step 2 — Read the current scenario

Read the full file. Parse:
- Frontmatter (name, version, description, client, subsystems, ui_sections, governance_password, etc.)
- Phases (markdown `##` headings)
- Steps (markdown `####` headings)

Note the current `version:` and the highest step number. You will need both.

## Step 3 — Understand the requested edit

From the remainder of `$ARGUMENTS` and any follow-up messages from the user, identify the edit type. Common edits:

1. **Add a step after S<NNN>** — renumber subsequent steps, update Verify field references
2. **Remove a step** — renumber subsequent steps, check that removed step is not referenced by other steps' Verify fields
3. **Rewrite a step's Action / Goal / Verify** — keep step numbering intact
4. **Rewrite an entire phase** — keep phase numbering intact
5. **Update frontmatter** — change `prerequisites`, `description`, `ui_sections`, `subsystems`, `governance_password`, etc.
6. **Fix a Rule 6 violation** — rewrite any Action containing a forbidden token as a UI-only sequence
7. **Bump the version** — increment `version:` when the edit breaks prior runs' assumptions

Ask the user for clarification only if the edit scope is ambiguous. Do not guess intent.

## Step 4 — Apply the edit

Use the Edit tool to apply the change in place. Preserve:
- Frontmatter field ordering
- Blank lines between steps
- The `---` horizontal rules between phases
- Indentation (2 spaces for YAML list items)

If the edit renumbers steps, update every downstream reference: step numbers, any Verify field that references another step by ID, and any per-step screenshot filename (the screenshots use the timestamped Rule 10 naming `reports/scenarios-runner/screenshots/SCEN-<NNN>_<RUN_ID>/S<NNN>_<RUN_ID>_<short-desc>.jpg` — the `S<NNN>` segment is what tracks the step number).

## Step 5 — Re-validate rule compliance

After the edit, scan the entire file for rule violations.

**Rule 6 forbidden tokens in Action fields:**

| Token | Why forbidden | UI-only replacement |
|-------|---------------|---------------------|
| `rm` / `rm -rf` | Destructive filesystem write | Click Delete button in UI |
| `mv` | Filesystem write | Rename via UI form |
| `kill` / process-kill of an app-managed session | Bypasses UI session mgmt | Click Hibernate or Delete in the UI |
| `curl -X POST/PUT/DELETE/PATCH` | API action outside UI | Click the button that triggers it |
| `echo ... >` | Direct file write | Edit via UI or config page |
| `sed -i` | Direct file edit | Edit via UI |
| `git commit` | Project mutation | Out of scope for UI tests |

Read-only uses (Verify fields only) are allowed: `curl -s .../api/... | jq`, `cat`, `ls`, `grep`, and read-only session/listing commands.

**Rule 1 CLEAN-AFTER-YOURSELF** — every artifact added in the scenario must be removed in Phase CLEANUP. After an edit that adds a `Creates:` field, verify a matching cleanup step exists.

**Rule 2 0-IMPACT** — every created artifact must have a test-prefixed name. If an edit introduces a name without the `scen-` or `scen-test-` prefix, flag it.

**Rule 10 PHOTOSTORY** — every step must have a screenshot referenced in Verify. If an edit adds a step without a screenshot, flag it.

**Rule 12 SUDO-MODE** — if an edit touches a destructive operation (delete, change password, strict route), the Action must include the password re-entry sub-step.

**Rule 14 REPORTS-TO-PROJECT-ROOT** — any report/screenshot path the edit introduces must resolve under `${CLAUDE_PROJECT_DIR}/reports/scenarios-runner/`, never inside the scenarios folder or a worktree-local path.

Report every violation found. For each one, suggest a concrete UI-only alternative before asking the user to approve the rewrite.

## Step 6 — Bump the version

If the edit changes step numbering, changes what is verified, or changes prerequisites, bump the `version:` field in the frontmatter. Use semver: patch for typos and wording, minor for new steps or new verifications, major for restructured phases.

If the edit is cosmetic only (rewording without behavior change), leave the version alone.
