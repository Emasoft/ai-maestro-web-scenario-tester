# Implement Scenarios Proposals — Detailed Procedure

## Table of contents

- [Step 1 — Discover proposal files](#step-1--discover-proposal-files)
- [Step 2 — Read every proposal file and extract P0 items](#step-2--read-every-proposal-file-and-extract-p0-items)
- [Step 3 — Confirm with the user](#step-3--confirm-with-the-user)
- [Step 4 — Spawn the implementer subagent](#step-4--spawn-the-implementer-subagent)
- [Step 5 — Parse the implementer's result](#step-5--parse-the-implementers-result)
- [Step 6 — Never merge automatically](#step-6--never-merge-automatically)
- [Step 7 — Write the implementation summary](#step-7--write-the-implementation-summary)

## Step 1 — Discover proposal files

Parse `$ARGUMENTS`. Accept any of these forms:

- **Scenario number:** `18` → match `scenario_proposed-improvements_018_*.md`
- **Scenario range:** `16-20` → match all proposals for scenarios 16, 17, 18, 19, 20
- **Comma list:** `16,18,19` → match proposals for exactly those scenarios
- **Timestamp:** `2026-04-13_0230` → match all proposals with that timestamp suffix
- **Empty / "last batch":** glob all `scenario_proposed-improvements_*.md` newer than the most recent `scenario-batch-*_*.md` aggregate report

Glob the project-root reports folder (Rule 14 — REPORTS-TO-PROJECT-ROOT; proposals live under `${CLAUDE_PROJECT_DIR}/reports/scenarios-runner/`, NOT inside the scenarios folder):

```
${CLAUDE_PROJECT_DIR}/reports/scenarios-runner/scenario_proposed-improvements_*.md
```

Filter by the parsed arguments. Sort by scenario number ascending, then timestamp descending (newest first when duplicates exist).

If no files match, tell the user: "No proposal files matched `<arguments>`. Run the scenarios first via `amwst-run-scenarios-batch` to produce proposals." Stop.

## Step 2 — Read every proposal file and extract P0 items

Read each matched file in full. For each one, extract:

- Scenario ID
- Timestamp
- P0 items only (ignore P1, P2, P3 — they are not this skill's job)
- For each P0 item: problem description, root cause, proposed solution, affected files

Build a consolidated list of P0 items grouped by scenario. Count the total.

## Step 3 — Confirm with the user

Present the consolidated list in a compact format:

```
Found <N> P0 proposals across <M> scenarios:

SCEN-018 (3 P0 items):
  - [file.ts:120] Add a wait after item send
  - [api/items.ts] Return item ID on creation
  - [ItemCard.tsx] Show blocked state on drag-over

SCEN-019 (2 P0 items):
  - ...

Proceed with implementer spawn? (yes/no)
```

Wait for the user to confirm. If they say no, stop without spawning anything. If they say yes, continue.

## Step 4 — Spawn the implementer subagent

The `amwst-scenario-improvement-implementer` subagent is defined in the plugin's `agents/` folder with `isolation: worktree` in its frontmatter. That frontmatter flag tells the Agent tool to create a new git worktree, check out a fresh branch, and run the subagent entirely inside it. You do NOT have to create the worktree yourself — it is handled by the Agent tool based on the subagent's frontmatter.

Spawn via the Agent tool:

```
Agent(
    description: "Implement P0 proposals for <scenario-list>",
    subagent_type: "amwst-scenario-improvement-implementer",
    prompt: "Implement P0 items from the following proposal files: <newline-separated absolute paths>. Project: ${CLAUDE_PROJECT_DIR}. Rules file: <resolved-rules-path>. For each P0 item: read the proposal, locate the affected file, apply the minimum surgical fix, run the project's test/build command if one is present (read it from scenarios.config.json or auto-detect), commit each fix as a separate commit with a descriptive message. Do NOT push — leave the branch local for the user to review. Return IMPLEMENTATIONS_DONE <branch-name> <commits-count> or IMPLEMENTATIONS_FAIL <reason> as the final line."
)
```

## Step 5 — Parse the implementer's result

The subagent returns one of two result formats as its final line:

1. **`IMPLEMENTATIONS_DONE <branch-name> <commits-count>`** — success.
2. **`IMPLEMENTATIONS_FAIL <reason>`** — failure. Agent tool auto-cleans up the worktree.

## Step 6 — Never merge automatically

**Do NOT merge the branch from this skill.** The user is responsible for reviewing the commits, re-running the scenarios against the branch to verify the fixes, and merging.

## Step 7 — Write the implementation summary

Save under the project-root reports folder (Rule 14): `${CLAUDE_PROJECT_DIR}/reports/scenarios-runner/scenario-implementations-summary_<timestamp>.md`:

- List of proposal files consumed
- P0 item count grouped by scenario
- Implementer final result (DONE/FAIL)
- Branch name (if DONE)
- Next steps: "Review commits on `<branch-name>`, re-run affected scenarios via `amwst-run-scenarios-batch <range>`, merge when green."

## Hard rules

1. **NEVER spawn `claude -p` or subprocess** — use Agent tool exclusively.
2. **NEVER edit source code directly** — the implementer subagent is the only authorized editor.
3. **NEVER merge the implementer's branch** — the user merges.
4. **NEVER push to remote** — branch stays local.
5. **NEVER touch DB migrations or external service state** — source-code only.
6. **NEVER use `git add -A`** — the implementer stages files by explicit name.
