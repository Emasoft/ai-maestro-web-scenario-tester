# CPV canonical-pipeline check — ai-maestro-web-scenario-tester

Date: 2026-09-29 (local)
Scope: `scripts/publish.py`, `.github/workflows/*`, `git-hooks/pre-push`, `.claude-plugin/plugin.json`, standard files — compared against `cpv-canonical-pipeline` (SKILL.md + `references/detailed-standard.md`) and the canon source of truth `gen_publish_py()` / `gen_ci_yml()` / `gen_release_yml()` / `gen_pre_push_hook()` in CPV 5.21.1's `scripts/generate_plugin_repo.py`.

Profile declared in `plugin.json`: `cpv.pipeline_profile: remote-validation`. Per the canon, that profile's publish.py body is byte-identical to the standard template, so the full standard canon applies to `stage_commit_and_push`.

Basis note: comparison was made against pipeline files untouched by the 5 commits that landed mid-task (396eadd..c20bfa3 touch README/agents/design/references/skills/tests only); verified via `git diff 923e880..HEAD --stat`.

---

## Divergences found: 13 (3 fixed, 9 recommendations, 1 declared-intentional)

### FIXED (this run — one coherent change to scripts/publish.py)

| # | Divergence | Where | What was done |
|---|---|---|---|
| 1 | **Resolver tag missing** — Claude Code's version-constrained dependency resolver (`>=1.2` constraints) matches ONLY `{plugin-name}--v{version}` tags; the plain `vX.Y.Z` tag is ignored, so every release was unpinnable (ai-maestro issue #1) | `scripts/publish.py` `stage_commit_and_push` (old ~L1657-1715) | Added `_plugin_name()` (strict, None on unreadable — unlike `_read_plugin_name`), `_dependency_tag_name()` (double-hyphen `--v` separator), and dual-tag creation. For `web-scenario-tester` vN the second tag is `web-scenario-tester--vN`. |
| 2 | **Stale-tag-on-retry** — old code skipped tagging when the tag existed locally, so a retry after an interrupted publish pushed a PREVIOUS attempt's tag that no longer pointed at the validated tree | same | Both tags now route through `_ensure_tag_at_head()`: creates at HEAD, verifies existing tag is at HEAD, and is FAIL-CLOSED — refuses to move a tag that is already on origin or when `ls-remote` cannot answer (via `_remote_tag_state()` three-valued probe). |
| 3 | **Atomic-push hardening** — old push used module-default retry (60 attempts), `capture_output=False` (stderr=None broke the transient-error classifier), and no timeout override, while the branch-aware pre-push hook runs the whole gate inside the push's clock | same | Push is now `git push --atomic origin HEAD v{ver} {name}--v{ver}` (both tags land or neither), with `_PUSH_TIMEOUT_SEC` = 600 + 2×1800 + 1800 s, `_PUSH_MAX_ATTEMPTS = 3`, captured stderr echoed on failure, and a post-push `ls-remote` verification of BOTH tags (reports UNVERIFIED, never a false green). Dry-run prints both tags and the full atomic ref list. |

Applied as: new helper block (scripts/publish.py:1466-1619) + rewritten `stage_commit_and_push` (scripts/publish.py:1704-1796). Verified: `ruff check` clean, AST/compile clean, functional checks pass (`_dependency_tag_name` → `web-scenario-tester--v0.1.8`, dry-run output carries both tags, no tag created on disk, tree dirty only in publish.py).

Per the dispatcher's mid-task directive, everything below was left UNCHANGED as recommendations.

### RECOMMENDATIONS (not applied)

