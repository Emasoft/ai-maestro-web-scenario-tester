---
number: 1
name: Example smoke test — homepage loads and primary navigation works
version: "1.0"
description: >
  As a first-time visitor, you open the web app's homepage in a browser, confirm
  the page loads with its title and main heading visible, then click the primary
  navigation link to the About page and confirm you land there. A minimal
  end-to-end smoke test that proves the app boots, serves its homepage, and its
  top navigation routes correctly. No data is created or modified — this is a
  read-only walkthrough.
client: claude
interhosts: false
device: desktop
subsystems:
  - frontend-routing
  - static-assets
ui_sections:
  - Homepage -> Header -> Page title
  - Homepage -> Main -> Primary heading
  - Homepage -> Header -> Nav -> About link
  - About page -> Main -> Heading
data_produced:
  - nothing (read-only walkthrough)
rewipe-list: []
git-fixtures: []
dir-fixtures: []
browser_stack: dev-browser
prerequisites:
  - The web app under test is running and reachable at its configured appUrl
  - dev-browser plugin available (loaded via the dev-browser:dev-browser skill)
  - tests/scenarios/scenarios.config.json present with appUrl set
governance_password: "n/a — generic web app, no governance"
commit: TBD
author: web-scenario-tester examples
---

# Scenario: Example smoke test — homepage loads and primary navigation works

A minimal, read-only smoke test for any generic web app. Replace `appUrl`, the
heading text, and the nav link label with your app's real values via
`scenarios.config.json` and the step Actions below.

## Phase 0: SAFE-SETUP

#### S001: Launch the browser and open the homepage
- **Action:** Via dev-browser, open a page named `app` and navigate to the app's base URL (the `appUrl` from `tests/scenarios/scenarios.config.json`). Wait for the document to finish loading.
- **Goal:** The homepage responds with HTTP 200 and the page is fully loaded.
- **Creates:** nothing
- **Modifies:** nothing
- **Verify:** Page navigation resolves without a network error; take a screenshot of the loaded homepage.

---

## Phase 1: Homepage and navigation

#### S002: Confirm the homepage title and main heading are visible
- **Action:** Read the page snapshot. Locate the document `<title>` and the page's primary `<h1>` heading.
- **Goal:** The page title is non-empty and the main `<h1>` heading is present and visible.
- **Creates:** nothing
- **Modifies:** nothing
- **Verify:** Snapshot contains a non-empty title and an `<h1>`; take a screenshot showing the heading.

#### S003: Click the primary navigation link to the About page
- **Action:** In the header navigation, click the "About" link (adjust the label to your app's nav). Wait for the About page to load.
- **Goal:** The browser navigates to the About route and that page loads.
- **Creates:** nothing
- **Modifies:** nothing
- **Verify:** The URL changes to the About path; take a screenshot of the About page after navigation.

#### S004: Confirm the About page rendered its own heading
- **Action:** Read the page snapshot on the About page. Locate its primary heading.
- **Goal:** The About page shows its own distinct `<h1>` heading (different from the homepage).
- **Creates:** nothing
- **Modifies:** nothing
- **Verify:** Snapshot shows the About heading text; take a screenshot of the verified About heading.

---

## Phase CLEANUP: Restore Original State

#### S005: Navigate back to the homepage
- **Action:** Via dev-browser, navigate the `app` page back to the base URL.
- **Goal:** The browser is back on the homepage, matching the Phase 0 starting point.
- **Removes:** nothing (read-only scenario created no artifacts)
- **Verify:** Homepage loads again; take a screenshot.

#### S006: STATE-WIPE — restore configuration files
- **Action:** This scenario has an empty `rewipe-list` and created no state, so there are no config files to restore. Confirm `rewipe-list` is empty and skip restoration.
- **Goal:** No configuration files were modified by this scenario.
- **Removes:** nothing
- **Verify:** `rewipe-list` is empty; nothing to compare.

#### S007: Post-test screenshot
- **Action:** Take a screenshot of the full homepage.
- **Goal:** UI identical to the Phase 0 baseline.
- **Creates:** nothing
- **Modifies:** nothing
- **Verify:** Screenshot saved; visual comparison with the Phase 0 baseline screenshot.
