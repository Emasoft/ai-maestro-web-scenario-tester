# Scenario Tests Rules — pointer

This skill does **not** carry its own copy of the rules doc. The canonical,
full-length rules text is bundled once at the plugin root:

```
${CLAUDE_PLUGIN_ROOT}/references/SCENARIOS_TESTS_RULES.md
```

Read that file for the complete 14-rule spec (Rule 0 + Rules 1-14), the
scenario file format, the device-emulation presets, the phase/step templates,
the autonomous-batch cron protocol, and the non-negotiable cleanup order.

A consuming project MAY override the canonical doc with its own copy at:

```
${CLAUDE_PROJECT_DIR}/tests/scenarios/SCENARIOS_TESTS_RULES.md
```

(seeded by `init-scenarios-folder.sh` from the bundled copy). Prefer the
consumer copy when it exists; otherwise read the bundled one.

A short summary of all 14 rules lives in this skill's `SKILL.md`.
