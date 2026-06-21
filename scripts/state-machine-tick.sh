#!/usr/bin/env bash
# state-machine-tick.sh — single source of truth for the autonomous batch state machine.
#
# Reads tests/scenarios/state/autonomous-batch-state.json, applies one tick of the
# state machine, and prints what to do next on stdout. Idempotent — safe to call
# many times in a row, or from a cron, or from the run-scenarios-batch skill.
#
# Output format (one line on stdout):
#   RUN <SCEN-NNN>          — dispatch this scenario via the scenario-runner agent
#   CLEANUP                 — phase=master_cleanup, run consolidated proposals
#   DONE                    — phase=consolidated, nothing to do
#   WAIT <SCEN-NNN>         — that scenario's heartbeat is fresh, leave it alone
#   ERROR <reason>          — state file unreadable / corrupt / something is wrong
#
# Side effects (idempotent):
#   - If an in_progress scenario's heartbeat is stale (>STALE_THRESHOLD_MIN old, or
#     no heartbeat file exists and started_at is >STALE_THRESHOLD_MIN ago), the
#     scenario is reset to pending so the next caller can dispatch it fresh.
#   - The recovery event is logged to state/recovery.log with timestamp + reason.
#
# Usage:
#   bash tests/scenarios/scripts/state-machine-tick.sh
#   bash tests/scenarios/scripts/state-machine-tick.sh --dry-run        # no mutations
#   bash tests/scenarios/scripts/state-machine-tick.sh --stale-min 90   # override threshold

set -euo pipefail

# ---- Resolve project root (worktree-safe) ----
if MAIN_ROOT="$(git rev-parse --git-common-dir 2>/dev/null)"; then
  MAIN_ROOT="$(cd "$(dirname "$MAIN_ROOT")" && pwd)"
else
  MAIN_ROOT="${CLAUDE_PROJECT_DIR:-$(pwd)}"
fi

STATE_DIR="$MAIN_ROOT/tests/scenarios/state"
STATE_FILE="$STATE_DIR/autonomous-batch-state.json"
RECOVERY_LOG="$STATE_DIR/recovery.log"
STALE_THRESHOLD_MIN=90
DRY_RUN=0

while [ $# -gt 0 ]; do
  case "$1" in
    --stale-min) STALE_THRESHOLD_MIN="$2"; shift 2 ;;
    --dry-run)   DRY_RUN=1; shift ;;
    *) echo "ERROR unknown-arg-$1" ; exit 2 ;;
  esac
done

if [ ! -f "$STATE_FILE" ]; then
  echo "ERROR state-file-missing"
  exit 2
fi

# ---- Helper: write recovery log entry ----
log_recovery() {
  local msg="$1"
  printf '%s %s\n' "$(date -u +%Y-%m-%dT%H:%M:%SZ)" "$msg" >> "$RECOVERY_LOG"
}

# ---- Step 1: validate JSON and read phase ----
if ! python3 -c "import json,sys; json.load(open(sys.argv[1]))" "$STATE_FILE" 2>/dev/null; then
  echo "ERROR state-file-corrupt"
  exit 2
fi

PHASE="$(python3 -c "import json,sys; print(json.load(open(sys.argv[1])).get('phase',''))" "$STATE_FILE")"

case "$PHASE" in
  consolidated|failed)
    echo "DONE"
    exit 0
    ;;
  master_cleanup)
    echo "CLEANUP"
    exit 0
    ;;
  master_setup|running) ;;
  *)
    echo "ERROR unknown-phase-$PHASE"
    exit 2
    ;;
esac

# ---- Step 2: detect stale in_progress and reset to pending ----
NOW_EPOCH="$(date -u +%s)"
STALE_THRESHOLD_SEC=$((STALE_THRESHOLD_MIN * 60))

# Use python to avoid jq dependency. Read state, detect stale, optionally rewrite.
python3 - "$STATE_FILE" "$STATE_DIR" "$NOW_EPOCH" "$STALE_THRESHOLD_SEC" "$DRY_RUN" "$RECOVERY_LOG" <<'PYEOF'
import json, os, sys, time, datetime

state_file, state_dir, now_epoch_s, stale_threshold_s, dry_run_s, recovery_log = sys.argv[1:]
now_epoch = int(now_epoch_s)
stale_threshold = int(stale_threshold_s)
dry_run = dry_run_s == "1"

with open(state_file, "r") as f:
    state = json.load(f)

mutated = False
recovery_entries = []

