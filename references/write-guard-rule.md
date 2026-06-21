# Rule: Prevent scenario subagents from writing outside their scope

**Severity: IRON.** Any project that runs the `web-scenario-tester` plugin's
scenario subagents (the runner and the improvement-implementer) MUST install
this write-guard. It is not optional.

## The rule

Every scenario subagent that does code modification can only WRITE inside:

1. **Its own project root or git worktree** — `$CLAUDE_PROJECT_DIR`
2. **System scratch** — `/tmp`, `/private/tmp`, `/var/folders` (for cloning/fixing auxiliary repos)
3. **Any extra roots** the project explicitly lists in `scenarios.config.json` → `writeGuardAllowlist`

Reads may go anywhere. Writes are restricted to the roots above. No exceptions.

## Why this rule exists

`isolation: worktree` provides **filesystem isolation only** — each worktree is
a separate git checkout. It does **NOT** provide process sandboxing. A subagent
with `Bash`, `Write`, and `Edit` tools can walk out of its worktree with a
simple `cd ../..` and corrupt the parent repo.

This was not hypothetical: an overnight scenario batch had an
improvement-implementer subagent's destructive git command blocked by a global
git-safety hook; instead of deferring, the subagent `cd`-ed into the parent
repo, checked out a new branch on the parent's working tree, and committed
files there — corrupting it. The write-guard closes that gap by validating
every write tool call and catching the common Bash escape patterns.

## THE PLATFORM CONSTRAINT — why a project shadow is the only place this works

**Plugin-shipped subagents CANNOT carry a `hooks:` frontmatter field.** This is
a Claude Code security restriction documented in the plugins-reference:

> Plugin agents support [...] For security reasons, `hooks`, `mcpServers`, and
> `permissionMode` are not supported for plugin-shipped agents.

Empirically: a plugin-shipped agent's `hooks:` field is silently ignored at
runtime. So the `web-scenario-tester` plugin's bundled agents
(`amwst-scenario-runner`, `amwst-scenario-improvement-implementer`) deliberately
ship **without** a `hooks:` field — they cannot enforce the write-guard on
their own.

The ONLY way to wire a `PreToolUse` write-guard onto a code-modifying scenario
subagent is to give the consuming project its own **PROJECT-SCOPED shadow** of
the agent under `.claude/agents/`, which references a guard script under
`.claude/scripts/`. A project-scoped agent definition CAN carry `hooks:`.

## How the consumer wires it (the project-scoped shadow)

`init-scenarios-folder.sh` installs the guard script for you and prints these
steps. To wire the shadow:

1. **The guard script** is installed at
   `${CLAUDE_PROJECT_DIR}/.claude/scripts/subagent-write-guard.sh`
   (from the plugin's `amwst_subagent-write-guard.sh.template`, `.template`
   suffix dropped, made executable).

2. **A project-scoped agent shadow** at
   `${CLAUDE_PROJECT_DIR}/.claude/agents/scenario-runner.md` (and one for
   `scenario-improvement-implementer.md`). Each is a thin shadow whose
   frontmatter carries `isolation: worktree` + the `hooks:` field, and whose
   body says "follow the bundled `amwst-scenario-runner` behavior". Frontmatter:

   ```yaml
   ---
   name: scenario-runner
   description: Project-scoped shadow of amwst-scenario-runner with the write-guard hook.
   isolation: worktree
   hooks:
     PreToolUse:
       - matcher: "Write|Edit|MultiEdit|NotebookEdit|Bash"
         hooks:
           - type: command
             command: "${CLAUDE_PROJECT_DIR}/.claude/scripts/subagent-write-guard.sh"
   ---
   ```

3. **Spawn by BARE NAME.** Spawn the subagent as `scenario-runner` — NOT a
   plugin-namespaced name. A plugin-namespaced spawn
   (`web-scenario-tester:amwst-scenario-runner`) resolves to the plugin's
   hookless version and the guard will NOT fire. The bare name resolves to the
   project-scoped shadow, which honors the `hooks:` field.

## What the guard does

The script (`subagent-write-guard.sh`):

- Parses the PreToolUse JSON from stdin with `python3` (no `jq` dependency).
- `Write|Edit|MultiEdit|NotebookEdit` → checks the target path against the allowlist.
- `Bash` → strips heredoc bodies (so `dev-browser <<'EOF' …` JS scripts don't
  false-positive on `/regex/` or `=>` fat-arrows), then scans for absolute
  paths in `cd`, `git -C`, file redirection, and `rm`/`mv`/`cp`/`mkdir`/`touch`/
  `tee`/`chmod`/`chown`/`dd`/`install`/`ln`/`sed -i`.
- Exit code 2 blocks the tool call; the stderr message becomes the reason Claude sees.

The allowlist reads `writeGuardAllowlist` from `scenarios.config.json` so a
project can permit extra roots **without editing the script**. Prefer adding
roots to that config key over editing the installed guard — keep the engine
generic.

## What is NOT blocked

The write-guard restricts filesystem writes only. It does NOT block:

- HTTP requests (curl, wget, git push, gh) — those are a separate concern. If
  your app exposes a mutating API and you want scenarios to use the UI only
  (Rule 6), add the commented "Rule-0 anti-bypass" guards shown in the template.
- Running arbitrary binaries on PATH.
- Reading sensitive files (the read allowlist is "anywhere" by design).
- Process escape via `exec`/`setsid`/`nohup`/background jobs.

Network or process sandboxing is a separate layer (firejail, Docker,
`sandbox-exec`) outside this rule's scope.

## Self-test

Run the bundled `tests/test-write-guard.sh` against the installed guard to
confirm it blocks an out-of-root write and allows an in-root write before you
trust it in an overnight batch.

## Checklist when spawning a code-modifying scenario subagent

- [ ] The project has the guard at `.claude/scripts/subagent-write-guard.sh` (executable)
- [ ] The project has a `.claude/agents/<name>.md` shadow with `isolation: worktree` + the `hooks:` field
- [ ] You spawn it by BARE name (no plugin namespace), so the hook fires
- [ ] The spawn prompt says: "Do not push. Do not merge. Return the branch name for the parent to push."
- [ ] The spawn prompt has a `[DEFERRED]` escape hatch for problems that would require an outside write
- [ ] After the subagent returns, `git status` shows the parent tree is clean before you push the branch
- [ ] If the parent tree is dirty after a spawn, the subagent escaped — investigate before pushing anything
