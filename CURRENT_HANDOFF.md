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
- FoodStore ADD-path durability commit: `c003f130e30b9bccae549691e21e00d3df3de303` (pushed to `origin/main`).
- Review Food V2 presentation commit: `97e050d6031de1e0fc6c0621a37444809c5d2e4e`.
- ChatView accessibility commit: `0a67b27c5393dcbac51e91197c8c3ebdb1dfa93b`.
- Cloud Backup presence fix commit: `3029cd375973291d034e4c0cae9d8fadcc3b5fd4`.
- FoodStore ADD, Review Food, ChatView, the three Data Integrity commits below, and the Cloud Backup fix were pushed normally to `origin/main`. Read Git for the current handoff-checkpoint HEAD SHA.
- Overall routing remains **HOLD**. The old `NEXT_TASK.md` pilot envelope is not authority for the current product work; its mismatch with this handoff fails closed.

## Last task
- Task: Checkpoint the independently validated FoodStore ADD-path durability correction.
- Status: **COMPLETE / GREEN** checkpoint. Repository routing remains **HOLD** for other active work.
- Summary: The four passing ADD tests were separated from the two intentionally red EDIT/REPLACE contracts without changing their assertions. The ADD-only source and test file were committed as `c003f130e30b9bccae549691e21e00d3df3de303` and pushed normally. Both unresolved contracts remain local in `ios/held-tests/FoodStoreEditReplacementContractTests.swift`, outside the synchronized test target. No EDIT/REPLACE behavior was implemented.

## Changes
- Committed `ios/calorietracker/Stores/FoodStore.swift`: private typed outcome (`rejectedBeforeWrite` versus `acceptedLocally(synchronized:)`), ADD-only refusal handling, and tracking/cleanup of ADD-created image files. Existing EDIT photo-deletion condition remains tied to synchronization success.
- Committed `ios/calorietrackerTests/FoodStoreDurabilityContractTests.swift`: four green ADD tests for valid reload/callbacks, rejected ADD callbacks/memory/reload, rejected ADD photo cleanup including an existing-photo filename collision, and local acceptance/callbacks after injected sync failure. No production seam was needed; a test-only `UserDefaults` subclass returns false from `synchronize()`.
- Preserved locally and uncommitted `ios/held-tests/FoodStoreEditReplacementContractTests.swift`: the two unchanged desired-contract assertions for failed pre-write EDIT and REPLACE. This file is outside the test target until the separate AMBER transaction task.
- Cloud Backup commit `3029cd375973291d034e4c0cae9d8fadcc3b5fd4` includes only `ios/calorietracker/Services/CloudBackupService.swift`, `ios/calorietracker/Views/CloudBackupSettingsView.swift`, and `ios/calorietrackerTests/CloudBackupPresenceTests.swift`.
- Data Integrity commits: `72dfdf6ec3614394f2f09da37993fb052676838e` (WeightStore chronology and its six tests), `aec7683223c2fc42c6cf6b807619c6f4218b27fd` (portion cap and its four tests), and `20a5f337d9fa0f84dc65a32000e4493eb7314e23` (DiaryImporter rejection tests). Other held work remains untouched.
- Review Food commit files: `ios/calorietracker/Views/FoodResultView.swift`, `ios/calorietracker/Views/ServingUnitEditor.swift`.
- Chat accessibility commit file: `ios/calorietracker/Views/ChatView.swift`.

