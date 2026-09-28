---
schema_version: 1
state: HOLD
risk_lane: AMBER
title: "Diagnose XCUITest worker materialization stall"
goal: "Identify why the iPhone 18 Pro UI-test worker does not launch before testing result-bundle finalization."
allowed_files:
  - CURRENT_HANDOFF.md
  - NEXT_TASK.md
forbidden_files:
  - "ios/calorietracker/**"
  - "ios/calorietrackerTests/**"
  - "ios/calorietrackerUITests/**"
  - "ios/calorietracker.xcodeproj/**"
validation_required:
  - "One bounded, named UI-test startup observation; a build or runner cancellation is not a test execution."
  - "Record the actual command exit, named-test count, result-bundle readability, and worker/process evidence."
  - "Stop after one infrastructure stall; preserve all existing local edits."
auto_start_allowed: false
human_decision_required: false
commit_allowed: false
push_allowed: false
stop_conditions:
  - "Handoff state remains HOLD, BLOCKED, or DECISION_REQUIRED."
  - "Test worker fails to materialize or validation is flaky/incomplete."
  - "Product, nutrition, architecture, or protected-file changes become necessary."
  - "Scope expands, Git state is ambiguous, or credentials/permissions are required."
---

# Next task — advisory only

Search Food and Review Food remain on HOLD. This AMBER diagnostic is **not** pre-approved for automatic launch. The file names above describe permitted writes for a future separately authorized read-only investigation; other repository files may be inspected but must not be changed. Do not modify app behavior, tests, the scheme, or protected edits. The external routing consumer's first dry run must return `STOP: HOLD` without dispatching this task.
