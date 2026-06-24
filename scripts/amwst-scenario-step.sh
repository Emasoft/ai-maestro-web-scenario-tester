#!/usr/bin/env bash
# amwst-scenario-step.sh — read ONE step (or list step ids / phases) from a .scen.md
# so the scenario runner greps just the step it is executing, never re-reading the
# whole scenario every turn (token economy — TRDD-74ZS7P9U req 4 / technique 4).
#
# Usage:
#   amwst-scenario-step.sh <file.scen.md> list          # every step: "<line>  S<NNN>: <title>"
#   amwst-scenario-step.sh <file.scen.md> phases        # every phase header: "<line>  Phase …"
#   amwst-scenario-step.sh <file.scen.md> S007          # just the S007 block
#
# A step block runs from its `#### S<NNN>` header up to (but not including) the next
# `####` step header or `##` phase header. The selector is matched case-insensitively.
set -euo pipefail

die() { printf '%s\n' "$*" >&2; exit 2; }

[ $# -ge 2 ] || die "usage: amwst-scenario-step.sh <file.scen.md> list|phases|S<NNN>"
FILE=$1; SEL=$2
[ -f "$FILE" ] || die "not a file: $FILE"

case "$SEL" in
  list)
    grep -nE '^#### S[0-9]+' "$FILE" | sed -E 's/^([0-9]+):#### /\1  /' \
      || die "no steps (no '#### S<NNN>' headers) in $FILE"
    ;;
  phases)
    grep -nE '^## ' "$FILE" | sed -E 's/^([0-9]+):## /\1  /' \
      || die "no phases (no '## ' headers) in $FILE"
    ;;
  [Ss][0-9]*)
    want=$(printf '%s' "$SEL" | tr '[:lower:]' '[:upper:]')
    # A '#### S<NNN>' line opens the block (printing on iff its id == want); the next
    # '####' step or '## ' phase header closes it. '## ' never matches a '####' line
    # (4th char is '#', not space), so step headers don't false-close their own block.
    out=$(awk -v want="$want" '
      /^#### S[0-9]+/ { hdr=$0; sub(/^#### /, "", hdr); split(hdr, a, /[: ]/); printing = (toupper(a[1]) == want) }
      /^## /          { printing = 0 }
      printing        { print }
    ' "$FILE")
    [ -n "$out" ] || die "step $want not found in $FILE"
    printf '%s\n' "$out"
    ;;
  *)
    die "unknown selector: $SEL (use list | phases | S<NNN>)"
    ;;
esac