## Validation
- ADD checkpoint rerun: `FoodStoreDurabilityContractTests` **4 named executions / 4 passed / 0 failed / 0 skipped**, Xcode exit **0**, readable result bundle. The adjacent `DiaryPersistenceSafetyTests.corruptFoodBlobIsPreservedAndAddIsRefusedUntilBackedUp()` ran separately: **1 named execution / 1 passed / 0 failed / 0 skipped**, exit **0**. An initial extra filter without Swift Testing's trailing `()` selected no adjacent test; it was not counted as validation. `git diff --check` and `git diff --cached --check` passed. The production `FoodStore.swift` SHA-256 remained `11af4cce059c9d95d37956a87fceda41933a7906158db687d48ed6af2f2e4e25`, matching the prior clean arm64 build candidate, so no new app build was run for this test-organization/checkpoint task.
- Baseline classification: on a clean detached worktree at `618b52f56896e98f95c0688279bad1dbd7f2777e`, the exact two selected `FoodPhotoRemovalTests` executed on the same iPhone 18 Pro iOS 27.0 Simulator: **2 executions / 0 passed / 2 failed / 0 skipped**, Xcode exit **65**, readable result bundle. `removingPrimaryPromotesNextPhotoWithoutResurrectingCachedBytes()` failed at line 51 (`reloaded.entries.first?.imageData` was nil, expected `"second"`); `missingFileDoesNotGiveTheNextPhotoItsRemovalID()` failed at line 146 (`reloaded.additionalImageData` was empty, expected `"surviving"`). These match the two local-slice assertion failures exactly. The baseline checkout was clean before and after the run and removed afterward. No broad suite or app build was run for this classification-only task.
- Current ADD slice: **4 named tests / 4 passed / 0 failed / 0 skipped**, genuine Xcode exit **0** and readable result. Adjacent `DiaryPersistenceSafetyTests` + `FoodPhotoRemovalTests`: **33 named tests / 31 passed / 2 failed / 0 skipped**, Xcode exit **65**; the exact two failures were reproduced on unchanged main as recorded above. Clean fresh-DerivedData arm64 Simulator app build: **exit 0**, **2 existing warnings** (`ExerciseCatalogWarmup.swift:16`, `RestaurantFoodSearchIndex.swift:102`). `git diff --check` passed; hashes of all six protected files, the scheme, and held Search Food test match their pre-task values.
- FoodStore durability proof: **5 named tests / 2 passed / 3 failed / 0 skipped**; Xcode exit **65**, readable result bundle. The three failures are expected evidence of current contract defects, not a green regression gate: add falsely reports success/publishes callbacks, replacement swaps memory/deletes the old photo/orphans a new photo, and edit publishes unsaved state/orphans a new photo after JSON encoding refusal. A valid add/reload passes. After injected `synchronize() == false`, a same-process reload sees the new value already set in `UserDefaults`; this does **not** prove disk durability or process-restart survival. No clean app build was required because app code was unchanged; the test target compiled and executed. `git diff --check` passed.
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
- User-approved ADD contract: a refusal before `UserDefaults.set` is failure with no accepted in-memory row or success callbacks; once `set` occurs, the ADD is locally accepted even if later `synchronize()` returns false. Do not roll it back based solely on sync failure. No retry UX or broader persistence framework was added.
- EDIT/REPLACE/DELETE/combine/import/cloud-merge still need separate transaction and image-lifecycle work. The two EDIT/REPLACE desired-contract tests from the prior proof were not selected as ADD acceptance and remain red by design.
- `saveEntries()` has two different false paths: `PersistedBlobGuard.save` may refuse before `UserDefaults.set` (unbacked corrupt blob or encoding failure), whereas `synchronize()` can return false **after** `set` and the guard's observed blob changed. Therefore false does not imply rollback is safe. Apple documents `synchronize()` as waiting for pending defaults updates and returning false when disk save fails; it is not a per-entry transaction.
- ADD now treats a pre-write refusal as failure without success callbacks and treats post-`set` sync failure as locally accepted, per the explicit task approval. REPLACE/EDIT/DELETE should keep old rows and photos recoverable until their replacement is accepted; their transaction and callback rules remain a separate AMBER design/implementation boundary.
- Missing automated UI execution was not treated as a pass. The independent presentation/accessibility commits are checkpointed on clean compilation, source-diff review, and the stated manual Review Food evidence, with the untested configurations and VoiceOver limitation explicit.
- A selected Search Food suggestion still uses its stable dataset identity; the test-only interaction correction is held until its named tests execute.

