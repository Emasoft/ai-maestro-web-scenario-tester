#!/usr/bin/env bash
# ============================================================================
# project-helpers-template.sh — TEMPLATE for a consumer's dev-browser helpers
# ============================================================================
# This is a TEMPLATE, not a runnable helper. Copy it into your project at the
# path you set as `helpersScript` in scenarios.config.json (conventionally
# tests/scenarios/scripts/dev-browser-helpers/<yourapp>-helpers.sh), then
# implement the 3 REQUIRED functions for YOUR app's specific DOM.
#
# The scenario-runner sources this script (Rule 8) before every scenario run
# and calls these functions to drive your app's UI through `dev-browser`.
#
# ─────────────────────────────────────────────────────────────────────────
# THE 3-ENV-VAR CONTRACT (the runner exports these; you read them)
# ─────────────────────────────────────────────────────────────────────────
# The runner resolves these three values from scenarios.config.json and
# exports them into the environment before sourcing this file. Read them with
# the `:-` fallbacks shown so the script also works when run by hand.
#
#   1. APP_BROWSER          — the named dev-browser Chromium instance to drive
#                             (from config key `browserInstance`). Pass it as
#                             `dev-browser --browser "$APP_BROWSER"` in EVERY
#                             call so the persistent `dashboard` page (logged in
#                             once at master setup) is reused across runs.
#   2. APP_DASHBOARD_URL    — the base URL of the running app
#                             (from config key `dashboardUrl`).
#   3. APP_SCREENSHOTS_ROOT — absolute root dir for screenshots
#                             (the runner points this at reports/, per Rule 14).
#
# Naming note: pick env-var names unique to your app (e.g. ACME_BROWSER) and
# keep them consistent between this file and the runner's invocation. The names
# below (APP_*) are placeholders.
# ============================================================================

set -euo pipefail

APP_BROWSER="${APP_BROWSER:-myapp-scenarios}"
APP_DASHBOARD_URL="${APP_DASHBOARD_URL:-http://localhost:3000/}"
APP_SCREENSHOTS_ROOT="${APP_SCREENSHOTS_ROOT:-${CLAUDE_PROJECT_DIR:-$(pwd)}/reports/scenarios-runner/screenshots}"

# Standard dev-browser flags from Rule 8 — every helper MUST use these.
#   --headless        : unattended; no window focus-stealing (drop only to debug)
#   --timeout 60      : the scenario default (some dashboard pages need >30s)
DB_FLAGS=(--browser "$APP_BROWSER" --headless --timeout 60)

# ─────────────────────────────────────────────────────────────────────────
# REQUIRED HELPER 1 — login
# ─────────────────────────────────────────────────────────────────────────
# app_login <password>
#
# Open (or re-attach to) the persistent `dashboard` named page, navigate to
# the app, and if a login form is visible, fill it and submit. If already
# logged in, return immediately without re-filling (idempotent).
#
# Resolve the password from the config's `governancePasswordRef` BEFORE
# calling this (e.g. `pw="$MYAPP_TEST_PASSWORD"` for `env:MYAPP_TEST_PASSWORD`).
# NEVER hardcode the secret in this file.
#
# Print a JSON summary on stdout (e.g. {"ok":true,"already_logged_in":false}).
# Exit non-zero on timeout / navigation error.
#
# IMPLEMENT FOR YOUR APP: replace the selectors below with your real login
# form's input / button selectors.
app_login() {
	local password="${1:?app_login: missing password argument}"
	local password_json
	password_json="$(printf '%s' "$password" | python3 -c 'import json,sys; print(json.dumps(sys.stdin.read()))')"
	dev-browser "${DB_FLAGS[@]}" <<EOF
const page = await browser.getPage("dashboard");
try {
  if (page.url() === "about:blank" || !page.url().startsWith("${APP_DASHBOARD_URL}")) {
    await page.goto("${APP_DASHBOARD_URL}", { waitUntil: "domcontentloaded", timeout: 45000 });
  }
} catch (e) {
  await page.goto("${APP_DASHBOARD_URL}", { waitUntil: "domcontentloaded", timeout: 45000 });
}
await new Promise(r => setTimeout(r, 3000));
// TODO(yourapp): replace these selectors with your login form's real ones.
const pre = await page.evaluate(() => ({
  hasLoginForm: !!document.querySelector('input[type="password"]'),
}));
let already = !pre.hasLoginForm;
if (!already) {
  await page.fill('input[type="password"]', ${password_json});
  await page.click('button[type="submit"]');
  await new Promise(r => setTimeout(r, 3000));
}
console.log(JSON.stringify({ ok: true, already_logged_in: already, url: page.url() }));
EOF
}

