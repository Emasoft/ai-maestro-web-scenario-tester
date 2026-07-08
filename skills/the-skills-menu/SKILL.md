---
name: the-skills-menu
description: "Dynamic skill menu for the web-scenario-tester plugin. Teaches agents which skills are available, when to use them, and how to load them with the Skill() tool. Use when an agent needs to pick a downstream skill at runtime. Used by every web-scenario-tester agent via the-skills-menu method (TRDD-9dd64dbf)."
user-invocable: false
---

# the-skills-menu — universal web-scenario-tester skill catalog

## Overview

This skill is the **catalog** every web-scenario-tester agent consults to
discover operational skills at runtime. The agent preloads only this
catalog in its `skills:` frontmatter; everything else loads on demand
via the `Skill()` tool.

## Prerequisites

- The calling agent has `Skill` in its `tools:` list.
- A clear task statement so you can pick the right skill.

## Instructions

Follow these steps in order:

1. Identify the task domain.
2. Skim the **Plugin Skills** section below and pick a candidate.
3. Invoke the chosen skill via `Skill({skill: "web-scenario-tester:<name>"})`
   (use the plugin namespace prefix — cross-plugin references require it).
4. Follow the loaded skill's own checklist; do NOT load another skill
   until the first one returns.
5. Surface the downstream skill's summary to the caller.

## Output

This catalog returns nothing itself — it documents invocations for
OTHER skills. The chosen downstream skill produces the actual output.

## Standalone Skills

No standalone (user/local/project-scope) skills are tracked by this
plugin's catalog yet. Add entries here as the plugin starts to
reference standalone skills outside its own namespace.

## Plugin Skills

The web-scenario-tester plugin ships the operational skills below. Pick the one your task needs and load it on demand:

| # | Skill | What it does |
|---|-------|--------------|
| 1 | `amwst-create-scenario` | >- |
| 2 | `amwst-edit-scenario` | >- |
| 3 | `amwst-implement-scenarios-proposals` | >- |
| 4 | `amwst-improve-scenario` | >- |
| 5 | `amwst-phase-execute` | >- |
| 6 | `amwst-phase-fixasyougo` | >- |
| 7 | `amwst-phase-proposals` | >- |
| 8 | `amwst-region-capture` | >- |
| 9 | `amwst-run-scenario` | >- |
| 10 | `amwst-run-scenarios-batch` | >- |
| 11 | `amwst-scenarios-rules` | >- |
| 12 | `amwst-step-batch` | >- |
| 13 | `amwst-validate-scenario` | >- |

All entries above are invoked as
`Skill({skill: "web-scenario-tester:<name>"})`.

## Resources

- [the-skills-menu-create](../the-skills-menu-create/SKILL.md) —
  the migrator skill in the CPV plugin that can regenerate this
  catalog from the plugin's current skill inventory at any time
  (not bundled in this plugin; install
  `claude-plugins-validation` to access it).
