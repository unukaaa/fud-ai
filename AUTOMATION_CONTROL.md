# FOOD AI Automation Control

This file exists only to keep a standing control pull request open for ChatGPT Work / GitHub event-trigger testing.

Rules:
- No production behavior changes.
- No app/test file changes through this control PR.
- Automation approvals must remain bounded to the exact task, HEAD, digest, expiry, and permissions.
- GREEN tasks only may be considered for unattended launch.
- AMBER / RED / HOLD / BLOCKED / DECISION_REQUIRED always stop.
- Commit and push permissions remain false unless separately and explicitly authorized.

Current pilot:
- task_id: routing-doc-consistency-audit
- execution_target: cloud_clean_checkout
- read_only: true
- max_tasks: 1
- max_duration_minutes: 15
- commit_allowed: false
- push_allowed: false
