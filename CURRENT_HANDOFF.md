---
schema_version: 1
state: HOLD
risk_lane: RED
last_task_status: COMPLETE
last_task_risk_lane: AMBER
auto_start_allowed: false
human_decision_required: true
next_task_envelope: NEXT_TASK.md
validation_evidence_ref: "#validation"
---

# FOOD AI — Current Handoff

## Current checkpoint
- Branch: `main`.
- Review Food V2 presentation commit: `97e050d6031de1e0fc6c0621a37444809c5d2e4e`.
- ChatView accessibility commit: `0a67b27c5393dcbac51e91197c8c3ebdb1dfa93b`.
- Both scoped commits were pushed normally to `origin/main`. This handoff is a separate documentation checkpoint; read Git for its own HEAD SHA after publication.
- Overall routing remains **HOLD**. The old `NEXT_TASK.md` pilot envelope is not authority for the current product work; its mismatch with this handoff fails closed.

## Last task
- Task: Classify and checkpoint independently validated uncommitted slices without implementing product functionality.
- Status: **COMPLETE** for the two scoped commits; unresolved Search Food tests, portion tests, and protected changes remain local. No automated task may start.
- Summary: Review Food V2 and ChatView accessibility were committed separately. Search Food UI-test edits and unexecuted PortionSuggestionPolicy tests were deliberately excluded.

## Changes
- Review Food commit files: `ios/calorietracker/Views/FoodResultView.swift`, `ios/calorietracker/Views/ServingUnitEditor.swift`.
- Chat accessibility commit file: `ios/calorietracker/Views/ChatView.swift`.
- Handoff-only documentation change: `CURRENT_HANDOFF.md`. No new app files, nutrition values, serving calculations, resolver behavior, Search Food product code, or automation tooling changed in this consolidation task.

## Validation
- Clean arm64 iOS Simulator app build after staging the production slice: **exit 0**, **0 errors**, **2 existing app warnings** (`ExerciseCatalogWarmup.swift:16`, `RestaurantFoodSearchIndex.swift:102`). The build included both Review Food and ChatView working-tree source.
- Review Food: user-reported normal Simulator taps retained the exact Cavendish, Big Mac, and six-piece McNuggets identities. User-reported manual visual/layout review passed for those tested AUSNUT/verified examples in light/dark mode and normal/accessibility text, including the corrected serving and nutrition rows. Mixed-source and photo configurations did **not** receive equivalent manual coverage.
- ChatView: staged diff contains six accessibility labels and one photo-menu hint only; no layout, gesture, voice, or chat-logic change. No runtime VoiceOver acceptance. The idle microphone remains intentionally unchanged.
- Search Food UI tests: revised exact stable-ID button taps retain strict identity assertions, but the XCUITest worker stalled before named execution. **0 executed / 0 passed / 0 failed / 0 skipped** for the revised journeys. Manual product journeys do not validate test interaction.
- PortionSuggestionPolicy tests: four focused tests exist, but **0 named executions**; the policy fix was not made.
- Staged diffs for both source commits were inspected, staged file lists were exact, and `git diff --cached --check` passed before each commit. No XCUITest or unit-test run was attempted during consolidation.

## Architecture decisions
- Missing automated UI execution was not treated as a pass. The independent presentation/accessibility commits are checkpointed on clean compilation, source-diff review, and the stated manual Review Food evidence, with the untested configurations and VoiceOver limitation explicit.
- A selected Search Food suggestion still uses its stable dataset identity; the test-only interaction correction is held until its named tests execute.

## Known issues / risks
- Search Food XCUITest worker startup/finalization is unreliable. Do not weaken identity assertions or infer automated acceptance from manual taps.
- Review Food mixed-source/photo layouts and the shared serving editor in Edit Food Entry need later manual checks; the accepted examples do not cover them.
- ChatView labels need later VoiceOver judgment; idle-mic semantics were not changed.
- PortionSuggestionPolicy may suggest above its maximum; its tests have not executed, so that work remains HOLD.
- Search Food `protein bar`/reordered-token discovery needs a product decision before changing the conservative whole-query boundary. The restaurant-index initialization warning/performance path needs separate ownership evidence.
- Home-dashboard macro-card wrapping at large text and catalog line-16 concurrency ownership remain separate backlog items.

## Protected working-tree changes
- Preserve the existing unrelated edits to `ios/calorietracker.xcodeproj/project.pbxproj`, `ios/calorietracker/Info.plist`, `ios/calorietracker/InfoPlist.xcstrings`, `ios/calorietracker/LocalModels.xcstrings`, `ios/calorietracker/Localizable.xcstrings`, and `ios/calorietracker/WeeklyChallenge.xcstrings`.
- Preserve the separate `ios/calorietracker.xcodeproj/xcshareddata/xcschemes/calorietracker.xcscheme` edit. All seven contents were hash-checked unchanged across both source commits. None was staged, committed, reset, stashed, or modified by this task.

## Git state
- Committed and pushed: the two exact source commits above, followed by this handoff-only checkpoint. No force push, rebase, reset, or history rewrite.
- Intentionally uncommitted: `ios/calorietrackerUITests/SearchFoodAcceptanceUITests.swift` (strict-ID test interaction plus Review Food screenshot/assertion additions) and untracked `ios/calorietrackerTests/PortionSuggestionPolicyTests.swift`.
- Unrelated/protected modifications: the six files and scheme listed above. No other staged source/test file remains after the two commits.

## Recommended next task
Run one bounded investigation of XCUITest worker startup, then execute only the three strict Banana, Big Mac, and six-nuggets journeys if the worker becomes reliable. Keep the unexecuted test edits uncommitted until a trustworthy named-test verdict exists.

## Human decision required
Before broadening reordered-token Search Food discovery (for example `protein bar`), decide what positive whole-food identity evidence is required without promoting a component of a composed meal. This is not permission to start that work automatically.
