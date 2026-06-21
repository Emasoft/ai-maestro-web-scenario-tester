#!/bin/sh
# ──────────────────────────────────────────────────────────────────────────
# init-scenarios-folder.sh — bootstrap a fresh consumer's scenarios folder.
#
# Idempotent: re-running never clobbers a file the user has already filled in
# (config, helpers stub, scenario files). It only CREATES what is missing and
# REFRESHES the engine scripts + the canonical rules doc (which the plugin owns).
#
# What it does in ${CLAUDE_PROJECT_DIR}/<scenariosDir>/ (default tests/scenarios):
#   1. Copy SCENARIOS_TESTS_RULES.md from ${CLAUDE_PLUGIN_ROOT}/references/.
#   2. Seed NEXT_SCEN_NUMBER=1 (only if absent).
#   3. Create state/, reports/scenarios-runner/, state-backups/, fixtures/git/, scripts/.
#   4. Copy (default) or symlink (--link) the shared engine scripts from
#      ${CLAUDE_PLUGIN_ROOT}/scripts/.
#   5. Write a starter scenarios.config.json from the template (only if absent).
#   6. Stub a project helpers script from the template (only if absent).
#   7. Install the write-guard from the template into .claude/scripts/ and
#      print how to wire the project-scoped agent shadow.
#
# Usage:
#   sh init-scenarios-folder.sh                 # copy engine scripts (default)
#   sh init-scenarios-folder.sh --link          # symlink engine scripts instead
#   sh init-scenarios-folder.sh --scenarios-dir tests/e2e   # override scenariosDir
#
# Cross-platform POSIX sh — no bashisms.
# ──────────────────────────────────────────────────────────────────────────

set -eu

# ---- Resolve the plugin root (where this script + bundled content live) ----
# Prefer ${CLAUDE_PLUGIN_ROOT} (set when invoked inside Claude Code). Fall back
# to deriving it from this script's own location so the script also runs by hand.
if [ -n "${CLAUDE_PLUGIN_ROOT:-}" ]; then
    PLUGIN_ROOT="$CLAUDE_PLUGIN_ROOT"
else
    SELF_DIR=$(cd "$(dirname "$0")" && pwd)
    PLUGIN_ROOT=$(cd "$SELF_DIR/.." && pwd)
fi

# ---- Resolve the consumer project root ----
if [ -n "${CLAUDE_PROJECT_DIR:-}" ]; then
    PROJECT_DIR="$CLAUDE_PROJECT_DIR"
else
    PROJECT_DIR=$(pwd)
fi

# ---- Parse args ----
LINK_MODE=0
SCENARIOS_DIR_REL="tests/scenarios"
while [ $# -gt 0 ]; do
    case "$1" in
        --link) LINK_MODE=1; shift ;;
        --scenarios-dir) SCENARIOS_DIR_REL="$2"; shift 2 ;;
        -h|--help)
            sed -n '2,30p' "$0"
            exit 0
            ;;
        *) echo "init-scenarios-folder: unknown arg: $1" >&2; exit 2 ;;
    esac
done

PLUGIN_SCRIPTS="$PLUGIN_ROOT/scripts"
PLUGIN_REFS="$PLUGIN_ROOT/references"
SCEN_DIR="$PROJECT_DIR/$SCENARIOS_DIR_REL"

echo "[init-scenarios] plugin root : $PLUGIN_ROOT"
echo "[init-scenarios] project root: $PROJECT_DIR"
echo "[init-scenarios] scenarios   : $SCEN_DIR"

# Sanity: the bundled content must exist.
if [ ! -d "$PLUGIN_SCRIPTS" ] || [ ! -d "$PLUGIN_REFS" ]; then
    echo "[init-scenarios] ERROR: plugin scripts/ or references/ not found under $PLUGIN_ROOT" >&2
    echo "[init-scenarios]        is CLAUDE_PLUGIN_ROOT set correctly?" >&2
    exit 1
fi

# ---- Step 3 (do dirs first so later steps can write into them) ----
echo "[init-scenarios] creating folders"
for d in \
    "$SCEN_DIR" \
    "$SCEN_DIR/state" \
    "$SCEN_DIR/state-backups" \
    "$SCEN_DIR/fixtures/git" \
    "$SCEN_DIR/scripts" \
    "$SCEN_DIR/scripts/dev-browser-helpers" \
    "$PROJECT_DIR/reports/scenarios-runner" \
    "$PROJECT_DIR/.claude/scripts" \
    "$PROJECT_DIR/.claude/agents" ; do
    if [ ! -d "$d" ]; then
        mkdir -p "$d"
        echo "[init-scenarios]   + $d"
    fi
done

# ---- Step 1: canonical rules doc (always refresh — the plugin owns it) ----
echo "[init-scenarios] installing SCENARIOS_TESTS_RULES.md"
if [ -f "$PLUGIN_REFS/SCENARIOS_TESTS_RULES.md" ]; then
    cp "$PLUGIN_REFS/SCENARIOS_TESTS_RULES.md" "$SCEN_DIR/SCENARIOS_TESTS_RULES.md"
    echo "[init-scenarios]   = $SCEN_DIR/SCENARIOS_TESTS_RULES.md (refreshed)"
else
    echo "[init-scenarios]   WARN: rules doc missing in plugin references/" >&2
