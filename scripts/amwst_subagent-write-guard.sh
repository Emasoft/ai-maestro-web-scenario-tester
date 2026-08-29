#!/usr/bin/env bash
# ────────────────────────────────────────────────────────────────────
# amwst_subagent-write-guard.sh — ACTIVE plugin write-guard (PreToolUse)
#
# Wired by THIS plugin's hooks/hooks.json as a PreToolUse hook (matcher
# Write|Edit|MultiEdit|NotebookEdit|Bash). Plugin hooks are plugin-SCOPED:
# they load for every session that has the plugin enabled — which would be
# far too broad for a write-guard. The SENTINEL GATE below makes that safe.
#
# SENTINEL GATE
#   The hook is INERT unless a scenario run is active. The run owner
#   (amwst-run-scenario / amwst-run-scenarios-batch / the main agent) writes
#       ${CLAUDE_PROJECT_DIR}/.claude/scenario_is_running.json
#   when it STARTS a run and DELETES it when the run COMPLETES. With no
#   sentinel the hook exits 0 immediately and does nothing — so normal
#   (non-scenario) work in any project with this plugin enabled is untouched.
#   (The sentinel file is gitignored; the tester adds it to .gitignore.)
#
# PURPOSE (only while a run is active)
#   Scenario subagents may only WRITE to:
#     1. $CLAUDE_PROJECT_DIR — the project root (runner) or the subagent's
#        git worktree (implementer, via isolation: worktree)
#     2. System scratch — /tmp, /private/tmp, /var/folders/*, /private/var/folders/*
#     3. Any extra roots listed in scenarios.config.json "writeGuardAllowlist"
#   Reads are NOT restricted — subagents may read from anywhere.
#
# WHY
#   `isolation: worktree` gives FILESYSTEM isolation (a separate checkout)
#   but NOT process sandboxing — a subagent with Bash/Write/Edit can `cd ../..`
#   into the parent repo and corrupt it. This hook closes that gap by
#   validating every Write/Edit/MultiEdit/NotebookEdit target AND catching the
#   common Bash escape patterns (cd to an outside absolute path, git -C, file
#   redirection, rm/mv/cp/mkdir/touch/tee/chmod/chown/dd/install/ln/sed -i).
#
# EXIT CODES
#   0 — allow the tool call (also: no active scenario run → inert)
#   2 — block the tool call (stderr becomes the reason shown to Claude)
#
# DEPENDENCIES
#   python3 (cross-platform JSON parsing — no jq dependency)
#   realpath (optional — falls back to raw path matching when absent)
# ────────────────────────────────────────────────────────────────────

set -euo pipefail

# ── SENTINEL GATE — do nothing unless a scenario run is active ──
# Checked FIRST (before reading stdin) so the overwhelming common case — any
# tool call when no scenario is running — costs almost nothing.
SENTINEL="${CLAUDE_PROJECT_DIR:-}/.claude/scenario_is_running.json"
if [ -z "${CLAUDE_PROJECT_DIR:-}" ] || [ ! -f "$SENTINEL" ]; then
	exit 0
fi

# Read hook JSON from stdin and pull fields via python3 — portable, no jq.
# The JSON is passed to python3 through an env var (HOOK_JSON) rather than
# interpolated into the heredoc, so quotes/backslashes in the command string
# can never break the parser.
INPUT=$(cat)

json_field() {
	# json_field <dotted.path>   e.g. json_field tool_input.file_path
	HOOK_JSON="$INPUT" python3 - "$1" <<'PYEOF'
import json, os, sys
path = sys.argv[1].split(".")
try:
    obj = json.loads(os.environ.get("HOOK_JSON", ""))
except Exception:
    print("")
    sys.exit(0)
cur = obj
for key in path:
    if isinstance(cur, dict) and key in cur:
        cur = cur[key]
    else:
        cur = ""
        break
print(cur if isinstance(cur, str) else "")
PYEOF
}

TOOL_NAME=$(json_field tool_name)
# The caller's working directory, from the hook payload. Needed because a RELATIVE
# path in a Bash command means "relative to the caller's cwd" — resolving it against
# this process's cwd (what `realpath -m` does by default) would check the wrong path.
# Empty when absent: resolve_against_cwd then refuses to resolve, and the caller blocks.
HOOK_CWD=$(json_field cwd)

# Resolve the project root (CLAUDE_PROJECT_DIR points at the agent's working
# tree — main tree for runner, worktree dir for implementer).
PROJECT_ROOT="${CLAUDE_PROJECT_DIR:-}"
if [ -z "$PROJECT_ROOT" ]; then
	echo "[write-guard] WARN: CLAUDE_PROJECT_DIR not set, allowing tool call" >&2
	exit 0
