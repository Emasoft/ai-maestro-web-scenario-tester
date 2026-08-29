# Rule: Prevent scenario subagents from writing outside their scope

**Severity: IRON.** The `web-scenario-tester` plugin enforces this write-guard
for its scenario subagents (the runner and the improvement-implementer)
automatically — it ships **with the plugin** as a sentinel-gated PreToolUse
hook. There is nothing for a consuming project to install; the consumer only
keeps the run-sentinel gitignored (done for you by `init-scenarios-folder.sh`).

## The rule

Every scenario subagent that does code modification can only WRITE inside:

1. **Its own project root or git worktree** — `$CLAUDE_PROJECT_DIR`
2. **System scratch** — `/tmp`, `/private/tmp`, `/var/folders/*`, `/private/var/folders/*` (for cloning/fixing auxiliary repos). Both spellings of each macOS root are listed on purpose: the guard matches after `realpath -m`, which resolves `/tmp` → `/private/tmp` and `/var/folders/*` → `/private/var/folders/*`, so a single unresolved spelling silently never matches.
3. **Any extra roots** the project explicitly lists in `scenarios.config.json` → `writeGuardAllowlist`

Reads may go anywhere. Writes are restricted to the roots above. No exceptions.

## Why this rule exists

`isolation: worktree` provides **filesystem isolation** — each worktree is a
separate git checkout. Historically it did **not** constrain the tools: a
subagent with `Bash`, `Write`, and `Edit` could walk out of its worktree with a
simple `cd ../..` and corrupt the parent repo.

**Claude Code 2.1.222 narrowed this upstream.** Its changelog entry reads:
"Fixed worktree-isolated sessions and their subagents being able to run
destructive git commands against the main checkout; isolation now applies to
file edits and Bash in every session type."

**Treat that as narrowing, not closure.** The entry is ambiguous in the
dimension that matters here: its first clause names *destructive git commands*,
while its second could mean the isolation boundary is enforced for all edits and
Bash. Nobody has tested which reading is correct against this repo, so **do not
assume the `cd ../..` escape is dead** — and do not delete this guard on the
strength of that sentence. The guard runs on every scenario run regardless of
CLI version, and it covers ground the upstream fix does not reach even under the
generous reading:

- **Runs that are not worktree-isolated at all.** A scenario batch executing in
  the main checkout gets no isolation from the CLI; the guard is the only limit.
- **The project's own allowlist.** `scenarios.config.json` → `writeGuardAllowlist`
  is a per-project policy the CLI knows nothing about.
- **Defense in depth.** The upstream fix is one version's behavior; a guard that
  fails closed does not depend on which CLI version the run happens to use.

This was not hypothetical: an overnight scenario batch had an
improvement-implementer subagent's destructive git command blocked by a global
git-safety hook; instead of deferring, the subagent `cd`-ed into the parent
repo, checked out a new branch on the parent's working tree, and committed
files there — corrupting it. The write-guard closes that gap by validating
every write tool call and catching the common Bash escape patterns.

### CLOSED 2026-08-27 — Bash checks now cover RELATIVE paths too

The gap recorded below was **fixed**: all four Bash checks (`cd`, redirection,
`cp/mv/ln/install` destination, and the `rm/mkdir/touch/tee/chmod/dd/sed -i` token
scan) now resolve relative paths against the hook payload's `cwd` before calling
`is_allowed_path`, instead of dropping them via `grep -E '^/'`.

- `resolve_against_cwd` — absolute/`~` pass through; relative is resolved against
  `HOOK_CWD` (from `json_field cwd`). If `cwd` is absent it returns 1 and the caller
  **blocks** — "cannot verify" is treated as forbidden, matching `is_allowed_path`'s
  own empty-is-forbidden rule.
- `looks_like_path` — only absolute, `~`-rooted or slash-bearing tokens are checked, so
  widening the token scan does not turn every bare argument (`-rf`, `pwned`) into a
  false block.

