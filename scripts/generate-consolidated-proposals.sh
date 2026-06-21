#!/usr/bin/env bash
# generate-consolidated-proposals.sh — produce the user-facing batch summary.
#
# Reads tests/scenarios/state/autonomous-batch-state.json + every
# scenario_proposed-improvements_*.md report referenced from it, then writes
# reports/scenarios-runner/CONSOLIDATED_PROPOSALS_<batch_id>.md per the
# Rule 13 format: phase-1 summary table, then approval-checklist sections
# for P0/P1/P2/P3 proposals across the entire batch.
#
# Idempotent: rewriting the file with the same input produces the same output.
# Operates only on text files — no API calls, no git mutations.
#
# Usage:
#   bash tests/scenarios/scripts/generate-consolidated-proposals.sh
#   bash tests/scenarios/scripts/generate-consolidated-proposals.sh --out path.md
#   bash tests/scenarios/scripts/generate-consolidated-proposals.sh --quiet

set -euo pipefail

if MAIN_ROOT="$(git rev-parse --git-common-dir 2>/dev/null)"; then
  MAIN_ROOT="$(cd "$(dirname "$MAIN_ROOT")" && pwd)"
else
  MAIN_ROOT="${CLAUDE_PROJECT_DIR:-$(pwd)}"
fi

STATE_FILE="$MAIN_ROOT/tests/scenarios/state/autonomous-batch-state.json"
REPORTS_DIR="$MAIN_ROOT/reports/scenarios-runner"
OUT=""
QUIET=0

while [ $# -gt 0 ]; do
  case "$1" in
    --out)   OUT="$2"; shift 2 ;;
    --quiet) QUIET=1; shift ;;
    *) echo "ERROR unknown-arg-$1" >&2; exit 2 ;;
  esac
done

[ -f "$STATE_FILE" ] || { echo "ERROR state-file-missing: $STATE_FILE" >&2; exit 2; }

# Default output path embeds batch_id from state file
if [ -z "$OUT" ]; then
  BATCH_ID="$(python3 -c "import json,sys; print(json.load(open(sys.argv[1])).get('batch_id','unknown'))" "$STATE_FILE")"
  OUT="$REPORTS_DIR/CONSOLIDATED_PROPOSALS_${BATCH_ID}.md"
fi

mkdir -p "$(dirname "$OUT")"

python3 - "$STATE_FILE" "$REPORTS_DIR" "$OUT" "$QUIET" <<'PYEOF'
import json
import os
import re
import sys
from pathlib import Path

state_file, reports_dir, out_path, quiet_s = sys.argv[1:]
quiet = quiet_s == "1"

with open(state_file) as f:
    state = json.load(f)

batch_id = state.get("batch_id", "unknown")
started_at = state.get("started_at", "")
base_branch = state.get("base_branch", "")
scenario_list = state.get("scenario_list", [])
scenarios = state.get("scenarios", {})

# ---- Aggregate counts ----
done = [s for s in scenario_list if scenarios.get(s, {}).get("status") == "done"]
pending = [s for s in scenario_list if scenarios.get(s, {}).get("status") in ("pending", "in_progress")]
verdicts = {"PASS": 0, "FAIL": 0, "PARTIAL": 0, "STUCK": 0}
total_bugs_fixed = 0
all_fix_shas = []

for s in done:
    e = scenarios[s]
    v = (e.get("verdict") or "").upper()
    if v in verdicts:
        verdicts[v] += 1
    total_bugs_fixed += e.get("bugs_fixed", 0)
    all_fix_shas.extend(e.get("bug_fix_commit_shas", []))

p0_total = sum(scenarios.get(s, {}).get("p0_proposals_count", 0) for s in done)
p1_total = sum(scenarios.get(s, {}).get("p1_proposals_count", 0) for s in done)
p2_total = sum(scenarios.get(s, {}).get("p2_proposals_count", 0) for s in done)
p3_total = sum(scenarios.get(s, {}).get("p3_proposals_count", 0) for s in done)

# ---- Per-priority extraction from each improvements .md ----
# Each scenario's improvements file has a structure with P0/P1/P2/P3 sections.
# We extract proposal blocks and re-emit them grouped by priority.

PRIORITY_HEADER = re.compile(r"^#+\s*(P0|P1|P2|P3)\b", re.MULTILINE)

def extract_proposals(md_path: Path, scen_id: str):
    """Return dict {P0: [(title, body), ...], P1: [...], ...}."""
    out = {"P0": [], "P1": [], "P2": [], "P3": []}
    if not md_path.exists():
        return out
    text = md_path.read_text()
    # Find priority section boundaries
    matches = list(PRIORITY_HEADER.finditer(text))
    if not matches:
        return out
    matches.append(None)  # sentinel for end
    for i in range(len(matches) - 1):
        m = matches[i]
        next_m = matches[i + 1]
        priority = m.group(1)
        section_start = m.end()
        section_end = next_m.start() if next_m else len(text)
        section = text[section_start:section_end].strip()
        # Split into proposals by H4 (####) headers
        prop_headers = list(re.finditer(r"^####\s+(.+)$", section, re.MULTILINE))
        if not prop_headers:
            continue
        prop_headers.append(None)
        for j in range(len(prop_headers) - 1):
            h = prop_headers[j]
            nh = prop_headers[j + 1]
            title = h.group(1).strip()
            body_start = h.end()
            body_end = nh.start() if nh else len(section)
            body = section[body_start:body_end].strip()
            out[priority].append({"scen": scen_id, "title": title, "body": body})
    return out