def parse_iso(ts):
    if not ts:
        return None
    # Accept either Z or +HHMM offset
    try:
        s = ts.replace("Z", "+00:00")
        return datetime.datetime.fromisoformat(s).timestamp()
    except Exception:
        return None

for scen_id, entry in state.get("scenarios", {}).items():
    if entry.get("status") != "in_progress":
        continue

    # Try heartbeat file first (most authoritative)
    hb_path = os.path.join(state_dir, f"runner-heartbeat-{scen_id}.txt")
    hb_age = None
    if os.path.exists(hb_path):
        try:
            with open(hb_path, "r") as f:
                first_line = f.readline().strip()
            # Format: "epoch=1777950000" or just an integer
            if first_line.startswith("epoch="):
                hb_epoch = int(first_line.split("=", 1)[1])
            else:
                hb_epoch = int(first_line)
            hb_age = now_epoch - hb_epoch
        except Exception:
            hb_age = None

    # Fall back to started_at
    started_age = None
    started_ts = parse_iso(entry.get("started_at"))
    if started_ts is not None:
        started_age = now_epoch - int(started_ts)

    # Decide staleness
    is_stale = False
    reason = ""
    if hb_age is not None:
        if hb_age > stale_threshold:
            is_stale = True
            reason = f"heartbeat {hb_age}s old (>{stale_threshold}s threshold)"
    elif started_age is not None:
        if started_age > stale_threshold:
            is_stale = True
            reason = f"no heartbeat, started {started_age}s ago (>{stale_threshold}s threshold)"
    else:
        is_stale = True
        reason = "no heartbeat and no started_at"

    if is_stale:
        if not dry_run:
            entry["status"] = "pending"
            entry["started_at"] = None
            # Bump retry counter for visibility
            entry["retries"] = entry.get("retries", 0) + 1
            entry["last_stuck_at"] = datetime.datetime.utcnow().strftime("%Y-%m-%dT%H:%M:%SZ")
            entry["last_stuck_reason"] = reason
            # Remove the stale heartbeat file
            try:
                if os.path.exists(hb_path):
                    os.remove(hb_path)
            except Exception:
                pass
            mutated = True
        recovery_entries.append((scen_id, reason))

# Atomic write
if mutated and not dry_run:
    tmp = state_file + ".tmp"
    with open(tmp, "w") as f:
        json.dump(state, f, indent=2)
        f.write("\n")
    os.replace(tmp, state_file)

# Append recovery log
if recovery_entries and not dry_run:
    with open(recovery_log, "a") as f:
        ts = datetime.datetime.utcnow().strftime("%Y-%m-%dT%H:%M:%SZ")
        for scen_id, reason in recovery_entries:
            f.write(f"{ts} STALE_RESET {scen_id} {reason}\n")

# Print recovery summary to stderr (so stdout stays clean for caller)
for scen_id, reason in recovery_entries:
    print(f"recovered: {scen_id} ({reason})", file=sys.stderr)
PYEOF

# ---- Step 3: determine next action ----
NEXT="$(python3 - "$STATE_FILE" <<'PYEOF'
import json, sys
with open(sys.argv[1]) as f:
    state = json.load(f)
scenarios = state.get("scenarios", {})
order = state.get("scenario_list", list(scenarios.keys()))

# Already in_progress (fresh heartbeat) → WAIT
for scen_id in order:
    e = scenarios.get(scen_id, {})
    if e.get("status") == "in_progress":
        print(f"WAIT {scen_id}")
        sys.exit(0)

# Otherwise, find first pending
for scen_id in order:
    e = scenarios.get(scen_id, {})
    if e.get("status") == "pending":
        print(f"RUN {scen_id}")
        sys.exit(0)

# Nothing pending and nothing running — time for cleanup
print("CLEANUP")
PYEOF
)"

# ---- Step 4: if we returned CLEANUP, advance phase=running → master_cleanup ----
if [ "$NEXT" = "CLEANUP" ] && [ "$PHASE" = "running" ] && [ "$DRY_RUN" -eq 0 ]; then
  python3 - "$STATE_FILE" <<'PYEOF'
import json, sys, os
with open(sys.argv[1]) as f:
    state = json.load(f)
state["phase"] = "master_cleanup"
tmp = sys.argv[1] + ".tmp"
with open(tmp, "w") as f:
    json.dump(state, f, indent=2)
    f.write("\n")
os.replace(tmp, sys.argv[1])
PYEOF
  log_recovery "PHASE_ADVANCE running -> master_cleanup"
fi

echo "$NEXT"
