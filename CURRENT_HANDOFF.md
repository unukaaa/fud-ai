---
schema_version: 1
state: HOLD
risk_lane: RED
last_task_status: COMPLETE
last_task_risk_lane: GREEN
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
- Cloud Backup presence fix commit: `3029cd375973291d034e4c0cae9d8fadcc3b5fd4`.
- Review Food, ChatView, the three Data Integrity commits below, and the Cloud Backup fix were pushed normally to `origin/main`. Read Git for the current handoff-checkpoint HEAD SHA.
- Overall routing remains **HOLD**. The old `NEXT_TASK.md` pilot envelope is not authority for the current product work; its mismatch with this handoff fails closed.

## Last task
- Task: Checkpoint the validated Cloud Backup presence fix only.
- Status: **COMPLETE / GREEN** for this Git-only checkpoint; overall repository routing remains **HOLD**. FoodStore durability remains **HOLD / AMBER**.
- Summary: The three-file Cloud Backup fix was committed and pushed separately from this handoff. No FoodStore implementation or other product work was done.

## Changes
- Cloud Backup commit `3029cd375973291d034e4c0cae9d8fadcc3b5fd4` includes only `ios/calorietracker/Services/CloudBackupService.swift`, `ios/calorietracker/Views/CloudBackupSettingsView.swift`, and `ios/calorietrackerTests/CloudBackupPresenceTests.swift`. This handoff is a separate documentation checkpoint. FoodStore remains unchanged.
- Data Integrity commits: `72dfdf6ec3614394f2f09da37993fb052676838e` (WeightStore chronology and its six tests), `aec7683223c2fc42c6cf6b807619c6f4218b27fd` (portion cap and its four tests), and `20a5f337d9fa0f84dc65a32000e4493eb7314e23` (DiaryImporter rejection tests). Other held work remains untouched.
- Review Food commit files: `ios/calorietracker/Views/FoodResultView.swift`, `ios/calorietracker/Views/ServingUnitEditor.swift`.
- Chat accessibility commit file: `ios/calorietracker/Views/ChatView.swift`.

## Validation
- Cloud Backup baseline: **3 named tests / 2 passed / 1 failed / 0 skipped**. The injected lookup error was swallowed and changed prior presence to false. Corrected presence plus adjacent archive suites: **6 named tests / 6 passed / 0 failed / 0 skipped**, genuine Xcode exit 0. Clean arm64 Simulator app build: **exit 0**, **2 existing warnings** (`ExerciseCatalogWarmup.swift:16`, `RestaurantFoodSearchIndex.swift:102`). `git diff --check` passed.
- Checkpoint: the exact Cloud Backup staged file list and diff were inspected; `git diff --cached --check` passed. No tests or build were rerun for this Git-only checkpoint; the validated source/test content was committed unchanged.
- FoodStore Task 2 was read-only: **0 new test executions** and no second build. Code inspection established the ignored-save and pre-save image-deletion paths; no runtime persistence-failure fixture was added because the rollback/durability contract is unresolved.
- WeightStore baseline: **6 named executions / 4 passed / 2 failed / 0 skipped**. Both failures were the expected backdated loss/gain false notifications (`count` was 1, expected 0). After correction: **6/6 passed, 0 failed, 0 skipped**. Adjacent WeightStore persistence/import tests: **2/2 passed, 0 failed, 0 skipped**. All counts came from readable result bundles and genuine test execution.
- Clean arm64 iOS Simulator app build after the WeightStore correction: **exit 0**, **0 errors**, **2 distinct existing app warnings** (`ExerciseCatalogWarmup.swift:16`, `RestaurantFoodSearchIndex.swift:102`). `git diff --check` passed; production diff is limited to the goal-notification comparison.
- PortionSuggestionPolicy baseline: **4 named executions / 2 passed / 2 failed / 0 skipped**. Zero-budget suggestion was `0.05` above maximum `0`; tiny-budget suggestion was `0.1` above maximum `0`. After the one-line correction: **4/4 passed, 0 failed, 0 skipped**. No separate directly relevant surrounding policy suite exists.
- Second clean arm64 iOS Simulator app build after the portion correction: **exit 0**, **0 errors**, the same **2 distinct existing app warnings**. `git diff --check` passed; production changes remain confined to WeightStore and PortionSuggestionPolicy.
- DiaryImporter suite after four test-only additions: **7 named executions / 7 passed / 0 failed / 0 skipped** (four new rejection/boundary tests plus three existing valid-import tests). The exact 20 MiB whitespace payload reached document validation and was rejected as invalid JSON; the 20 MiB + 1 byte payload was rejected by the size gate. No new app build was needed after this test-only change. Final `git diff --check` passed.
- Checkpoint verification: each logical staged diff and exact file list were inspected; `git diff --cached --check` passed before each commit. No tests or builds were rerun during this Git-only checkpoint; the results above belong to the unchanged committed diffs.
- Review Food: user-reported normal Simulator taps retained the exact Cavendish, Big Mac, and six-piece McNuggets identities. User-reported manual visual/layout review passed for those tested AUSNUT/verified examples in light/dark mode and normal/accessibility text, including the corrected serving and nutrition rows. Mixed-source and photo configurations did **not** receive equivalent manual coverage.
- ChatView: the committed diff contains six accessibility labels and one photo-menu hint only; no layout, gesture, voice, or chat-logic change. No runtime VoiceOver acceptance. The idle microphone remains intentionally unchanged.
- Search Food UI tests: revised exact stable-ID button taps retain strict identity assertions, but the XCUITest worker stalled before named execution. **0 executed / 0 passed / 0 failed / 0 skipped** for the revised journeys. Manual product journeys do not validate test interaction.

