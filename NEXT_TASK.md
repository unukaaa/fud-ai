---
schema_version: 1
state: COMPLETE
risk_lane: GREEN
task_id: routing-doc-consistency-audit
execution_target: cloud_clean_checkout
title: "Routing documentation consistency audit"
goal: "Read the routing policy, handoff, next-task envelope, and automation scripts; report inconsistencies without editing files, committing, pushing, or dispatching."
read_only: true
max_tasks: 1
max_duration_minutes: 15
allowed_files:
  - AUTOMATION_POLICY.md
  - CURRENT_HANDOFF.md
  - NEXT_TASK.md
  - scripts/automation_decision.rb
  - scripts/automation_dispatch.rb
  - scripts/automation_github_approval.rb
forbidden_files:
  - "ios/calorietracker/**"
  - "ios/calorietrackerTests/**"
  - "ios/calorietrackerUITests/**"
  - "ios/calorietracker.xcodeproj/**"
validation_required:
  - "Report inspected files and contradictions; confirm zero writes and zero dispatches."
auto_start_allowed: true
human_decision_required: false
commit_allowed: false
push_allowed: false
stop_conditions:
  - "Any write, product/test scope, ambiguity, stale approval, or changed Git state."
---

# Next task — advisory only

This GREEN pilot targets a clean cloud checkout of the exact approved remote HEAD. The listed files are inspection scope, not write permission; the pilot itself must make zero writes, Git mutations, or dispatches. Unrelated local Mac edits are not cloud-runner state. Search Food and Review Food remain on HOLD. A trusted external validation receipt and separate authenticated human approval bound to a future pushed HEAD and task digest are required before any pre-launch readiness decision.
