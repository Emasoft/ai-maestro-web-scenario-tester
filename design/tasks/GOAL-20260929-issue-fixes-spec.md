# Work spec: issues #2 and #3 fixes (goal session 2026-09-29)

Repo: this repo (plugin `web-scenario-tester`, v0.1.7 at spec time)
Base: commit 923e880 (PR #4 merged — password-literal mandate already fixed upstream of this spec).

## Job A — Issue #3 regression guard (CI + validator)

Issue #3's remaining ask: "A CI check that fails when `governance_password` appears with a quoted
value anywhere under `references/` or `skills/` — the pattern, not the value."

State after PR #4: the rules doc no longer mandates the literal; occurrences at
references/SCENARIOS_TESTS_RULES.md:546,786 carry env-var NAME (`"$MYAPP_TEST_PASSWORD"`), which
is the sanctioned form. The guard must therefore flag a quoted value that is NOT an env-var-name
pattern, i.e. flag `governance_password: "<value>"` where `<value>` is not `$VARNAME`-shaped.

Implement:
1. Extend `scripts/amwst-validate-scenario.py` (stdlib only, keep style) with a new check in
   `validate()`: if frontmatter key `governance_password` is present and its value is quoted but
   does NOT match `^\$[A-Z_][A-Z0-9_]*$` (env-var NAME form), emit an ERROR:
   "governance_password must carry the env var NAME (\"$MYAPP_TEST_PASSWORD\"), never a literal
   credential — see Rule 12 (THE PASSWORD NEVER PASSES THROUGH A MODEL)". This guards new
   scenario files at authoring time.
2. Add a repo-level grep guard as a new test in `tests/test_password_guard.py` (pytest, stdlib
   only): walk `references/` and `skills/` (absolute paths from REPO_ROOT as in the existing
   tests), fail on any `governance_password: "..."` line whose quoted value is not `$VARNAME`-shaped
   and not a documented placeholder from this allowlist: `$MYAPP_TEST_PASSWORD`. Also assert the
   same for `AIM_GOVERNANCE_PASSWORD=` followed by a non-empty value in any file (env FILES never
   committed; the pattern catches a committed default). Keep the test fast (glob *.md, *.py,
   *.json, *.sh, *.yml under those two dirs only).
3. Verify: `uv run pytest tests/ -q` passes; run the validator on a synthetic bad file in /tmp to
   prove the error fires, and on an existing reference file to prove no false positive.

## Job B — Issue #2 cleanup rules (lift from ai-maestro 496355e5, renamed)

Source text is proven — lifted from Emasoft/ai-maestro commit 496355e5, adapted to this plugin's
element names (amwst-*). NOTE: this plugin's rules doc is ai-maestro-specific already (Rule 0
talks `~/agents/`, registry.json, cemetery), so the ai-maestro paths stay. Apply these 4 edits:

1. `references/SCENARIOS_TESTS_RULES.md` — insert after the Rule 1 intro block (after line 111
   "The UI must look identical.", before the `---` at line 113), these new subsections with the
   ai-maestro wording adapted:
   - `### The debt is owed when the RUN ENDS — not when the last phase ends` — the 6-row
     who-cleans-when table + "If you cannot clean up, you must SAY SO EXPLICITLY" paragraph.
   - `### Keep a live artifact ledger — you cannot delete what you never wrote down` — the
     write-as-you-go ledger bullet list (agents incl. auto-COS, teams/groups, tmux sessions,
     GitHub repos/forks/issues/PRs/branches, files outside reports/, rewipe-list config
     mutations).
   - `### Deleting an agent means deleting ALL of it — go through the pipeline, never by hand` —
     full text incl. the NEVER-rm-rf loop incident (2026-07-25, PersistedSession G05b), soft vs
     hard delete, cemetery purge, "a pipeline bug is fixed with Rule 4, never shell".
   - `### Verify by absence, not by intention` — the 6-command verify block + "A leftover found
     here is not bookkeeping" line.
2. Same file, Rule 13's runner self-recovery table (~line 1241, "Stale (≥ 10 min old)" row) —
   replace the row text with the amended version that FIRST runs the Rule-1 cleanup for the dead
   run's artifacts (ledger, sweep ~/agents/, tmux, registry, sessions.json, cemetery, gh repos)
   before deleting the heartbeat and restarting from S001.
3. Same file, cron-side stale detection step 2 (~line 1248) — prepend the artifact-cleanup-first
   clause as in the reference ("clean up the dead run's artifacts first … a pending reset without
   cleanup hands the next runner a half-built fleet").
4. `agents/amwst-scenario-runner.md` — insert a new subsection `### Cleanup is owed on EVERY exit
   path — not only the happy one` after the Phase F row's phase map (after line 52's table, or as
   a section after "The protocol reference" section — place it directly before `## Token
   discipline`), with the reference text (exit-path list incl. user-stop; artifact ledger
   write-as-you-go; UI-only Delete Agent pipeline; never rm -rf; verify-by-absence block; name
   unremovable artifacts in the return lines; the return gate "you may not return until Phase F
   has run"). Also add one line to the Phase F table row: "and on EVERY exit path (BLOCKED,
   STUCK, DEFERRED, user-stop included)".
5. `skills/amwst-run-scenarios-batch/SKILL.md` — insert `### Cleanup is the conductor's
   responsibility too (Rule 1)` after the Workflow section (before `### Rules reference`), with
   the reference text (BLOCKED/STUCK/died runner cleanup before a pending reset; user-stops-batch
   means stop AND clean; end-of-batch verify-by-absence command list; name unremovable leftovers
   in the batch summary by name).

## Job C — 3-pillars / janitor-tool integration (from ai-maestro maintainer brief)

The plugin must not depend on the 3-pillar tools (they are project-governance tooling, and this
plugin's skills target CONSUMER projects), but its reporting/visibility surfaces should know the
canon. Minimal adoption, cite don't copy:
1. `agents/web-scenario-tester-main-agent.md` and `agents/amwst-scenario-runner.md` memory
   sections: add one line each — "This project's kanban/TRDD corpus is maintained via `trddgrep`
   (3-pillars 3.0.0; cite PRRD G2.1); scenario reports are REPORTS, never TRDD cards (Rule 14)."
2. `references/SCENARIOS_TESTS_RULES.md` Rule 14 section: add one line: "A scenario report is
   never converted into a TRDD/kanban card; if a finding needs a tracked task, the consumer
   project files it with `trddgrep new` (3-pillars governance, PRRD G2.1)."

## Constraints (bind every worker)

- RULE 0: nothing deleted; edits only. Do not touch `design/refused/`.
- Editing tooling: use fastedit / Edit tool. NEVER sed -i / perl / heredoc rewrites.
- No version bump, no commit, no push — orchestrator commits.
- Do not modify `scripts/publish.py` (CPV agent is working it concurrently) or anything under
  `.github/`.
- Test after your change: from the repo root, `uv run pytest tests/ -q` (Job A) or, for Jobs B/C, verify the edited files with `tldr structure`/read-back and re-grep the edited markers.
