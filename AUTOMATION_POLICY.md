---
schema_version: 1
handoff_file: CURRENT_HANDOFF.md
next_task_file: NEXT_TASK.md
states: [COMPLETE, HOLD, BLOCKED, DECISION_REQUIRED]
lane_precedence: [RED, AMBER, GREEN]
risk_lanes:
  GREEN: "Mechanical, reversible, objectively validated; no product or architecture decision."
  AMBER: "Architecture, concurrency, flaky tests, timing or behavior changes, or broader ownership questions."
  RED: "Product decisions, nutrition logic, schema or data-model changes, destructive Git, or irreversible/high-impact changes."
defaults:
  auto_start_allowed: false
  commit_allowed: false
  push_allowed: false
forced_hold:
  flaky_or_incomplete_validation: AMBER
  protected_file_write_or_conflict: AMBER
  scope_expansion: AMBER
  human_or_product_choice: RED
---

# FOOD AI automation routing policy

The YAML front matter in this file, `CURRENT_HANDOFF.md`, and `NEXT_TASK.md` is the machine-readable contract. The prose explains it; it does not override the fields. Unknown, missing, contradictory, or stale fields fail closed to `HOLD` with `auto_start_allowed: false`. A higher-risk lane always wins.

`CURRENT_HANDOFF.md` records the repository continuation gate (`state`), the proposed next task's `risk_lane`, the last task's status/lane, exact validation evidence, and the next-task envelope reference. `NEXT_TASK.md` is advisory, not authorization. Its `state` must match the handoff gate. A completed documentation task can coexist with a repository `HOLD`.

Automatic launch is eligible only when **both** files say `state: COMPLETE`, both say `risk_lane: GREEN`, both explicitly say `auto_start_allowed: true`, validation is complete and objectively passing, `human_decision_required: false`, Git/protected files are safe, and a separate human-approved finite task list with time/task bounds authorizes that exact task. `HOLD`, `BLOCKED`, `DECISION_REQUIRED`, AMBER, and RED always stop. Flaky or incomplete validation, a protected-file write/conflict, scope expansion, or a human/product choice forces AMBER/RED and `HOLD` (or `DECISION_REQUIRED` when a choice is needed).

No envelope may authorize commit or push by default. Either action requires an explicit envelope permission **and** separate user approval for that exact task; force push, history rewrite, and destructive Git are never inferred. An external Work/GitHub trigger should first perform a read-only dry run against the current files and return `STOP: HOLD`. It must not launch the advisory next task merely because the envelope exists.

The decision-only consumer is `ruby scripts/automation_decision.rb` (`--self-test` runs isolated in-memory fixtures). A future GREEN candidate additionally needs a stable `task_id` in `NEXT_TASK.md` and `validation: {complete: true, passing: true, head: <current HEAD>, evidence: <nonempty reference>}` in the handoff. A trusted external controller must supply `--approval TRUSTED_PLAN.yml` with `approved_tasks` entries containing an exact task ID and SHA-256 digest of all machine-readable envelope fields, plus `max_tasks`, `tasks_completed`, `max_duration_minutes`, `started_at`, `expires_at`, and explicit false commit/push permissions. The consumer checks those fields, Git state, and protected-file exclusions but never dispatches. `LAUNCH_ALLOWED` is only a decision, not proof that an approval file came from a human or permission to start work without the trusted controller.

## Trusted approval and final pre-launch gate

The repository and a local `--approval` file cannot attest their own authority. A future controller must obtain a finite approval from an authenticated, user-authorized source outside this repository, verify its provenance there, and pass an independently verified receipt to the pre-launch gate. The receipt identifies the source/reference and binds the exact approval-plan digest and invocation digest. A self-declared `source_kind` or copied digest is not proof of approval; without an independent source verifier, the gate stops.

The invocation digest binds the task ID and full task digest, current HEAD, exact allowed and forbidden files, validation evidence for that HEAD, remaining task count and duration bounds, start/expiry times, and both task and approval commit/push permissions. Any change invalidates the receipt. Commit/push remain false in this GREEN-only contract; a future permission model needs separate explicit authorization and review.

Immediately before any future launch, re-read HEAD, Git/protected working-tree state, all three routing files, and the approval; compare them with the approved snapshot; re-run the decision gate using current time; confirm no new human decision or stale validation; and independently re-verify the receipt. A ready result is an exact task envelope, not dispatch. The present adapter can emit `PRELAUNCH_READY` only in isolated synthetic tests with an injected verifier. Its live `--prelaunch` invocation has no trusted receipt and must return `STOP: HOLD`. No launcher, external API, schedule, or task-start capability is provided.
