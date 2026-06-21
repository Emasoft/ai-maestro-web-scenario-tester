---
name: amwst-implement-scenarios-proposals
description: >-
  Use when proposal files need P0 items applied to code. Trigger with
  "implement proposals from scenario N" or "fix P0 issues from last batch".
  Spawns implementer in an isolated git worktree.
argument-hint: timestamp-or-scenario-range
disable-model-invocation: false
model: opus
---

# Implement Scenarios Proposals — proposal-to-code bridge

## Overview

You are the bridge between scenario run analysis and application source code changes. Find the relevant `scenario_proposed-improvements_*.md` files, show them to the user for confirmation, and hand off the actual code changes to the `amwst-scenario-improvement-implementer` subagent (which runs in a git worktree).

You do NOT edit application source code directly. Your role is discovery, confirmation, and orchestration.

## Prerequisites

- Proposal files at `${CLAUDE_PROJECT_DIR}/reports/scenarios-runner/scenario_proposed-improvements_*.md`
- Project with a valid git repo (the implementer needs a worktree)
- Build/test command available in the project (optional but recommended; the implementer reads it from `scenarios.config.json` or auto-detects it)

## Instructions

### Checklist

Copy this checklist and track your progress:

- [ ] Parse `$ARGUMENTS` to identify which proposal files to consume
- [ ] Glob `reports/scenarios-runner/scenario_proposed-improvements_*.md` and filter
- [ ] Read each matched file and extract P0 items only
- [ ] Present consolidated P0 list to user; wait for confirmation
- [ ] Spawn `amwst-scenario-improvement-implementer` subagent via Agent tool
- [ ] Parse subagent result (IMPLEMENTATIONS_DONE / IMPLEMENTATIONS_FAIL)
- [ ] Write implementation summary to `${CLAUDE_PROJECT_DIR}/reports/scenarios-runner/`
- [ ] Return 3-line final summary

### Workflow

1. Parse `$ARGUMENTS` to identify which proposal files to consume.
2. Glob proposal files matching the range or timestamp; stop if none found.
3. Read each file and extract P0 items only.
4. Present the consolidated P0 list to the user and wait for confirmation.
5. Spawn the `amwst-scenario-improvement-implementer` subagent via Agent tool.
6. Parse the subagent result (IMPLEMENTATIONS_DONE or IMPLEMENTATIONS_FAIL).
7. Write the implementation summary to `${CLAUDE_PROJECT_DIR}/reports/scenarios-runner/`.
8. Return a 3-line final summary.

### Rules reference

Canonical rules file: `${CLAUDE_PLUGIN_ROOT}/references/SCENARIOS_TESTS_RULES.md` (the bundled canonical copy of the 14 mandatory rules). A consuming project MAY override it at `${CLAUDE_PROJECT_DIR}/tests/scenarios/SCENARIOS_TESTS_RULES.md` — prefer the consumer copy when it exists, else the bundled one. Pass the resolved path into the implementer subagent prompt.

See [Detailed Procedure](references/p0-implementation-patterns.md) for the full 7-step flow, argument format table (range, comma list, timestamp, "last batch"), and implementer subagent spawn template.

## Output

```
PROPOSALS_IMPLEMENTED <P0-count> items | Result: <DONE|FAIL>
Branch: <branch-name or "none">
Summary: <absolute-path-to-summary-report>
```

## Error Handling

| Error | Action |
|-------|--------|
| No matching proposal files | Tell user to run scenarios first; stop |
| User declines confirmation | Stop; do not spawn subagent |
| IMPLEMENTATIONS_FAIL | Log reason in batch report; tell user to inspect worktree or re-run proposals |
| Build fails in worktree | Implementer reports FAIL; worktree is auto-cleaned |

## Examples

```
/amwst-implement-scenarios-proposals 18
/amwst-implement-scenarios-proposals 16-20
/amwst-implement-scenarios-proposals last batch
```

## Resources

- [Detailed Procedure](references/p0-implementation-patterns.md) — full 7-step flow including argument parsing, proposal extraction, subagent spawn template, and summary format
  - Step 1 — Discover proposal files
  - Step 2 — Read every proposal file and extract P0 items
  - Step 3 — Confirm with the user
  - Step 4 — Spawn the implementer subagent
  - Step 5 — Parse the implementer's result
  - Step 6 — Never merge automatically
  - Step 7 — Write the implementation summary