all_props = {"P0": [], "P1": [], "P2": [], "P3": []}
for s in done:
    imp_path = scenarios[s].get("improvements_path", "")
    if imp_path:
        path = Path(imp_path)
        if not path.is_absolute():
            path = Path(reports_dir) / path.name
        proposals = extract_proposals(path, s)
        for k, lst in proposals.items():
            all_props[k].extend(lst)

# ---- Build the markdown output ----
lines = []
lines.append(f"# Autonomous Batch {batch_id} — Consolidated Proposals")
lines.append("")
lines.append(f"**Started:** {started_at}")
lines.append(f"**Base branch:** {base_branch}")
lines.append(f"**Total scenarios in batch:** {len(scenario_list)}")
lines.append(f"**Done:** {len(done)} (PASS: {verdicts['PASS']}, PARTIAL: {verdicts['PARTIAL']}, FAIL: {verdicts['FAIL']}, STUCK: {verdicts['STUCK']})")
lines.append(f"**Pending/Stalled:** {len(pending)}")
lines.append(f"**Bugs fixed in place (Phase 1):** {total_bugs_fixed} across {len(all_fix_shas)} commits")
lines.append(f"**Proposals pending approval:** {p0_total} P0, {p1_total} P1, {p2_total} P2, {p3_total} P3")
lines.append("")
lines.append("---")
lines.append("")

# Phase 1 summary
lines.append("## Phase 1 summary — bug fixes already committed")
lines.append("")
lines.append("These fixes were applied in-place to the base branch during the run, per Rule 4 FIX-AS-YOU-GO. No action required from you on these — they are the baseline.")
lines.append("")
lines.append("| # | Scenario | Verdict | Bugs fixed | Fix commit SHAs | Report |")
lines.append("|---|----------|---------|-----------|-----------------|--------|")
for i, s in enumerate(done, 1):
    e = scenarios[s]
    v = e.get("verdict", "?")
    bf = e.get("bugs_fixed", 0)
    shas = ", ".join(e.get("bug_fix_commit_shas", [])) or "—"
    rp = e.get("report_path", "")
    rp_short = Path(rp).name if rp else "—"
    lines.append(f"| {i} | {s} | {v} | {bf} | `{shas}` | [{rp_short}]({rp}) |")
lines.append("")

# Pending/stuck table
if pending:
    lines.append("## Pending / stalled scenarios")
    lines.append("")
    lines.append("| Scenario | Status | Started | Last stuck reason | Retries |")
    lines.append("|----------|--------|---------|-------------------|---------|")
    for s in pending:
        e = scenarios[s]
        lines.append(f"| {s} | {e.get('status','?')} | {e.get('started_at') or '—'} | {e.get('last_stuck_reason') or '—'} | {e.get('retries', 0)} |")
    lines.append("")

# Phase 2 — approval section
lines.append("## Phase 2 — your turn: approve proposals for Phase 3 implementation")
lines.append("")
lines.append("Below is every P0/P1/P2/P3 proposal from every scenario in this batch.")
lines.append("**To approve, mark the checkbox `[x]`** next to it. Save this file when done.")
lines.append("")
lines.append("Phase 3 implementation runs only on approved items via `/run-scenarios-batch --improve <batch-id>`.")
lines.append("")

for prio in ("P0", "P1", "P2", "P3"):
    lst = all_props[prio]
    lines.append(f"### {prio} proposals ({len(lst)})")
    lines.append("")
    if not lst:
        lines.append("_(none)_")
        lines.append("")
        continue
    for i, p in enumerate(lst, 1):
        lines.append(f"#### {p['scen']} — {p['title']}")
        lines.append("- [ ] **Approve**")
        lines.append("")
        lines.append(p["body"])
        lines.append("")

# Footer
lines.append("---")
lines.append("")
lines.append("## Phase 3 — implement approved proposals")
lines.append("")
lines.append("After checking approval boxes above, run:")
lines.append("")
lines.append("```bash")
lines.append(f"/run-scenarios-batch --improve {batch_id}")
lines.append("```")
lines.append("")
lines.append("Each approved proposal is implemented in its own isolated git worktree by `scenario-improvement-implementer`. Worktree branches return as draft PRs for your review/merge — never auto-merged.")

with open(out_path, "w") as f:
    f.write("\n".join(lines))
    f.write("\n")

if not quiet:
    print(f"Wrote {out_path}")
    print(f"  done: {len(done)} | pending: {len(pending)}")
    print(f"  P0/P1/P2/P3: {p0_total}/{p1_total}/{p2_total}/{p3_total}")
PYEOF
