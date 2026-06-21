#!/usr/bin/env bash
# Shared scenario restore — invoked by per-scenario wrapper cleanup-SCEN-<NNN>.sh.
# Finds the most recent state-backups/SCEN-<NNN>_<timestamp>/ directory, verifies
# every backed-up file's SHA256, restores each to its original path, and verifies
# the restored copy matches the backup.
#
# Exits 0 on full restore. Exits 1 with RESTORE_FAIL <reason> on any failure.
# The backup directory is retained after restore (audit trail); the janitor
# migrates it to reports_dev/ after 48h.

set -euo pipefail

NNN="${1:?usage: scenario-restore.sh <NNN>}"
PROJECT_DIR="${CLAUDE_PROJECT_DIR:-$(cd "$(dirname "$0")/../../.." && pwd)}"

BACKUP_ROOT="$PROJECT_DIR/tests/scenarios/state-backups"
BACKUP_DIR=$(ls -dt "$BACKUP_ROOT/SCEN-${NNN}_"* 2>/dev/null | head -1)
if [ -z "${BACKUP_DIR:-}" ]; then
  echo "RESTORE_FAIL no backup directory found for SCEN-$NNN under $BACKUP_ROOT" >&2
  exit 1
fi

MANIFEST="$BACKUP_DIR/MANIFEST.sha256"
if [ ! -f "$MANIFEST" ]; then
  echo "RESTORE_FAIL missing MANIFEST.sha256 in $BACKUP_DIR" >&2
  exit 1
fi

echo "RESTORE_BEGIN SCEN-$NNN backup=$BACKUP_DIR"

restored=0
failed=0
while IFS= read -r line; do
  [ -z "$line" ] && continue
  sha=$(awk '{print $1}' <<< "$line")
  orig=$(awk '{print $2}' <<< "$line")
  rel=$(awk '{print $3}' <<< "$line")
  src="$BACKUP_DIR/$rel"
  if [ ! -f "$src" ]; then
    echo "RESTORE_MISS $orig (backup file missing at $src)" >&2
    failed=$((failed+1))
    continue
  fi
  backup_sha=$(shasum -a 256 "$src" | awk '{print $1}')
  if [ "$backup_sha" != "$sha" ]; then
    echo "RESTORE_FAIL backup corrupt for $orig (expected $sha, got $backup_sha)" >&2
    failed=$((failed+1))
    continue
  fi
  mkdir -p "$(dirname "$orig")"
  cp -p "$src" "$orig"
  restored_sha=$(shasum -a 256 "$orig" | awk '{print $1}')
  if [ "$restored_sha" != "$sha" ]; then
    echo "RESTORE_FAIL post-copy sha mismatch for $orig" >&2
    failed=$((failed+1))
    continue
  fi
  echo "RESTORE $orig"
  restored=$((restored+1))
done < "$MANIFEST"

if [ "$failed" -gt 0 ]; then
  echo "RESTORE_FAIL $failed file(s) failed" >&2
  exit 1
fi

echo "RESTORE_OK SCEN-$NNN ($restored files restored)"
echo "BACKUP_DIR_RETAINED=$BACKUP_DIR"
