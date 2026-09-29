---
schema_version: 1
state: HOLD
risk_lane: AMBER
last_task_status: COMPLETE
last_task_risk_lane: AMBER
auto_start_allowed: false
human_decision_required: true
next_task_envelope: NEXT_TASK.md
validation_evidence_ref: "#validation"
---

# FOOD AI — Current Handoff

## Current checkpoint
- Branch: `main`; the FoodStore commit `e6e06b1af` is pushed. Verify the final handoff-checkpoint HEAD from Git rather than embedding a self-referential SHA here.
- Current development phase: FoodStore EDIT/REPLACE durability and rejected-write UI acceptance are checkpointed in `e6e06b1af`; Search Food automated acceptance and other durability paths remain separate HOLD work.
- The repo-wide routing state remains HOLD. `NEXT_TASK.md` is not authority to launch another task.

## Last task
- Task: Checkpoint the validated FoodStore EDIT/REPLACE durability slice.
- Status: **COMPLETE**. Commit `e6e06b1af` contains only the seven inspected FoodStore implementation/contract/runtime-test files and was pushed normally; this handoff is a separate documentation checkpoint. Repository-wide routing remains HOLD.
- Summary: Pre-write rejection preserves old accepted food/photos and suppresses success callbacks; accepted local writes retain new state despite a false `synchronize()`. Mounted UI acceptance proved rejected edit stays open with an error and rejected import retains its preview without applying water or success callbacks.

## Changes
- Commit `e6e06b1af` includes `FoodStore.swift`, `EditFoodEntryView.swift`, `ImportDiaryView.swift`, `calorietrackerApp.swift`, `FoodStoreEditReplacementContractTests.swift`, `FoodStoreRejectionAcceptanceHarness.swift`, and `FoodStoreRejectedMutationUITests.swift` (under their existing `ios/` paths).
- `FoodEntryMutationResult` distinguishes rejected pre-write mutations from locally accepted ones. Rejected edit/replacement rolls back memory and new unreferenced photos; accepted mutation removes only obsolete unreferenced photos. Editor/import callers show failure rather than dismissing or reporting success.
- The one-shot refusal seam, isolated in-memory harness, preview initializer, and launch route are `#if DEBUG`/test-only; the hook resets after use and has no persistent setting. They remain as focused regression coverage, not release behavior.
- No nutrition, schema, Search Food, Review Food, ChatView, Cloud Backup, automation, project, scheme, or localization behavior was changed.

## Validation
- Baseline before production correction: **10 named tests executed; 6 passed, 4 failed, 0 skipped**, Xcode exit 65. Expected failures: rejected edit, rejected replacement, rejected import, and in-place overwrite of an edited photo. Readable `/private/tmp/FoodStoreEditReplacementExpandedBaseline-20260929.xcresult`.
- Final EDIT/REPLACE contracts: **13 named tests executed; 13 passed, 0 failed, 0 skipped**, Xcode exit 0. Includes direct acceptance results, rejected callbacks/import callbacks, accepted local sync-failure results, and shared diary/favorite photo protection. Readable `/private/tmp/FoodStoreEditReplacementFinal-20260929.xcresult`.
- Committed ADD durability contract rerun independently: **4 named tests executed; 4 passed, 0 failed, 0 skipped**, Xcode exit 0. Readable `/private/tmp/FoodStoreAddAfterEditReplace-20260929.xcresult`.
- Mounted rejected-write UI acceptance: **2 named XCUITests executed; 2 passed, 0 failed, 0 skipped**, Xcode exit 0. The real Edit Food and Import Diary views showed the expected errors and remained open; isolated old food/water and callback assertions passed. Readable `/private/tmp/FoodStoreRejectedMutationUI-20260929.xcresult`; retained screenshots were exported to `/private/tmp/FoodStoreRejectedMutationUI-20260929-attachments/` and visually inspected.
- After the DEBUG hook, focused EDIT/REPLACE + ADD contracts: **17 named tests executed; 17 passed, 0 failed, 0 skipped**, Xcode exit 0. Readable `/private/tmp/FoodStoreRejectedMutationPostHookLogic-20260929.xcresult`.
- Adjacent ADD/persistence/photo suites: **37 selected tests; 35 passed, 2 failed, 0 skipped**, Xcode exit 65. The only failures are `FoodPhotoRemovalTests.removingPrimaryPromotesNextPhotoWithoutResurrectingCachedBytes()` and `missingFileDoesNotGiveTheNextPhotoItsRemovalID()` with the same raw-image-byte assertions previously reproduced on unchanged committed main. ADD durability tests remained green. Readable `/private/tmp/FoodStoreEditReplacementAdjacent-20260929.xcresult`.
- Fresh-DerivedData arm64 iOS Simulator app build: **exit 0**, app artifact present, with **2 existing app warnings** at `ExerciseCatalogWarmup.swift:16` and `RestaurantFoodSearchIndex.swift:102`. Xcode also printed a contradictory generic `error: ... exit code 0` diagnostic; it did not fail the build. Build log: `/private/tmp/FoodStoreEditReplacementBuild-20260929.log`.
- After the DEBUG hook, another fresh-DerivedData arm64 iOS Simulator app build: **exit 0**, app artifact present, with the same **2 existing app warnings**. No physical-device or VoiceOver acceptance was claimed.
- During checkpoint, the exact seven-file staged diff was inspected; `git diff --cached --check` passed. The staged candidate was byte-identical to the validated working-tree files, so tests/build were not rerun. No physical-device acceptance was claimed.