fi

# ---- Step 2: NEXT_SCEN_NUMBER (seed only if absent) ----
if [ ! -f "$SCEN_DIR/NEXT_SCEN_NUMBER" ]; then
    printf '1\n' > "$SCEN_DIR/NEXT_SCEN_NUMBER"
    echo "[init-scenarios]   + NEXT_SCEN_NUMBER=1"
else
    echo "[init-scenarios]   = NEXT_SCEN_NUMBER kept ($(cat "$SCEN_DIR/NEXT_SCEN_NUMBER" 2>/dev/null))"
fi

# ---- Step 4: shared engine scripts (copy or symlink; always refresh) ----
echo "[init-scenarios] installing engine scripts ($([ "$LINK_MODE" -eq 1 ] && echo symlink || echo copy))"
for s in \
    scenario-setup.sh \
    scenario-restore.sh \
    state-machine-tick.sh \
    compress-screenshots.sh \
    master-cleanup.sh \
    generate-consolidated-proposals.sh ; do
    src="$PLUGIN_SCRIPTS/$s"
    dst="$SCEN_DIR/scripts/$s"
    if [ ! -f "$src" ]; then
        echo "[init-scenarios]   WARN: engine script missing in plugin: $s" >&2
        continue
    fi
    if [ "$LINK_MODE" -eq 1 ]; then
        ln -sf "$src" "$dst"
    else
        cp "$src" "$dst"
        chmod +x "$dst" 2>/dev/null || true
    fi
    echo "[init-scenarios]   = $s"
done

# ---- Step 5: starter scenarios.config.json (only if absent) ----
CFG="$SCEN_DIR/scenarios.config.json"
if [ ! -f "$CFG" ]; then
    if [ -f "$PLUGIN_REFS/scenarios.config.template.json" ]; then
        cp "$PLUGIN_REFS/scenarios.config.template.json" "$CFG"
        echo "[init-scenarios]   + scenarios.config.json (starter — EDIT IT: see references/scenarios.config.README.md)"
    else
        echo "[init-scenarios]   WARN: config template missing in plugin references/" >&2
    fi
else
    echo "[init-scenarios]   = scenarios.config.json kept (already configured)"
fi

# ---- Step 6: project helpers stub (only if absent) ----
HELPERS_DST="$SCEN_DIR/scripts/dev-browser-helpers/project-helpers.sh"
if [ ! -f "$HELPERS_DST" ]; then
    if [ -f "$PLUGIN_REFS/project-helpers-template.sh" ]; then
        cp "$PLUGIN_REFS/project-helpers-template.sh" "$HELPERS_DST"
        chmod +x "$HELPERS_DST" 2>/dev/null || true
        echo "[init-scenarios]   + dev-browser-helpers/project-helpers.sh (STUB — implement the 3 helpers for your app)"
    else
        echo "[init-scenarios]   WARN: project-helpers template missing in plugin references/" >&2
    fi
else
    echo "[init-scenarios]   = dev-browser-helpers/project-helpers.sh kept"
fi

# ---- Step 7: write-guard into .claude/scripts/ (always refresh the engine) ----
GUARD_SRC="$PLUGIN_SCRIPTS/amwst_subagent-write-guard.sh.template"
GUARD_DST="$PROJECT_DIR/.claude/scripts/subagent-write-guard.sh"
echo "[init-scenarios] installing write-guard"
if [ -f "$GUARD_SRC" ]; then
    cp "$GUARD_SRC" "$GUARD_DST"
    chmod +x "$GUARD_DST" 2>/dev/null || true
    echo "[init-scenarios]   = .claude/scripts/subagent-write-guard.sh"
else
    echo "[init-scenarios]   WARN: write-guard template missing in plugin scripts/" >&2
fi

cat <<'WIRING'

────────────────────────────────────────────────────────────────────────────
NEXT STEPS — wire the write-guard (IRON rule, see references/write-guard-rule.md)
────────────────────────────────────────────────────────────────────────────
Plugin-shipped agents CANNOT carry a `hooks:` field, so you MUST create
PROJECT-SCOPED agent shadows that reference the installed write-guard:

  1. Create .claude/agents/scenario-runner.md and
     .claude/agents/scenario-improvement-implementer.md, each with
     frontmatter:

       ---
       name: scenario-runner
       description: Project shadow of amwst-scenario-runner with the write-guard hook.
       isolation: worktree
       hooks:
         PreToolUse:
           - matcher: "Write|Edit|MultiEdit|NotebookEdit|Bash"
             hooks:
               - type: command
                 command: "${CLAUDE_PROJECT_DIR}/.claude/scripts/subagent-write-guard.sh"
       ---
       (body: "Follow the bundled amwst-scenario-runner behavior.")

  2. Spawn these subagents by BARE name (scenario-runner) — never the
     plugin-namespaced name, or the hook will NOT fire.

THEN configure your project:
  3. Edit tests/scenarios/scenarios.config.json
     (doc: references/scenarios.config.README.md).
  4. Implement the 3 helpers in
     tests/scenarios/scripts/dev-browser-helpers/project-helpers.sh
     and point `helpersScript` in the config at it.
  5. Author your first scenario with the create-scenario skill.
────────────────────────────────────────────────────────────────────────────
WIRING

echo "[init-scenarios] done"
