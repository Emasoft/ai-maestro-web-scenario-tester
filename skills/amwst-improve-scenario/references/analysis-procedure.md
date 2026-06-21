# Improve Scenario — Analysis Procedure

## Table of contents

- [Step 1 — Locate the scenario and its history](#step-1--locate-the-scenario-and-its-history)
- [Step 2 — Read the reports](#step-2--read-the-reports)
- [Step 3 — Identify patterns](#step-3--identify-patterns)
- [Step 4 — Draft proposed changes](#step-4--draft-proposed-changes)
- [Step 5 — Write the analysis report](#step-5--write-the-analysis-report)

## Step 1 — Locate the scenario and its history

Parse `$ARGUMENTS` to get the scenario number. Resolve the scenario file:

```
${CLAUDE_PROJECT_DIR}/tests/scenarios/SCEN-<padded-id>_*.scen.md
```

(The scenarios folder is configurable via `scenarios.config.json` `scenariosDir`; default `tests/scenarios/`. Scenario files always carry the `.scen.md` extension.)

Then collect every report related to this scenario by globbing the project-root reports folder (Rule 14 — REPORTS-TO-PROJECT-ROOT; run reports and proposals live under `${CLAUDE_PROJECT_DIR}/reports/scenarios-runner/`, NOT inside the scenarios folder):

```
${CLAUDE_PROJECT_DIR}/reports/scenarios-runner/SCEN-<padded-id>_*.report.md
${CLAUDE_PROJECT_DIR}/reports/scenarios-runner/scenario_proposed-improvements_<padded-id>_*.md
```

Sort all matches by timestamp (descending — newest first). If zero reports exist, tell the user: "SCEN-<padded-id> has no run history yet. Run it at least once via `amwst-run-scenario <N>` (or `amwst-run-scenarios-batch <N>`) before asking for improvements." Stop.

## Step 2 — Read the reports

Read every report file in chronological order (oldest first — you need the trajectory, not just the latest). For each report, extract:

- Step table (Step ID, Action, Status: PASS/FAIL/FIXED, Screenshot)
- Bugs Found & Fixed section
- Issues Noticed (Non-Blocking) section
- Cleanup Verification outcome
- State-Wipe Verification outcome
- Commit hash at start and end

Read each `scenario_proposed-improvements_*.md` to extract the P0 items.

## Step 3 — Identify patterns

Look for recurring problems across runs. Common patterns:

1. **Flaky step** — same step passes on some runs and fails on others. Usually a missing wait, race condition, or timing-sensitive verification.
2. **Repeatedly-fixed bug** — same bug appears across multiple runs even after a "fix" was applied. Indicates the fix was a band-aid and the scenario's verification is too weak to catch it permanently.
3. **Missing coverage** — user reports or proposals suggest a feature was touched but never verified. Add a Verify field referencing that feature's UI state.
4. **Unclear verification** — a step's Verify field is vague (`Verify: item is shown`) and runs produce ambiguous PASS/FAIL. Tighten to an exact text match or screenshot comparison.
5. **Cleanup drift** — the scenario's cleanup phase missed an artifact in some runs. Add explicit cleanup step.
6. **Wrong cleanup order** — sessions or created folders leak because cleanup deletes resources in the wrong order. Reorder the cleanup phase.
7. **Rule 6 violation that crept in** — a previous edit introduced a forbidden token (bash deletion, curl API call) that ran without being caught.
8. **Prerequisite drift** — a prerequisite was added to the app but never added to the scenario's frontmatter, causing intermittent failures.

Think deeply about each pattern. Do not propose a change unless it is supported by at least two runs or one catastrophic failure.

## Step 4 — Draft proposed changes

For each pattern identified, draft a concrete proposed change to the scenario file. Each proposal has four fields:

1. **Pattern** — short name for the issue (e.g. "Flaky S014: missing wait after item send")
2. **Evidence** — which runs showed the pattern (reference report filenames and step IDs)
3. **Proposed change** — the exact edit to make to the scenario file (old text → new text, or "add new step after S014")
4. **Priority** — P0 (blocks reliable runs), P1 (improves stability), P2 (nice-to-have), P3 (cosmetic)

Do NOT edit the scenario file from this skill. The `amwst-edit-scenario` skill is the authoritative path for applying edits. Your output is a proposal document.

## Step 5 — Write the analysis report

Save the analysis under the project-root reports folder (Rule 14):

```
${CLAUDE_PROJECT_DIR}/reports/scenarios-runner/scenario-improvement-analysis_<padded-id>_<timestamp>.md
```

Structure:

```markdown
# Scenario Improvement Analysis: SCEN-<padded-id>

**Analyzed at:** <ISO timestamp>
**Runs analyzed:** <N>
**Current scenario version:** <version from frontmatter>

## Summary
<2-3 sentences: what patterns emerged, how many proposals, priority mix>

## Run History
| Run | Timestamp | Commit | Result | Bugs Found | Bugs Fixed |
|-----|-----------|--------|--------|------------|------------|

## Identified Patterns

### Pattern 1: <name>
- **Priority:** P0 | P1 | P2 | P3
- **Evidence:** <list of runs + step IDs>
- **Proposed change:**
  <old text or step block>
  →
  <new text or step block>

## Recommended next action
<Which proposals to apply first; reference `amwst-edit-scenario` as the tool to apply them.>
```