## Architecture decisions
- A refusal before `UserDefaults.set` is not an accepted mutation. A false `synchronize()` after `set` is still locally accepted; tests prove same-process visibility, not process-restart disk durability.
- Photos are prepared without overwriting an existing file. On refusal, only newly created files with no remaining accepted diary/favorite reference are removed. On acceptance, obsolete old files are removed only if no accepted reference remains.
- HealthKit import callbacks are downstream of accepted food replacement. No new persistence framework or migration was introduced.

## Known issues / risks
- The two adjacent raw-image-byte photo-removal tests remain pre-existing failures; do not change them as part of this slice.
- `deleteEntry`, `combineIntoMeal`, and cloud merge have separate unaddressed transaction/callback risks. Full-data deletion has distinct destructive semantics and was not altered.
- Rejected-save presentation was exercised in mounted UI tests, but not on a physical device. Sync-failure tests do not establish disk durability across process restart.
- Search Food exact-ID XCUITest interaction remains HOLD with 0 named executions for the held test edit. Review Food mixed-source/photo layouts and ChatView VoiceOver judgment remain separate limitations.
- Cloud Backup upload record-prefetch behavior remains a separate unproven risk. The two existing app warnings are unrelated.

## Protected working-tree changes
- Preserve untouched: `ios/calorietracker.xcodeproj/project.pbxproj`, `ios/calorietracker/Info.plist`, `ios/calorietracker/InfoPlist.xcstrings`, `ios/calorietracker/LocalModels.xcstrings`, `ios/calorietracker/Localizable.xcstrings`, and `ios/calorietracker/WeeklyChallenge.xcstrings`.
- Preserve untouched: `ios/calorietracker.xcodeproj/xcshareddata/xcschemes/calorietracker.xcscheme` and `ios/calorietrackerUITests/SearchFoodAcceptanceUITests.swift`.

## Git state
- FoodStore durability commit `e6e06b1af` was pushed normally to `origin/main`. This handoff is committed separately; no history was rewritten.
- Intentionally uncommitted: the held `SearchFoodAcceptanceUITests.swift` edit (0 named executions), six protected edits, and scheme edit. Their hashes match the pre-checkpoint values; no other task work remains staged or uncommitted.

## Recommended next task
- Run one bounded, identity-strict Search Food XCUITest acceptance attempt for the held test-only change when its worker is healthy. Keep separate FoodStore DELETE/combine/cloud-merge transaction risks outside that task.

## Human decision required
- No new product decision was needed for this checkpoint. Other HOLD paths require separate authorization; automatic continuation is not permitted.