fi

if command -v realpath >/dev/null 2>&1; then
	PROJECT_ROOT_ABS=$(realpath "$PROJECT_ROOT" 2>/dev/null || echo "$PROJECT_ROOT")
else
	PROJECT_ROOT_ABS=$(cd "$PROJECT_ROOT" 2>/dev/null && pwd -P || echo "$PROJECT_ROOT")
fi

# ── EXTRA ALLOWLIST from scenarios.config.json "writeGuardAllowlist" ──
SCENARIOS_SUBDIR="${SCENARIOS_DIR_REL:-tests/scenarios}"
CONFIG_FILE="$PROJECT_ROOT_ABS/$SCENARIOS_SUBDIR/scenarios.config.json"
EXTRA_ALLOW=""
if [ -f "$CONFIG_FILE" ]; then
	EXTRA_ALLOW=$(
		CFG="$CONFIG_FILE" python3 - <<'PYEOF'
import json, os
try:
    with open(os.environ["CFG"]) as f:
        cfg = json.load(f)
    roots = cfg.get("writeGuardAllowlist", [])
    if isinstance(roots, list):
        for r in roots:
            if isinstance(r, str) and r.strip():
                if r.startswith("~/"):
                    r = os.path.expanduser(r)
                print(r.rstrip("/"))
except Exception:
    pass
PYEOF
	)
fi

normalize_path() {
	local path="$1"
	# shellcheck disable=SC2088
	if [ "${path:0:2}" = '~/' ]; then
		path="${HOME}/${path:2}"
	elif [ "$path" = '~' ]; then
		path="$HOME"
	fi
	if command -v realpath >/dev/null 2>&1; then
		realpath -m "$path" 2>/dev/null || echo "$path"
	else
		echo "$path"
	fi
}

# Resolve ONE extracted path token to an absolute path for allowlist checking.
# Absolute / `~` paths pass through unchanged; a RELATIVE path is resolved against the
# payload's cwd, which is what the shell itself would do. Prints nothing and returns 1
# when a relative path cannot be resolved (no cwd in the payload) — callers treat that
# as "cannot verify" and BLOCK, matching is_allowed_path's own empty-is-forbidden rule.
resolve_against_cwd() {
	local raw="$1"
	# shellcheck disable=SC2088  # '~' here are literal case-patterns, not expansions
	case "$raw" in
	/* | '~/'* | '~') normalize_path "$raw" ;;
	*)
		[ -z "$HOOK_CWD" ] && return 1
		normalize_path "$HOOK_CWD/$raw"
		;;
	esac
}

# Is this token worth path-checking at all? Absolute, `~`-rooted, or containing a slash
# (`../x`, `./x`, `a/b`). A bare word (`-rf`, `pwned`) is NOT a path and is skipped, so
# widening the scans to relative paths does not turn every argument into a false block.
looks_like_path() {
	# shellcheck disable=SC2088  # '~' here is a literal case-pattern, not an expansion
	case "$1" in
	/* | '~'* | */* | . | ..) return 0 ;;
	*) return 1 ;;
	esac
}

is_allowed_path() {
	local candidate="$1"
	[ -z "$candidate" ] && return 1

	# Safe POSIX device sinks — always allowed (discard / terminal, not real writes).
	case "$candidate" in
	/dev/null | /dev/stdout | /dev/stderr | /dev/tty) return 0 ;;
	/dev/fd/*) return 0 ;;
	esac

	local abs
	abs=$(normalize_path "$candidate")

	# 1. Project root (main tree or worktree)
	case "$abs" in
	"$PROJECT_ROOT_ABS" | "$PROJECT_ROOT_ABS"/*) return 0 ;;
	esac

	# 2. Scratch areas (cross-platform: macOS /private/tmp + /var/folders/*, Linux /tmp)
	#    BOTH spellings of each macOS path are listed on purpose. normalize_path runs
	#    `realpath -m`, which resolves the symlinks: /tmp/* -> /private/tmp/* and
	#    /var/folders/* -> /private/var/folders/* . Without the /private/var/folders/*
	#    arm that pattern is DEAD on macOS and every write to $TMPDIR — mktemp -d,
	#    python tempfile, the default scratch — is blocked, while the block message
	#    still advertises it as allowed (measured 2026-08-29). The unresolved
	#    spellings stay for the no-realpath fallback, which matches the raw path.
	case "$abs" in
	/tmp | /tmp/*) return 0 ;;
	/private/tmp | /private/tmp/*) return 0 ;;
	/var/folders/*) return 0 ;;
	/private/var/folders/*) return 0 ;;
	esac

	# 3. Extra roots from scenarios.config.json "writeGuardAllowlist"
	if [ -n "$EXTRA_ALLOW" ]; then
		local root
		while IFS= read -r root; do
			[ -z "$root" ] && continue
			case "$abs" in
			"$root" | "$root"/*) return 0 ;;
			esac
		done <<<"$EXTRA_ALLOW"
	fi

	# ── PROJECT EXTENSION EXAMPLE (commented; prefer "writeGuardAllowlist") ──
	# If your scenarios legitimately write into per-test working dirs created
	# OUTSIDE the project (e.g. a test-entity sandbox under $HOME), allow them
	# with a TIGHT pattern that matches ONLY test artifacts, never real data:
	#   case "$abs" in
	#       "$HOME"/agents/scen[0-9]*|"$HOME"/agents/scen[0-9]*/*) return 0 ;;
	#   esac
	# Prefer adding such roots to "writeGuardAllowlist" over editing this script.

	return 1
}