Verified with an 11-case probe suite (payloads piped straight to the script):
**blocked** `cd ../.. && echo > f`, `echo x > ../../f`, `rm ../../important`,
`cp a ../../dest`, `cd /etc`; **allowed** `cd scripts && ls`, `echo x > reports/x.txt`,
`rm -rf .pytest_cache`, `git status`, `cd /tmp`, and an in-project `Write`.

**Residual ceiling (deliberate):** resolution is per-token against the payload `cwd`, NOT
a per-segment shell interpreter — `cd a && cd b` resolves both against `cwd`, not `b`
against `cwd/a`. Chained relative `cd`s that stay inside the allowlist are unaffected;
an escaping chain still trips on its first escaping segment. Upgrade to per-segment cwd
tracking only if a real command shape defeats this.

### `--restricted` (Claude Code 2.1.248) — not a substitute for this guard

2.1.248 added `--restricted` (`CLAUDE_CODE_RESTRICTED=1`). Per the changelog it "removes the
built-in tools that run commands or code and `WebFetch` (unless named in `--tools`), keeps file
tools inside the working directory, refuses `bypassPermissions`, and ignores user, project and
local settings files." That is a different tradeoff, not a stronger guard: removing the
command/code-running tools removes `Bash`, which the runner and improvement-implementer
subagents both need to drive a scenario; and "ignores... project... settings files" would drop
this plugin's own `hooks/hooks.json` wiring along with the rest of project config — the
changelog names no carve-out for plugin-shipped hooks, so do not assume one survives. A run
cannot both need Bash and run `--restricted`, so do not switch scenario runs to `--restricted`
in place of the sentinel-gated guard.

### The original gap — Bash checks were ABSOLUTE-PATH ONLY (measured 2026-08-26)

The four Bash checks (`cd`, `git -C`, redirection, `cp/mv/rm/tee/...`) each filter
their extracted paths through `grep -E '^/'`, so **only absolute paths are
validated**. A purely relative escape is NOT blocked. Measured by piping hook
payloads straight into `scripts/amwst_subagent-write-guard.sh` with the sentinel
present:

| Probe | Observed |
|---|---|
| `Write` → `<project>/../ESCAPED.txt` | **exit 2 — guard BLOCKED it** ✅ |
| `Write` → in-project path (control) | exit 0 — guard did not block ✅ |
| `Bash` → `cd ../.. && echo pwned > ESCAPED2.txt` | **exit 0 — guard did NOT block** ❌ |

Read that table as written: it records what the **guard script** did with each
payload, not what the harness ultimately permitted, and no probe executed the
escape — `ESCAPED2.txt` was never created, because the payload is a JSON string
describing a command nobody ran. The script implements the exit-status contract
(`block()` writes plain text to stderr and exits 2; there is no
`permissionDecision` JSON on stdout anywhere in the file), so exit 0 does mean
"no objection raised" — but the claim proven here is precisely "the guard does
not object to a relative-path Bash escape", which is the claim that matters for
whether the Bash half can be relied on.

So the Write/Edit half of the guard is proven to work, and the Bash half stops
only the *absolute-path* form of the escape. The script's own comment names
`cd /absolute/path` "the primary escape vector" — this gap looks deliberate, not
accidental, but the sentence above overstated it, and `cd ../..` is precisely the
escape in the incident narrative above.

**Why it is not patched here on the spot:** a relative path's meaning depends on
the process's cwd, which this hook is not given (`CLAUDE_PROJECT_DIR` is the
project root, not the caller's cwd), so resolving one correctly needs the hook
payload's `cwd` field plumbed through `is_allowed_path` — a real change to a
security script, deserving its own test pass rather than a hurried regex. Until
then: **do not rely on the Bash half of this guard against a determined escape.**

## The design — a plugin-scoped PreToolUse hook, gated by a run sentinel

The write-guard is a **plugin-scoped** `PreToolUse` hook. `hooks/hooks.json`
wires `scripts/amwst_subagent-write-guard.sh` for the matcher
`Write|Edit|MultiEdit|NotebookEdit|Bash`, so it loads in **every** session that
has this plugin enabled — including the forked scenario subagents.