## Known issues / risks
- The Cloud Backup enable-flow presence failure is closed, but `upload` separately treats a record prefetch failure as a new-record attempt; overwrite/data-loss consequences are not established and were not changed.
- ADD's proven pre-write bug is corrected and pushed. Its four focused tests and the adjacent add-refusal test passed; the two adjacent photo-removal failures are **PRE_EXISTING_FAILURE** on unchanged `618b52f56896e98f95c0688279bad1dbd7f2777e`, not regressions from the ADD slice. The two intentionally red EDIT/REPLACE contracts remain local outside the test target and must not be treated as passing. EDIT/REPLACE and delete/combine/import/cloud merge can still mutate memory/callbacks or images before acceptance. The post-`set` sync-failure test proves local visibility, not process-restart disk durability. Replacement/image transaction implementation remains **AMBER** because it needs staged image ownership, rollback ordering, and broader callback coordination; no automatic continuation.
- The targeted Simulator restart restored two unit-test worker launches, but it is not a proven permanent fix. Search Food XCUITest startup and finalization still require a bounded named-test verdict before that held test slice can be accepted.
- Search Food XCUITest worker startup/finalization is unreliable. Do not weaken identity assertions or infer automated acceptance from manual taps.
- Review Food mixed-source/photo layouts and the shared serving editor in Edit Food Entry need later manual checks; the accepted examples do not cover them.
- ChatView labels need later VoiceOver judgment; idle-mic semantics were not changed.
- Search Food `protein bar`/reordered-token discovery needs a product decision before changing the conservative whole-query boundary. The restaurant-index initialization warning/performance path needs separate ownership evidence.
- Home-dashboard macro-card wrapping at large text and catalog line-16 concurrency ownership remain separate backlog items.

## Protected working-tree changes
- Preserve the existing unrelated edits to `ios/calorietracker.xcodeproj/project.pbxproj`, `ios/calorietracker/Info.plist`, `ios/calorietracker/InfoPlist.xcstrings`, `ios/calorietracker/LocalModels.xcstrings`, `ios/calorietracker/Localizable.xcstrings`, and `ios/calorietracker/WeeklyChallenge.xcstrings`.
- Preserve the separate `ios/calorietracker.xcodeproj/xcshareddata/xcschemes/calorietracker.xcscheme` edit. All seven contents, plus the held Search Food test, were hash-checked unchanged during this ADD checkpoint. None was staged, committed, reset, stashed, or modified.

## Git state
- FoodStore ADD source/test checkpoint `c003f130e30b9bccae549691e21e00d3df3de303` was pushed normally. Only those two files were included. A separate handoff-only checkpoint records this state; no other task work was staged.
- Current uncommitted task work: `ios/held-tests/FoodStoreEditReplacementContractTests.swift` (two unresolved desired contracts). The held Search Food test, all six protected edits, and the scheme retained their pre-task hashes.
- Earlier pushed checkpoints: Review Food and ChatView, then the three exact Data Integrity commits listed above and their handoff checkpoint.
- The Cloud Backup source/test commit above and its earlier handoff-only commit were pushed normally to `origin/main`. This FoodStore handoff update is a separate documentation checkpoint; no history was rewritten.
- Intentionally uncommitted: `ios/calorietrackerUITests/SearchFoodAcceptanceUITests.swift` remains a separate HOLD slice with 0 named executions.
- Unrelated/protected modifications: the six files and scheme listed above. No staged files.

## Recommended next task
Define the separate EDIT/REPLACE image-transaction contract before implementation, including rollback ordering, callbacks, and old/new photo ownership; then validate the two preserved red tests as part of that bounded AMBER task. Do not treat the unrelated pre-existing photo tests as an ADD regression.

## Human decision required
The user approved local acceptance after `set` for this ADD slice, so that decision is resolved here; process-restart durability after a false sync remains unproven. Before changing replacement/import/delete transaction behavior, confirm callback and old/new image retention rules for those broader paths. Separately, before broadening reordered-token Search Food discovery (for example `protein bar`), decide what positive whole-food identity evidence is required without promoting a component of a composed meal. Neither is permission to start work automatically.