# ─────────────────────────────────────────────────────────────────────────
# REQUIRED HELPER 2 — sudo / confirm-modal
# ─────────────────────────────────────────────────────────────────────────
# app_confirm_modal <password>
#
# Many apps gate a destructive action (delete, change-role, etc.) behind a
# re-authentication / confirmation modal. This helper detects that modal,
# fills the password (or confirmation field), and submits. If no modal is
# present, it is a no-op (returns ok:true, modal:false).
#
# If your app has NO such modal, implement this as an immediate no-op that
# prints {"ok":true,"modal":false} — the runner calls it defensively after
# destructive clicks.
#
# IMPLEMENT FOR YOUR APP: replace the modal locator + field/button selectors.
app_confirm_modal() {
	local password="${1:?app_confirm_modal: missing password argument}"
	local password_json
	password_json="$(printf '%s' "$password" | python3 -c 'import json,sys; print(json.dumps(sys.stdin.read()))')"
	dev-browser "${DB_FLAGS[@]}" <<EOF
const page = await browser.getPage("dashboard");
// TODO(yourapp): replace with your confirm/sudo modal's real selectors.
const present = await page.evaluate(() =>
  !!document.querySelector('[role="dialog"][aria-modal="true"] input[type="password"]'));
if (!present) {
  console.log(JSON.stringify({ ok: true, modal: false }));
} else {
  await page.fill('[role="dialog"][aria-modal="true"] input[type="password"]', ${password_json});
  await page.click('[role="dialog"][aria-modal="true"] button');
  await new Promise(r => setTimeout(r, 1500));
  console.log(JSON.stringify({ ok: true, modal: true }));
}
EOF
}

# ─────────────────────────────────────────────────────────────────────────
# REQUIRED HELPER 3 — CRUD (create / read / update / delete a domain entity)
# ─────────────────────────────────────────────────────────────────────────
# Scenarios create test entities (Rule 2: never touch real user data) and
# delete them in cleanup (Rule 1). Provide at least a create + a delete that
# drive YOUR app's real UI (forms, buttons) — NOT the API (Rule 6 forbids
# bypassing the UI). What "entity" means is app-specific (a record, a project,
# an account…); model these on your dominant test entity.
#
# app_create_entity <name> [extra args…]
#   Drive the app's "new entity" UI flow to create a test entity named <name>.
#   Print a JSON summary including any id the UI surfaces.
#
# app_delete_entity <name-or-id>
#   Drive the app's delete UI flow (calling app_confirm_modal if a sudo modal
#   appears). Verify the entity is gone. Print a JSON summary.
#
# IMPLEMENT FOR YOUR APP.
app_create_entity() {
	local name="${1:?app_create_entity: missing name}"
	shift || true
	# TODO(yourapp): click "New", fill the form, submit; screenshot via app_screenshot.
	echo "TODO: implement app_create_entity for $name" >&2
	return 1
}

app_delete_entity() {
	local ref="${1:?app_delete_entity: missing name-or-id}"
	# TODO(yourapp): open the entity, click delete, handle app_confirm_modal, verify gone.
	echo "TODO: implement app_delete_entity for $ref" >&2
	return 1
}

# ─────────────────────────────────────────────────────────────────────────
# RECOMMENDED HELPER — screenshot (Rule 10 PHOTOSTORY)
# ─────────────────────────────────────────────────────────────────────────
# app_screenshot <step-id> <short-desc>
#   Save a JPEG screenshot of the current dashboard page into the per-run
#   screenshots dir under $APP_SCREENSHOTS_ROOT. Filenames follow Rule 10.
app_screenshot() {
	local step="${1:?app_screenshot: missing step-id}"
	local desc="${2:?app_screenshot: missing short-desc}"
	local run_id="${RUN_ID:-$(date -u +%Y%m%dT%H%M%SZ)}"
	local out_dir="$APP_SCREENSHOTS_ROOT/${SCEN_ID:-SCEN-000}_${run_id}"
	mkdir -p "$out_dir"
	local out_dir_json
	out_dir_json="$(printf '%s' "$out_dir" | python3 -c 'import json,sys; print(json.dumps(sys.stdin.read()))')"
	dev-browser "${DB_FLAGS[@]}" <<EOF
const page = await browser.getPage("dashboard");
await saveScreenshot(page, ${out_dir_json} + "/${step}_${run_id}_${desc}.jpg", { type: "jpeg", quality: 97 });
console.log("screenshot ${step}");
EOF
}

# ─────────────────────────────────────────────────────────────────────────
# NOTES
# ─────────────────────────────────────────────────────────────────────────
# * The `*_json` locals JSON-encode a shell value before it is interpolated
#   into the QuickJS heredoc, so quotes/backslashes in a password or path can
#   never break (or inject into) the script. Keep that encoding when you adapt
#   these helpers — interpolate `${password_json}`, never the raw `$password`.
# * Load the dev-browser API surface via the `dev-browser:dev-browser` skill —
#   do NOT hardcode any path under the dev-browser plugin cache; it is ephemeral.
# * Every function spawns ONE short-lived QuickJS sandbox via the persistent
#   daemon; the named `dashboard` page keeps cookies/session across calls.