| # | Divergence | file:line | Canon says |
|---|---|---|---|
| 4 | **RC-8 fail-open in ci.yml validate handler** — `exit >= 5 → "advisory, exit 0"`. CPV's verdict exits stop at 4; exit 5+ is ALWAYS an infra failure (uvx missing = 127, OOM = 137), which currently silently PASSES the gate | `.github/workflows/ci.yml:177-193` | Canon's shared `gen_cpv_validate_run_block`: `tee` + `${PIPESTATUS[0]}` + `PYTHONUNBUFFERED=1`, pass only on exit 0; exit 1-4 fails as findings ONLY with CPV's `SUMMARY: CRITICAL=` line in the report; everything else fails as "validator FAILED TO RUN". Fail-closed. |
| 5 | **RC-8 fail-open in release.yml** — same hole, worse: the handler fails only on 1-4 and lets ANY other non-zero exit fall through to publish — an infra failure publishes an unvalidated tag | `.github/workflows/release.yml:70-79` | Same shared block; identical handler in canon's release job. |
| 6 | **Test-detection probe** — `ls tests/test_*.py` misses nested layouts (`tests/unit/`) and passes a literal glob through | `.github/workflows/ci.yml:241`, `release.yml:83` | Canon (issue #215): `find tests -name 'test_*.py' -type f -print -quit`. |
| 7 | **Missing `PLUGIN_REPO_LINT_PHASE_TIMEOUT: "600"`** in the Validate job env (issue #162: cold-runner uv/npm cache-lock serialization can march past the job timeout with orphaned children) | `.github/workflows/ci.yml` validate job env | Canon sets it in both ci.yml and release.yml validate jobs. |
| 8 | **`git add -A` in the release commit** — sweeps untracked files into a public release commit (reports/ carry private data) | `scripts/publish.py` stage_commit_and_push commit branch (~L1725) | Canon (issue #186): `git add -u` + named generated files (`plugin.json`, `CHANGELOG.md`, `README.md`, `pyproject.toml`, `uv.lock`), with an untracked-file NOT-staged notice. |
| 9 | **No `Agent:` trailer on the release commit** (PRRD G1.1 self-identification) | `scripts/publish.py` commit command (~L1726) | Canon appends `-m "Agent: <plugin-name>"` (no `@`; `@` stripped from the slug). |
| 10 | **gh release notes = full CHANGELOG.md** — eventually breaches GitHub's 125,000-char release-body limit after the tag is public (measured 109,539 on CPV itself) | `scripts/publish.py` `stage_gh_release` (~L1770-1780) | Canon: per-release notes at `reports/publish/release-notes-{ver}.md` via `git-cliff --unreleased --strip all`; `--generate-notes` fallback only. (Note: `release.yml`'s CI-created release already extracts the per-version section — only the publish.py fallback path is affected.) |
| 11 | **Pipeline is 11 stages, canon is 15** — missing: secret scan (trufflehog, as a stage — the pre-push hook only scans feature branches), Linux fork-parity probe, CI-parity preflight (`cpv-remote-validate ci-preflight .`) | `scripts/publish.py` main() stage sequence (~L1895+) | Canon `_PIPELINE_STAGES` (audit row 31: docstring, stage list and `--print-gates` are one source of truth). Architectural — adds runtime to every publish; recommend adopting via the standard `--force-templates` refresh rather than a hand-merge. |
| 12 | **release.yml is a single job; canon is 3 fail-closed jobs** (validate → artifact upload, test-shard matrix, release with `needs: [validate, test-shard]`) | `.github/workflows/release.yml` | Architectural. The current single job still gates the release on validation passing inline, so this is a parity gap, not a safety hole (the RC-8 hole in #5 is the safety hole). |
| 13 | **release.yml changelog fallback `cp CHANGELOG.md changelog.txt`** — full-history body (same 125k-limit exposure as #10, in CI) | `.github/workflows/release.yml:144-146` | Canon falls back to the bounded git log since the previous tag. |

### Declared intentional (not a finding)

- `.github/workflows/notify-marketplace.yml` — listed under `cpv.pipeline.intentional_divergence` in `.claude-plugin/plugin.json:29-31`. Content matches canon's receiver-notification pattern (SHA-pinned dispatch action, no-op without the PAT secret, master+main branches).

### Checked and conforming (no action)

- All action pins byte-match the canon (checkout v6.0.3 / setup-uv v8.2.0 / megalinter v8 / actionlint v1.7.12 / commitlint v6.2.1 / zizmor v0.5.7 / cache v5.0.5 / upload-artifact v7.0.1 / sbom v0.24.0 / attest v4.1.0 / repository-dispatch v4.0.0).
- ci.yml job set and bare check-run contexts (`Lint`, `Validate`, aggregate `Test` over a matrix) match canon root-cause #3 shape; merge_group trigger present.
- Standard files all present: `.commitlintrc.json`, `.cspell.json`, `.jscpd.json`, `.markdownlint.json`, `.mega-linter.yml`, `.python-version`, `cliff.toml`, `.gitignore` (incl. `.claude/`, `.tldr/`, `llm_externalizer_output/`), README `<!--BADGES-START/END-->` with shields badge, `git-hooks/pre-push` + `core.hooksPath=git-hooks`.
- Pre-push hook: branch-aware canon shape (feature branches get a fail-closed trufflehog scan; default branch/tags get the full gate) — matches `gen_pre_push_hook` semantics.
- CPV ref pin `@v2.151.0` is CONSISTENT across all three callsites (publish.py gate + stage, ci.yml, release.yml) — the pin's purpose (cold-build cache stability) is served; it is not freshness-drift. Optional future action: bump the pin deliberately in one commit touching all three files.
- stage_lint runs ruff + mypy in one stage (canon stage 3); stage_changelog idempotency already fixed (2099afa); stage_bump / stage_changelog / stage_gh_release interrupted-publish recovery all present and canon-shaped.

## Out of scope (per dispatch instructions)

- No version bump, no commit, no push. No local backfill of a `web-scenario-tester--v0.1.7` resolver tag for the already-released v0.1.7 (v0.1.7 remains unpinnable until the next publish ships both tags, or a manual one-off `git tag -a web-scenario-tester--v0.1.7 v0.1.7 && git push origin web-scenario-tester--v0.1.7` is chosen by the owner).