## Architecture decisions
- Missing automated UI execution was not treated as a pass. The independent presentation/accessibility commits are checkpointed on clean compilation, source-diff review, and the stated manual Review Food evidence, with the untested configurations and VoiceOver limitation explicit.
- A selected Search Food suggestion still uses its stable dataset identity; the test-only interaction correction is held until its named tests execute.

## Known issues / risks
- The Cloud Backup enable-flow presence failure is closed, but `upload` separately treats a record prefetch failure as a new-record attempt; overwrite/data-loss consequences are not established and were not changed.
- FoodStore `saveEntries()` conflates a refused blob write with a later `UserDefaults.synchronize()` failure after `defaults.set`; callers cannot safely infer whether a false result means no write occurred. `addEntry`, `deleteEntry`, `combineIntoMeal`, `replaceAllEntries`, import replacement, and cloud merge ignore that result in different ways. `replaceAllEntries` and other removal paths can delete old images before persistence succeeds. Existing tests cover initial corruption blocking, not a write-time failure after a store starts healthy. **HOLD / AMBER** until rollback, callback, and image-cleanup ordering are specified and failure-tested.
- The targeted Simulator restart restored two unit-test worker launches, but it is not a proven permanent fix. Search Food XCUITest startup and finalization still require a bounded named-test verdict before that held test slice can be accepted.
- Search Food XCUITest worker startup/finalization is unreliable. Do not weaken identity assertions or infer automated acceptance from manual taps.
- Review Food mixed-source/photo layouts and the shared serving editor in Edit Food Entry need later manual checks; the accepted examples do not cover them.
- ChatView labels need later VoiceOver judgment; idle-mic semantics were not changed.
- Search Food `protein bar`/reordered-token discovery needs a product decision before changing the conservative whole-query boundary. The restaurant-index initialization warning/performance path needs separate ownership evidence.
- Home-dashboard macro-card wrapping at large text and catalog line-16 concurrency ownership remain separate backlog items.

## Protected working-tree changes
- Preserve the existing unrelated edits to `ios/calorietracker.xcodeproj/project.pbxproj`, `ios/calorietracker/Info.plist`, `ios/calorietracker/InfoPlist.xcstrings`, `ios/calorietracker/LocalModels.xcstrings`, `ios/calorietracker/Localizable.xcstrings`, and `ios/calorietracker/WeeklyChallenge.xcstrings`.
- Preserve the separate `ios/calorietracker.xcodeproj/xcshareddata/xcschemes/calorietracker.xcscheme` edit. All seven contents, plus the held Search Food test, were hash-checked unchanged across the Cloud Backup checkpoint. None was staged, committed, reset, stashed, or modified.

## Git state
- Earlier pushed checkpoints: Review Food and ChatView, then the three exact Data Integrity commits listed above and their handoff checkpoint.
- The Cloud Backup source/test commit above and this handoff-only commit were pushed normally to `origin/main`. Read Git for the current handoff-checkpoint HEAD SHA; no history was rewritten.
- Intentionally uncommitted: `ios/calorietrackerUITests/SearchFoodAcceptanceUITests.swift` remains a separate HOLD slice with 0 named executions.
- Unrelated/protected modifications: the six files and scheme listed above. No staged files.

## Recommended next task
Separately approve a focused FoodStore persistence-contract design/test-seam task: distinguish refused writes from post-write synchronization uncertainty, define rollback and callback behavior, and defer old-image deletion until the new state is safely committed. Do not implement or auto-start from this handoff.

## Human decision required
FoodStore durability needs an explicit decision on how to handle a failed `synchronize()` after `defaults.set` and how memory, HealthKit callbacks, and image cleanup should roll back or reconcile. Separately, before broadening reordered-token Search Food discovery (for example `protein bar`), decide what positive whole-food identity evidence is required without promoting a component of a composed meal. Neither is permission to start work automatically.