# Strip heredoc bodies before scanning a Bash command. A heredoc body
# (<<'EOF' / <<"EOF" / <<EOF) is a literal stdin string and cannot contain real
# shell constructs, so scanning it false-positives on JS regex literals, JS
# fat-arrows (=> looks like a > redirect), and abs paths inside string literals.
# This matters a LOT: every dev-browser call is a `<<'EOF' … EOF` script.
strip_heredoc_bodies() {
	local input="$1"
	local output=""
	local in_heredoc=false
	local delim=""
	local here_re='<<-?['"'"'"]?([A-Za-z_][A-Za-z0-9_]*)['"'"'"]?'
	local line
	while IFS= read -r line; do
		if $in_heredoc; then
			if [ "$line" = "$delim" ]; then
				in_heredoc=false
				output+="$line"$'\n'
			fi
			continue
		fi
		if [[ "$line" =~ $here_re ]]; then
			delim="${BASH_REMATCH[1]}"
			in_heredoc=true
		fi
		output+="$line"$'\n'
	done <<<"$input"
	printf '%s' "$output"
}

block() {
	local reason="$1"
	cat >&2 <<EOF
BLOCKED by scenarios write-guard
  Tool:   $TOOL_NAME
  Reason: $reason

Allowed write roots:
  - $PROJECT_ROOT_ABS (project root / worktree)
  - /tmp, /private/tmp, /var/folders/*, /private/var/folders/* (system scratch)
  - extra roots from scenarios.config.json "writeGuardAllowlist"

Scenario subagents may READ from anywhere, but may only WRITE inside their
project root or scratch. If you need to modify a file outside these roots,
do not bypass this rule — return a DEFERRED report explaining what you wanted
to change and why, and leave the orchestrator to do it.
EOF
	exit 2
}

case "$TOOL_NAME" in
Write)
	FILE_PATH=$(json_field tool_input.file_path)
	is_allowed_path "$FILE_PATH" || block "Write target '$FILE_PATH' is outside allowed roots"
	;;
Edit)
	FILE_PATH=$(json_field tool_input.file_path)
	is_allowed_path "$FILE_PATH" || block "Edit target '$FILE_PATH' is outside allowed roots"
	;;
MultiEdit)
	FILE_PATH=$(json_field tool_input.file_path)
	is_allowed_path "$FILE_PATH" || block "MultiEdit target '$FILE_PATH' is outside allowed roots"
	;;
NotebookEdit)
	FILE_PATH=$(json_field tool_input.notebook_path)
	is_allowed_path "$FILE_PATH" || block "NotebookEdit target '$FILE_PATH' is outside allowed roots"
	;;
Bash)
	CMD=$(json_field tool_input.command)
	CMD_SCAN=$(strip_heredoc_bodies "$CMD")

	# ── PROJECT EXTENSION EXAMPLE — Rule-0 anti-bypass guards (commented) ──
	# The GENERIC guard below only enforces the WRITE-ROOT allowlist. If your
	# app exposes a mutating HTTP API or tmux test sessions, you may ALSO want
	# to stop subagents from bypassing the UI (Rule 6). Adapt to YOUR app:
	#   if echo "$CMD_SCAN" | grep -qE 'curl[^|;&]*(-X[[:space:]]+)?(DELETE|POST|PATCH|PUT)[^|;&]*(/api/(records|projects|accounts))'; then
	#       block "Rule 0: subagent attempted curl mutation of app endpoints. Use the UI (dev-browser)."
	#   fi
	# ──────────────────────────────────────────────────────────────────────

	# 1. `cd <path>` outside the allowlist — the primary escape vector. Covers BOTH
	#    absolute paths and RELATIVE ones (`cd ../..`), the latter resolved against the
	#    payload's cwd. Relative was unchecked until 2026-08-27 and was a live escape.
	while IFS= read -r cd_path; do
		[ -z "$cd_path" ] && continue
		looks_like_path "$cd_path" || continue
		resolved=$(resolve_against_cwd "$cd_path") ||
			block "Bash 'cd' to unresolvable relative dir (no cwd in hook payload): $cd_path"
		is_allowed_path "$resolved" || block "Bash 'cd' to forbidden dir: $cd_path -> $resolved"
	done < <(
		echo "$CMD_SCAN" |
			grep -oE '(^|[[:space:]]|&&|\|\||;|\()[[:space:]]*cd[[:space:]]+[^[:space:]&|;()"'"'"']+' |
			sed -E 's/^.*cd[[:space:]]+//' ||
			true
	)

	# 2. `git -C /path` outside the allowlist (absolute paths only).
	while IFS= read -r git_path; do
		[ -z "$git_path" ] && continue
		is_allowed_path "$git_path" || block "Bash 'git -C' references forbidden dir: $git_path"
	done < <(
		echo "$CMD_SCAN" |
			grep -oE 'git[[:space:]]+-C[[:space:]]+[^[:space:]&|;()"'"'"']+' |
			sed -E 's/^git[[:space:]]+-C[[:space:]]+//' |
			grep -E '^/' ||
			true
	)

	# 3. File redirection `> path` / `>> path` outside the allowlist — absolute AND
	#    relative (`> ../../f`), the latter resolved against the payload's cwd.
	while IFS= read -r redir_path; do
		[ -z "$redir_path" ] && continue
		looks_like_path "$redir_path" || continue
		resolved=$(resolve_against_cwd "$redir_path") ||
			block "Bash redirection to unresolvable relative path (no cwd in hook payload): $redir_path"
		is_allowed_path "$resolved" || block "Bash redirection target: $redir_path -> $resolved"
	done < <(
		echo "$CMD_SCAN" |
			grep -oE '[12]?>>?[[:space:]]*[^[:space:]&|;()"'"'"'<>]+' |
			sed -E 's/^[12]?>>?[[:space:]]*//' ||
			true
	)

	# 4a. cp/mv/ln/install — destination-only check (LAST positional arg is the
	#     write target; earlier args are read-only sources, allowed anywhere).
	if echo "$CMD_SCAN" | grep -qE '(^|[[:space:]]|&&|\|\||;|\()[[:space:]]*(cp|mv|ln|install)([[:space:]]|$)'; then
		cpmv_segment=$(echo "$CMD_SCAN" |
			grep -oE '(cp|mv|ln|install)[[:space:]]+[^&|;]+' |
			head -1 ||
			true)
		if [ -n "$cpmv_segment" ]; then
			last_pos=""
			# shellcheck disable=SC2086
			set -- $cpmv_segment
			while [ $# -gt 0 ]; do
				tok="$1"
				shift
				case "$tok" in
				cp | mv | ln | install) continue ;;
				-*) continue ;;
				*) last_pos="$tok" ;;
				esac
			done
			if looks_like_path "$last_pos"; then
				resolved=$(resolve_against_cwd "$last_pos") ||
					block "Bash cp/mv/ln/install destination unresolvable (no cwd in hook payload): $last_pos"
				is_allowed_path "$resolved" ||
					block "Bash cp/mv/ln/install destination outside allowed roots: $last_pos -> $resolved"
			fi
		fi
	fi

	# 4b. rm/mkdir/touch/tee/chmod/chown/dd/sed-i — all-path scan (tokenize,
	#     keep absolute-path tokens, reject any outside the allowlist).
	if echo "$CMD_SCAN" | grep -qE '(^|[[:space:]]|&&|\|\||;|\()[[:space:]]*(rm|mkdir|touch|tee|chmod|chown|dd)([[:space:]]|$)' ||
		echo "$CMD_SCAN" | grep -qE '(^|[[:space:]])sed[[:space:]]+-[a-zA-Z.]*i'; then
		while IFS= read -r tok; do
			[ -z "$tok" ] && continue
			case "$tok" in
			=* | --*) continue ;;
			esac
			# looks_like_path keeps absolute, ~-rooted and slash-bearing tokens
			# (`../../f`) and drops bare words (`-rf`), so relative write targets are
			# now checked without turning every argument into a false block.
			looks_like_path "$tok" || continue
			resolved=$(resolve_against_cwd "$tok") ||
				block "Bash write op references unresolvable relative path (no cwd in hook payload): $tok"
			is_allowed_path "$resolved" || block "Bash write op references forbidden path: $tok -> $resolved"
		done < <(
			echo "$CMD_SCAN" |
				tr -s '[:space:]' '\n' |
				sort -u ||
				true
		)
	fi
	;;
*)
	# Tool not in our matcher → allow
	;;
esac

exit 0
