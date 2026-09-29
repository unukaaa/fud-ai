---
schema_version: 1
state: HOLD
risk_lane: AMBER
last_task_status: COMPLETE
last_task_risk_lane: AMBER
auto_start_allowed: false
human_decision_required: false
next_task_envelope: NEXT_TASK.md
validation_evidence_ref: "#validation"
---

# FOOD AI — Current Handoff

## Current checkpoint
- Branch: `main`; Today shortcut commit `e85c4a01b0843576bbb817f3bd7d8e82f67984be` is pushed to `origin/main`. Verify this handoff-only checkpoint HEAD from Git rather than embedding its own SHA here.
- Current development phase: Today “Recent foods” shortcut is checkpointed after automated, build, and user-reported Simulator acceptance. Search Food identity-strict XCUITest acceptance remains a separate HOLD.
- Repository routing remains HOLD / AMBER. `NEXT_TASK.md` is advisory, not authority to launch another task.

## Last task
- Task: Checkpoint the accepted compact Today “Recent foods” shortcut and focused repeat-log tests.
- Status: **COMPLETE**. The two-file feature slice was committed as `e85c4a01b0843576bbb817f3bd7d8e82f67984be` and pushed normally. The repository-wide routing state remains HOLD for separate work.
- Summary: A single compact “Recent foods” button replaces the Log again header, Browse saved action, and latest-food preview. It opens the existing Recent list. When the 30-day Recent list is empty, the shortcut is omitted. Selecting a Recent row still copies the exact saved food and opens Review Food before saving.

## Changes
- Feature commit `e85c4a01b`: `ios/calorietracker/ContentView.swift` adds one native Today “Recent foods” row and retains the shared Recent-to-Review setup; new `ios/calorietrackerTests/TodayLogAgainTests.swift` covers eligibility, exact saved-entry identity, repeat-copy serving/provenance/date, isolation, empty history, and single-submit gate.
- This `CURRENT_HANDOFF.md` update is a separate documentation-only checkpoint. No other files were committed.

## Validation
- Focused named Swift Testing execution after revision: **14/14 passed, 0 failed, 0 skipped** across `TodayLogAgainTests` (6) and `SavedNutritionSourceRoundTripTests` (8); `xcodebuild test` exit 0 and readable `.xcresult` summary.
- Clean, fresh-DerivedData arm64 iOS Simulator app build: **exit 0**. App warning count **2**, both pre-existing and outside this task (`ExerciseCatalogWarmup.swift:16`, `RestaurantFoodSearchIndex.swift:102`).
- `git diff --check` and feature `git diff --cached --check`: passed; exact two-file staged diff inspected before commit.
- User-reported normal-text Simulator acceptance of the final row: one compact control between macro summary and Today’s meals, materially less vertical space, Recent navigation, exact McDonald’s Big Mac Review Food identity, verified source and McDonald’s Australia detail, **557 Cal, P24.6 C44.9 F29.4**. Earlier manual Cavendish repeat check confirmed AUSNUT source/serving/nutrition, selected Today date, Cancel logging nothing, and Add creating one entry.
- User-reported large-text Simulator acceptance: shortcut remains readable, touch/navigation affordance clear, no pathological wrapping, and Today hierarchy understandable. These are human observations, not agent-run XCUITests or physical-device validation.
- Historical source persistence checkpoint remains separately validated: 8/8 provenance tests and 31/31 adjacent persistence/meal tests previously passed; Big Mac and AUSNUT Cavendish saved/reopened source truth was user-accepted in Simulator. This task did not change that contract.

## Architecture decisions
- The Today shortcut appears only when `FoodStore.recentEntries(days: 30)` is nonempty and routes to `.recent`; it does not select or preview a food. Recent ordering and contents remain unchanged.
- Reuse `duplicatedForLogging(at:)` and `analysisForRepeatReview()` from the existing Recent row path so Review Food remains authoritative for serving, meal/date, nutrition, media, and historical source. The Review Food Add action remains the commit point.
- One native Button replaces two actions and the full preview, with a minimum 44-point label height, native readable text style, and VoiceOver hint. No Liquid Glass was added.

## Known issues / risks
- The Recent shortcut is accepted in the current Simulator, but no XCUITest was run for it. Unit tests cover eligibility and copy/source semantics, not mounted SwiftUI navigation. The pre-existing home macro-card Dynamic Type wrapping is a separate backlog issue, not caused by this slice.
- Search Food exact-ID XCUITest acceptance remains HOLD: local test-only edit has 0 named executions. This does not alter user-accepted normal taps.
- Mixed-source/photo Review Food layouts and ChatView VoiceOver judgment lack equivalent manual acceptance. Two raw-image-byte photo-removal tests are pre-existing failures. FoodStore delete/combine/cloud-merge durability, Cloud Backup upload prefetch, and the two unrelated compiler warnings remain separate work.

## Protected working-tree changes
- Preserve untouched: `ios/calorietracker.xcodeproj/project.pbxproj`, `ios/calorietracker/Info.plist`, `ios/calorietracker/InfoPlist.xcstrings`, `ios/calorietracker/LocalModels.xcstrings`, `ios/calorietracker/Localizable.xcstrings`, and `ios/calorietracker/WeeklyChallenge.xcstrings`.
- Preserve untouched: `ios/calorietracker.xcodeproj/xcshareddata/xcschemes/calorietracker.xcscheme` and `ios/calorietrackerUITests/SearchFoodAcceptanceUITests.swift`.

## Git state
- Today feature commit `e85c4a01b` was pushed normally. Historical-provenance commit `439b3fd54` and FoodStore commit `e6e06b1af` remain separate and pushed. No history rewrite.
- Intentionally uncommitted: held Search Food XCUITest edit, six protected edits, and scheme edit. Nothing staged after the handoff checkpoint.

## Recommended next task
- Restore reliable identity-strict Search Food XCUITest execution for the existing held test-only edit; do not change production hit regions without independent product evidence.

## Human decision required
- None for this checkpoint. Automatic continuation remains disallowed because repository routing is HOLD.
