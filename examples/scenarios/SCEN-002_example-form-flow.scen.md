---
number: 2
name: Example form flow — submit the contact form and see the success state
version: "1.0"
description: >
  As a visitor, you open the contact page, fill in the name, email, and message
  fields with clearly test-prefixed values, submit the form, and confirm the app
  shows a success confirmation. You then verify the form resets so the page is
  back to its starting state. A short happy-path form-submission flow that proves
  client-side validation accepts good input and the submit path reaches a success
  state. The only data produced is one ephemeral test submission with
  test-prefixed values.
client: claude
interhosts: false
device: desktop
subsystems:
  - frontend-routing
  - form-handling
  - client-validation
ui_sections:
  - Contact page -> Form -> Name field
  - Contact page -> Form -> Email field
  - Contact page -> Form -> Message field
  - Contact page -> Form -> Submit button
  - Contact page -> Success banner
data_produced:
  - 1 contact-form submission with test-prefixed values (temporary, ephemeral)
rewipe-list: []
git-fixtures: []
dir-fixtures: []
browser_stack: dev-browser
prerequisites:
  - The web app under test is running and reachable at its configured appUrl
  - The app has a contact form reachable at a /contact route (adjust per app)
  - dev-browser plugin available (loaded via the dev-browser:dev-browser skill)
  - tests/scenarios/scenarios.config.json present with appUrl set
governance_password: "n/a — generic web app, no governance"
commit: TBD
author: web-scenario-tester examples
---

# Scenario: Example form flow — submit the contact form and see the success state

A short happy-path form-submission test for any generic web app with a contact
form. Adjust the route, field labels, and success-banner text to your app via the
step Actions below.

## Phase 0: SAFE-SETUP

#### S001: Open the contact page
- **Action:** Via dev-browser, open a page named `app` and navigate to the contact route (e.g. `${appUrl}/contact`, from `tests/scenarios/scenarios.config.json`). Wait for the page to load.
- **Goal:** The contact page responds with HTTP 200 and the form is rendered.
- **Creates:** nothing
- **Modifies:** nothing
- **Verify:** The form's Name, Email, and Message fields are present in the snapshot; take a screenshot of the empty form.

---

## Phase 1: Fill, submit, and confirm success

#### S002: Fill the Name field with a test-prefixed value
- **Action:** Click the Name input to focus it, then type `scen-test User`.
- **Goal:** The Name field contains the test-prefixed value.
- **Creates:** nothing
- **Modifies:** the Name input's value (in-memory form state only)
- **Verify:** Snapshot shows `scen-test User` in the Name field; take a screenshot.

#### S003: Fill the Email field with a test address
- **Action:** Click the Email input to focus it, then type `scen-test@example.com`.
- **Goal:** The Email field contains a valid-format test address.
- **Creates:** nothing
- **Modifies:** the Email input's value (in-memory form state only)
- **Verify:** Snapshot shows `scen-test@example.com` in the Email field; take a screenshot.

#### S004: Fill the Message field
- **Action:** Click the Message textarea to focus it, then type `scen-test message — automated smoke check, please ignore.`.
- **Goal:** The Message field contains the test message.
- **Creates:** nothing
- **Modifies:** the Message textarea's value (in-memory form state only)
- **Verify:** Snapshot shows the test message in the Message field; take a screenshot of the filled form.

#### S005: Submit the form
- **Action:** Click the Submit button. Wait for the app to process the submission and render its response.
- **Goal:** The submit action completes and the app transitions to a success state.
- **Creates:** 1 ephemeral contact-form submission with test-prefixed values
- **Modifies:** nothing persistent that the UI exposes for cleanup
- **Verify:** A success confirmation (banner / message / redirect) is visible in the snapshot; take a screenshot of the success state.

#### S006: Confirm the success confirmation text
- **Action:** Read the page snapshot. Locate the success banner / confirmation element.
- **Goal:** The app explicitly confirms the message was sent (e.g. "Thanks" / "Message sent").
- **Creates:** nothing
- **Modifies:** nothing
- **Verify:** Snapshot contains the success text; take a screenshot showing the confirmation.

---

## Phase CLEANUP: Restore Original State

#### S007: Reload the contact page to clear form state
- **Action:** Via dev-browser, navigate the `app` page back to the contact route to reset the form.
- **Goal:** The form returns to its empty, pristine state, matching the Phase 0 starting point.
- **Removes:** the in-memory form values entered during Phase 1 (the test submission itself is ephemeral; if your app persists submissions, delete the test entry through the app's UI here)
- **Verify:** The Name, Email, and Message fields are empty again; take a screenshot of the reset form.

#### S008: STATE-WIPE — restore configuration files
- **Action:** This scenario has an empty `rewipe-list` and modified no config files, so there is nothing to restore. Confirm `rewipe-list` is empty and skip restoration.
- **Goal:** No configuration files were modified by this scenario.
- **Removes:** nothing
- **Verify:** `rewipe-list` is empty; nothing to compare.

#### S009: Post-test screenshot
- **Action:** Take a screenshot of the full contact page.
- **Goal:** UI identical to the Phase 0 baseline (empty form).
- **Creates:** nothing
- **Modifies:** nothing
- **Verify:** Screenshot saved; visual comparison with the Phase 0 baseline screenshot.
