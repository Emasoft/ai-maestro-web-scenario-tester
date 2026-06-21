#!/usr/bin/env bash
# master-cleanup.sh — final phase of an autonomous scenario batch.
#
# Per Rule 13, this runs ONCE at the end of a batch:
#   1. Stop the shared dev-browser daemon.
#   2. (OPTIONAL) Kill leftover test tmux sessions matching a project
#      pattern — only if scenarios.config.json sets "cleanupTmuxPattern".
#      The per-scenario cleanup-SCEN-NNN.sh should have handled these, but
#      this is the belt-and-braces sweep. Skipped entirely when no pattern
#      is configured (a generic consumer with no tmux test sessions).
#   3. (OPTIONAL) Registry sanity check — only if scenarios.config.json sets
#      "registryScanPath" + "testAgentPattern". Logs any test artifact that
#      escaped per-scenario cleanup so the operator can act manually.
#      Skipped when not configured.
#   4. Generate the user-facing CONSOLIDATED_PROPOSALS file via the
#      bundled generate-consolidated-proposals.sh script.
#   5. Set state.phase = "consolidated".
#
# The caller (cron prompt OR hand-driven orchestrator) is responsible for
# committing the consolidated file. This script does NOT touch git.
#
# Steps 2 and 3 are deliberately config-gated so this script is reusable
# in any consuming project: the generic core (stop browser → consolidate
# → advance phase) always runs; the project-specific teardown only runs
# when the consumer opts in via scenarios.config.json.
#
# Usage:
#   bash master-cleanup.sh
#   bash master-cleanup.sh --dry-run

set -euo pipefail

if MAIN_ROOT="$(git rev-parse --git-common-dir 2>/dev/null)"; then
  MAIN_ROOT="$(cd "$(dirname "$MAIN_ROOT")" && pwd)"
else
  MAIN_ROOT="${CLAUDE_PROJECT_DIR:-$(pwd)}"
fi

SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
SCENARIOS_SUBDIR="${SCENARIOS_DIR_REL:-tests/scenarios}"
STATE_FILE="$MAIN_ROOT/$SCENARIOS_SUBDIR/state/autonomous-batch-state.json"
CONFIG_FILE="$MAIN_ROOT/$SCENARIOS_SUBDIR/scenarios.config.json"
DRY_RUN=0
LOG_PREFIX="[master-cleanup]"

while [ $# -gt 0 ]; do
  case "$1" in
    --dry-run) DRY_RUN=1; shift ;;
    *) echo "ERROR unknown-arg-$1" >&2; exit 2 ;;
  esac
done

[ -f "$STATE_FILE" ] || { echo "$LOG_PREFIX state-file-missing"; exit 2; }

# Read an optional string key out of scenarios.config.json (python3, no jq).
config_get() {
  local key="$1"
  [ -f "$CONFIG_FILE" ] || { printf ''; return 0; }
  python3 - "$CONFIG_FILE" "$key" <<'PYEOF'
import json, sys
try:
    with open(sys.argv[1]) as f:
        cfg = json.load(f)
    v = cfg.get(sys.argv[2], "")
    print(v if isinstance(v, str) else "")
except Exception:
    print("")
PYEOF
}

# Step 0: delete the write-guard run sentinel (belt-and-braces).
# The run owner deletes it at run end, but a crashed/killed run can leave it
# behind — which would keep the plugin's sentinel-gated write-guard ARMED for
# every later (non-scenario) session in this project. Remove it unconditionally
# here so master-cleanup always disarms the guard. Idempotent: `rm -f` no-ops
# when the file is absent.
SENTINEL="$MAIN_ROOT/.claude/scenario_is_running.json"
echo "$LOG_PREFIX step 0: clear write-guard run sentinel"
if [ -f "$SENTINEL" ]; then
  if [ "$DRY_RUN" -eq 0 ]; then
    rm -f "$SENTINEL"
    echo "$LOG_PREFIX   removed $SENTINEL"
  else
    echo "$LOG_PREFIX   would remove $SENTINEL"
  fi
else
  echo "$LOG_PREFIX   none — guard already disarmed"
fi

# Step 1: stop dev-browser
echo "$LOG_PREFIX step 1: stop dev-browser daemon"
if [ "$DRY_RUN" -eq 0 ]; then
  if command -v dev-browser >/dev/null 2>&1; then
    dev-browser stop 2>&1 | sed "s/^/$LOG_PREFIX   /" || true
  else
    echo "$LOG_PREFIX   dev-browser not on PATH (skipping)"
  fi