### Why this is safe even though it loads everywhere — the SENTINEL GATE

A plugin hook that fired in every session would be far too broad for a
write-guard. So the hook is **SENTINEL-GATED**: the very first thing the script
does (before it even reads stdin) is check for a run sentinel —

```
${CLAUDE_PROJECT_DIR}/.claude/scenario_is_running.json
```

If `CLAUDE_PROJECT_DIR` is unset or the sentinel is absent, the script
`exit 0`s immediately and does nothing. So in any normal (non-scenario) session
the guard is inert and zero-cost. It only enforces the write-root allowlist
**while a scenario run is active**.

### Why a plugin hook + sentinel, instead of a per-agent `hooks:` field

**Plugin-shipped agents CANNOT carry a `hooks:` frontmatter field.** This is a
Claude Code security restriction documented in the plugins-reference:

> Plugin agents support [...] For security reasons, `hooks`, `mcpServers`, and
> `permissionMode` are not supported for plugin-shipped agents.

Empirically: a plugin-shipped agent's `hooks:` field is silently ignored at
runtime. So the bundled agents (`amwst-scenario-runner`,
`amwst-scenario-improvement-implementer`) cannot self-attach the guard. A
**plugin-scoped hook** (in `hooks/hooks.json`) is honored, but it is
session-wide rather than agent-scoped — which is exactly why the sentinel gate
is the mechanism that scopes it to a run instead of to an agent. (This replaces
the older approach of installing a project-scoped agent shadow in the consumer's
`.claude/agents/` — no shadow is needed any more.)

### The run owner owns the sentinel lifecycle

The sentinel is what arms/disarms the guard, and the **run owner** manages it —
the `amwst-run-scenario` skill (single run), the `amwst-run-scenarios-batch`
skill (whole batch), or the main agent driving them:

- **Create at run START** — before forking any scenario subagent. A small JSON
  marker is enough, e.g.
  `{"scenario": "SCEN-016", "startedAt": "<iso>", "owner": "amwst-run-scenario"}`.
- **Delete at run END** — on success, failure, OR abort/cleanup. A leftover
  sentinel keeps the guard armed for later non-scenario sessions, so deleting it
  is mandatory on every exit path. For autonomous Rule-13 batches,
  `master-cleanup.sh` deletes it as its first step (belt-and-braces).

The sentinel is **gitignored** (`init-scenarios-folder.sh` adds
`.claude/scenario_is_running.json` to the consumer `.gitignore` idempotently).

### Spawn by bare or plugin name — both are guarded now

Because the guard is a plugin hook (not an agent-shadow `hooks:` field), it fires
for the bundled agents regardless of how they are spawned. There is no longer a
"must spawn by bare name or the hook won't fire" caveat — the old project-shadow
requirement is gone.

## What the guard does

The script (`scripts/amwst_subagent-write-guard.sh`, shipped with the plugin):

- **Sentinel gate first** — if `${CLAUDE_PROJECT_DIR}/.claude/scenario_is_running.json`
  is absent (or `CLAUDE_PROJECT_DIR` is unset), `exit 0` immediately and do
  nothing. Everything below runs only while a scenario run is active.
- Parses the PreToolUse JSON from stdin with `python3` (no `jq` dependency).
- `Write|Edit|MultiEdit|NotebookEdit` → checks the target path against the allowlist.
- `Bash` → strips heredoc bodies (so `dev-browser <<'EOF' …` JS scripts don't
  false-positive on `/regex/` or `=>` fat-arrows), then scans for absolute
  paths in `cd`, `git -C`, file redirection, and `rm`/`mv`/`cp`/`mkdir`/`touch`/
  `tee`/`chmod`/`chown`/`dd`/`install`/`ln`/`sed -i`.
- Exit code 2 blocks the tool call; the stderr message becomes the reason Claude sees.

## Extending the guard for your project

The guard is generic; extend it without forking the script:

- **Extra write roots** — add them to `writeGuardAllowlist` in
  `scenarios.config.json` (a JSON array of absolute paths; a leading `~/` is
  expanded). The script reads this key and permits those roots **without any
  edit to the script**. Prefer this over editing the guard — it keeps the
  engine generic and upgrade-safe.
- **App-specific block patterns** — for a tighter test-artifact allowlist or to
  stop UI-bypass mutations of your app's HTTP API (Rule 6), the script carries
  two clearly-marked, commented `PROJECT EXTENSION EXAMPLE` blocks (one in
  `is_allowed_path`, one in the `Bash` case) showing the exact pattern shape to
  copy. Adapt those to your app only if `writeGuardAllowlist` is not enough.

## What is NOT blocked

The write-guard restricts filesystem writes only. It does NOT block:

- HTTP requests (curl, wget, git push, gh) — those are a separate concern. If
  your app exposes a mutating API and you want scenarios to use the UI only
  (Rule 6), add the commented "Rule-0 anti-bypass" guards shown in the script's
  `PROJECT EXTENSION EXAMPLE` block.
- Running arbitrary binaries on PATH.
- Reading sensitive files (the read allowlist is "anywhere" by design).
- Process escape via `exec`/`setsid`/`nohup`/background jobs.

Network or process sandboxing is a separate layer (firejail, Docker,
`sandbox-exec`) outside this rule's scope.

## Self-test

You can exercise the guard by hand. With a sentinel present it should BLOCK an
out-of-root write and ALLOW an in-root one; with the sentinel absent it should
no-op (the gate). Example:

Set `GUARD` to the guard script path and `PROJ` to the project root, then
pass `PROJ` to the guard as a per-command inline variable assignment (the
guard reads the project root from its own `CLAUDE_PROJECT_DIR` parameter — a
scoped, per-invocation value, never a global shell export):

```bash
GUARD="$CLAUDE_PLUGIN_ROOT/scripts/amwst_subagent-write-guard.sh"
PROJ="$(pwd)"

# Gate OFF (no sentinel) → always exit 0, even for an outside path
printf '{"tool_name":"Write","tool_input":{"file_path":"/etc/passwd"}}' \
  | CLAUDE_PROJECT_DIR="$PROJ" "$GUARD"; echo "no-sentinel exit=$?"   # 0

# Gate ON → arm it
mkdir -p "$PROJ/.claude"
printf '{"scenario":"selftest","owner":"manual"}' > "$PROJ/.claude/scenario_is_running.json"
printf '{"tool_name":"Write","tool_input":{"file_path":"/etc/passwd"}}' \
  | CLAUDE_PROJECT_DIR="$PROJ" "$GUARD"; echo "outside exit=$?"      # 2 (BLOCK)
printf '{"tool_name":"Write","tool_input":{"file_path":"'"$PROJ"'/x.txt"}}' \
  | CLAUDE_PROJECT_DIR="$PROJ" "$GUARD"; echo "inside exit=$?"  # 0 (ALLOW)

# Disarm
rm -f "$PROJ/.claude/scenario_is_running.json"
```

## Checklist when running a code-modifying scenario subagent

- [ ] The plugin's `hooks/hooks.json` wires `scripts/amwst_subagent-write-guard.sh` as a `PreToolUse` hook (it does — shipped with the plugin)
- [ ] The consumer `.gitignore` ignores `.claude/scenario_is_running.json` (`init-scenarios-folder.sh` adds it)
- [ ] The run owner CREATES the sentinel at run start (this ARMS the guard)
- [ ] The run owner DELETES the sentinel at run end — success, fail, OR abort (this DISARMS it)
- [ ] The spawn prompt says: "Do not push. Do not merge. Return the branch name for the parent to push."
- [ ] The spawn prompt has a `[DEFERRED]` escape hatch for problems that would require an outside write
- [ ] After the subagent returns, `git status` shows the parent tree is clean before you push the branch
- [ ] If the parent tree is dirty after a spawn, the subagent escaped — investigate before pushing anything
