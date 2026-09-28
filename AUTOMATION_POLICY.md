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

`CURRENT_HANDOFF.md` records the repository continuation gate (`state`), the proposed next task's `risk_lane`, the last task's status/lane, historical validation notes, and the next-task envelope reference. `NEXT_TASK.md` is advisory, not authorization. Its `state` must match the handoff gate. A completed documentation task can coexist with a repository `HOLD`. Neither file may contain a machine-readable validation receipt for its own HEAD: committing that SHA would change HEAD.

Repository routing is **eligible for approval**, not launch, only when **both** files say `state: COMPLETE`, both say `risk_lane: GREEN`, both explicitly say `auto_start_allowed: true`, `human_decision_required: false`, and Git/protected files are safe. This yields `READY_FOR_APPROVAL` without a dispatch envelope. `HOLD`, `BLOCKED`, `DECISION_REQUIRED`, AMBER, and RED always stop. Flaky or incomplete external validation, a protected-file write/conflict, scope expansion, or a human/product choice prevents pre-launch readiness; do not relabel such work GREEN merely to obtain a ready decision.

No envelope may authorize commit or push by default. Either action requires an explicit envelope permission **and** separate user approval for that exact task; force push, history rewrite, and destructive Git are never inferred. An external Work/GitHub trigger should first perform a read-only dry run against the current files and return `STOP: HOLD`. It must not launch the advisory next task merely because the envelope exists.

The decision-only consumer is `ruby scripts/automation_decision.rb` (`--self-test` runs isolated fixtures). A GREEN candidate needs a stable `task_id` in `NEXT_TASK.md`. Its task digest covers all machine-readable envelope fields. It checks routing consistency, Git state, and protected-file exclusions, but does not accept a repository-local approval file or claim validation passed. The dry-run adapter likewise returns `READY_FOR_APPROVAL` without an envelope. Neither tool dispatches.

## External validation, human approval, and final pre-launch gate

After a routing checkpoint is pushed, a trusted controller must independently validate that exact remote HEAD and supply a receipt **outside the repository**. The receipt binds HEAD, task ID/digest (including file scope), objectively passing results and evidence, dirty/protected-file content fingerprints, one or more finite task/time bounds, UTC validation time, expiry, and a source reference. The pre-launch gate requires an independently injected verifier for this receipt; a self-declared receipt is not proof. The repo-only stage cannot turn an incomplete validation into a pass.

Separately, the authenticated human GitHub approval binds the same final HEAD and task digest. Its derived plan has exact task count/time bounds and false commit/push permissions. The authenticated approval receipt binds that plan and the validation-receipt digest to the invocation. Both source verifiers must pass, and both receipts must remain unexpired. A local JSON copy, webhook payload, or copied digest alone is not approval.

Immediately before any future launch, re-read HEAD, Git/protected working-tree state, and all three routing files; compare them with the approved snapshot; re-run the repo gate; re-verify **both** external sources against current time; then fetch `refs/heads/main` from `origin` and require that fresh remote HEAD to equal the approved HEAD. A ready result is an exact task envelope, not dispatch. The present adapter emits `PRELAUNCH_READY` only in isolated fixtures with injected verifiers and a remote-HEAD reader. Its live `--prelaunch` invocation has neither receipt and must return `STOP: HOLD`. No launcher, schedule, or task-start capability is provided.

## GitHub-comment GREEN pilot (verification only)

The single proposed pilot is `routing-doc-consistency-audit`: read the routing docs and automation scripts, report contradictions, and make **zero** writes, commits, pushes, or dispatches. It is limited to one task and 15 minutes. The current `NEXT_TASK.md` remains HOLD/AMBER; this pilot is only an isolated GREEN fixture, not an approved live task. Any eventual launcher must enforce a read-only filesystem even though the existing `allowed_files` field lists the files in scope.

The designated human's numeric GitHub user ID, issue number, and comment ID must come from trusted controller configuration—not an issue body, repo file, environment guess, or Git author. The controller fetches that exact issue comment from the authenticated GitHub API under `unukaaa/fud-ai`; it checks the numeric author ID, human `User` type, repository/issue/comment URLs, creation time, REST update time, and GraphQL `lastEditedAt`. Missing/edited comments, API errors, or uncertain metadata fail closed. It re-fetches the comment during the final pre-launch gate. A local JSON copy or webhook payload alone is not an approval.

The human approval comment must contain exactly these seven lines, with no Markdown fence, extra prose, or `true` permissions (one final newline is optional):

```text
FOOD-AI GREEN APPROVAL v1
task_id: routing-doc-consistency-audit
task_digest: <64 lowercase hex characters for the exact GREEN envelope>
head: <40 lowercase hex characters for current main HEAD>
expires_at: <UTC ISO-8601 timestamp, no later than 15 minutes after comment creation>
commit_allowed: false
push_allowed: false
```

The verifier derives a one-task, 15-minute, no-commit/no-push plan from the unedited comment. It can reach `APPROVAL_VERIFIED` / `PRELAUNCH_READY` only with the **separate trusted validation receipt** and a fresh matching remote HEAD. These are dry-run states only. No designated approver or issue/comment is configured, no real GitHub approval has been fetched, and no launcher exists.