fi

# Step 2: (OPTIONAL) kill leftover test tmux sessions matching the configured pattern
CLEANUP_TMUX_PATTERN="$(config_get cleanupTmuxPattern)"
echo "$LOG_PREFIX step 2: kill leftover test tmux sessions"
if [ -z "$CLEANUP_TMUX_PATTERN" ]; then
  echo "$LOG_PREFIX   no cleanupTmuxPattern configured — skipping"
elif ! command -v tmux >/dev/null 2>&1; then
  echo "$LOG_PREFIX   tmux not on PATH — skipping"
else
  LEFTOVERS="$(tmux list-sessions -F '#S' 2>/dev/null | grep -E "$CLEANUP_TMUX_PATTERN" || true)"
  if [ -n "$LEFTOVERS" ]; then
    while IFS= read -r SESSION; do
      [ -z "$SESSION" ] && continue
      echo "$LOG_PREFIX   kill: $SESSION"
      if [ "$DRY_RUN" -eq 0 ]; then
        tmux kill-session -t "$SESSION" 2>&1 | sed "s/^/$LOG_PREFIX     /" || true
      fi
    done <<<"$LEFTOVERS"
  else
    echo "$LOG_PREFIX   none — clean"
  fi
fi

# Step 3: (OPTIONAL) registry sanity check (read-only)
REG="$(config_get registryScanPath)"
TEST_AGENT_PATTERN="$(config_get testAgentPattern)"
echo "$LOG_PREFIX step 3: scan registry for leftover test artifacts"
if [ -z "$REG" ] || [ -z "$TEST_AGENT_PATTERN" ]; then
  echo "$LOG_PREFIX   no registryScanPath/testAgentPattern configured — skipping"
else
  # Expand a leading ~ in the configured path.
  # shellcheck disable=SC2088  # "~/" is a literal case-pattern match here, not an expansion
  case "$REG" in
    "~/"*) REG="$HOME/${REG#~/}" ;;
    "~") REG="$HOME" ;;
  esac
  if [ -f "$REG" ]; then
    python3 - "$REG" "$TEST_AGENT_PATTERN" "$LOG_PREFIX" <<'PYEOF'
import json, sys, re
reg_path, pattern, log_prefix = sys.argv[1:]
with open(reg_path) as f:
    reg = json.load(f)
agents = reg.get("agents", []) if isinstance(reg, dict) else reg
TEST_PATTERN = re.compile(pattern, re.IGNORECASE)
leftover = [a for a in agents if isinstance(a, dict) and TEST_PATTERN.match(a.get("name") or "")]
if leftover:
    for a in leftover:
        print(f"{log_prefix}   LINGERING_TEST_AGENT name={a.get('name')} id={a.get('id')} workdir={a.get('workingDirectory')}")
else:
    print(f"{log_prefix}   no lingering test agents")
PYEOF
  else
    echo "$LOG_PREFIX   registry file not found at $REG (skipping)"
  fi
fi

# Step 4: generate consolidated proposals
echo "$LOG_PREFIX step 4: generate consolidated proposals"
if [ "$DRY_RUN" -eq 0 ]; then
  bash "$SCRIPT_DIR/generate-consolidated-proposals.sh" 2>&1 | sed "s/^/$LOG_PREFIX   /" || {
    echo "$LOG_PREFIX   ERROR generate-consolidated-proposals failed"
    exit 1
  }
fi

# Step 5: phase = consolidated
echo "$LOG_PREFIX step 5: advance state phase to consolidated"
if [ "$DRY_RUN" -eq 0 ]; then
  python3 - "$STATE_FILE" <<'PYEOF'
import json, os, sys, datetime
sf = sys.argv[1]
with open(sf) as f:
    s = json.load(f)
s["phase"] = "consolidated"
s["completed_at"] = datetime.datetime.utcnow().strftime("%Y-%m-%dT%H:%M:%SZ")
tmp = sf + ".tmp"
with open(tmp, "w") as f:
    json.dump(s, f, indent=2)
    f.write("\n")
os.replace(tmp, sf)
PYEOF
fi

echo "$LOG_PREFIX done"
