# `scenarios.config.json` — per-project configuration

`scenarios.config.json` lives in the consuming project at
`${CLAUDE_PROJECT_DIR}/<scenariosDir>/scenarios.config.json` (default
`tests/scenarios/scenarios.config.json`). It is the single place where
the `web-scenario-tester` plugin's GENERIC engine learns about YOUR app:
which browser instance to drive, where the dashboard lives, how to log
in, which build/test commands to run, and where subagents are allowed to
write.

The plugin's agents and skills read this file at runtime. `init-scenarios-folder.sh`
seeds a starter copy from `references/scenarios.config.template.json`; you
then fill in the real values for your app.

JSON cannot hold comments, so every key is documented here.

## Required keys

| Key | Type | Meaning |
|---|---|---|
| `scenariosDir` | string | Path (relative to the project root) of the scenarios folder. Default `"tests/scenarios"`. Everything else — `state/`, `reports/scenarios-runner/`, `state-backups/`, `fixtures/git/`, `scripts/` — lives under this dir. |
| `browserInstance` | string | The named `dev-browser` Chromium instance every scenario shares (so the logged-in `dashboard` page persists across runs). Passed as `dev-browser --browser <browserInstance>`. Pick a name unique to this project (e.g. `myapp-scenarios`) so other dev-browser usage on the machine stays isolated. |
| `dashboardUrl` | string | The base URL of the running app the scenarios drive (e.g. `http://localhost:3000/`). The login helper navigates here. Include the trailing slash. |
| `healthEndpoint` | string | A URL that returns HTTP 200 when the app is up. Master setup probes it before starting a batch. Use a real endpoint your app exposes — NOT a non-existent `/api/health` (verify it returns 200). |
| `governancePasswordRef` | string | A REFERENCE to the test login/sudo password — never the literal secret. Forms: `env:VAR_NAME` (read from environment), `file:/abs/path` (read first line of a file), or `keychain:service/account` if your helper supports it. Keeps the secret out of the git-tracked config. |
| `helpersScript` | string | Path (relative to project root) to YOUR project's dev-browser helpers script — the consumer-supplied equivalent of the reference `project-helpers-template.sh`. It implements the 3 required helper functions (login, sudo/confirm-modal, CRUD) for your app's specific DOM. |
| `writeGuardAllowlist` | array of strings | EXTRA absolute write-roots the subagent write-guard should permit, beyond the always-allowed `${CLAUDE_PROJECT_DIR}` + `/tmp` + `/private/tmp` + `/var/folders`. Leave `[]` unless scenarios legitimately write outside the project (e.g. a fixtures tree under `$HOME/…`). Each entry is matched as a prefix. |
| `typeCheckCommand` | string | Command the implementer runs to type-check after a code change (e.g. `npx tsc --noEmit`). Empty string `""` to skip type-checking. |
| `buildCommand` | string | Command to build the project (e.g. `npm run build`). Empty `""` to skip. |
| `testCommand` | string | Command to run the unit test suite (e.g. `npm test`). Empty `""` to skip. |
| `restartCommand` | string | Command that (re)starts the app so a freshly-built change is live (e.g. `npm run dev`, `pm2 restart myapp`). Empty `""` if the dev server hot-reloads. |
| `targetBranch` | string | The branch Phase-1 fix commits land on and Phase-3 worktrees branch off (e.g. `main`). |

## Optional keys (master-cleanup project teardown)

These power the OPTIONAL Step 2 (tmux sweep) and Step 3 (registry scan)
of `master-cleanup.sh`. Leave them as empty strings `""` (the template
default) and those steps are skipped — the generic cleanup core (stop
dev-browser → consolidate proposals → advance phase) still runs. Set
them only if your app spawns test tmux sessions or maintains an agent
registry that scenario runs touch.

| Key | Type | Meaning |
|---|---|---|
| `cleanupTmuxPattern` | string | An extended-regex (`grep -E`) matched against `tmux list-sessions` names. Matching sessions are killed during master cleanup. Example: `^(scen-|cos-scen-)`. Empty → skip the tmux sweep. |
| `registryScanPath` | string | Path to a JSON agent-registry file to scan for leftover test agents after a batch (read-only — it only LOGS lingering entries, never deletes). A leading `~/` is expanded. Empty → skip the registry scan. |
| `testAgentPattern` | string | An extended-regex matched against each registry entry's `name`. Matching entries are reported as lingering test artifacts. Required together with `registryScanPath`. Empty → skip. |

## Secret handling

`governancePasswordRef` is a reference, not the secret itself. The
plugin never reads the secret directly — your `helpersScript` resolves
the reference (e.g. `env:MYAPP_TEST_PASSWORD` → `$MYAPP_TEST_PASSWORD`)
at the moment it fills a password field. This keeps the committed
`scenarios.config.json` free of credentials. Both `reports/` and
`reports_dev/` are gitignored so screenshots that capture a typed
password never reach the repo (Rule 14).

## Example (a Next.js app on port 3000)

```json
{
  "scenariosDir": "tests/scenarios",
  "browserInstance": "acme-scenarios",
  "dashboardUrl": "http://localhost:3000/",
  "healthEndpoint": "http://localhost:3000/api/status",
  "governancePasswordRef": "env:ACME_E2E_PASSWORD",
  "helpersScript": "tests/scenarios/scripts/dev-browser-helpers/acme-helpers.sh",
  "writeGuardAllowlist": [],
  "typeCheckCommand": "npx tsc --noEmit",
  "buildCommand": "npm run build",
  "testCommand": "npm run test:unit",
  "restartCommand": "pm2 restart acme-web",
  "targetBranch": "main",
  "cleanupTmuxPattern": "",
  "registryScanPath": "",
  "testAgentPattern": ""
}
```
