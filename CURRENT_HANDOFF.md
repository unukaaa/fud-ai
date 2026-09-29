---
schema_version: 1
state: HOLD
risk_lane: AMBER
last_task_status: COMPLETE
last_task_risk_lane: RED
auto_start_allowed: false
human_decision_required: false
next_task_envelope: NEXT_TASK.md
validation_evidence_ref: "#validation"
---

# FOOD AI — Current Handoff

## Current checkpoint
- Branch: `main`; historical nutrition provenance commit `439b3fd54` is pushed to `origin/main`. Verify the handoff-only checkpoint HEAD from Git rather than embedding its own SHA here.
- Current development phase: historical source persistence is checkpointed after focused tests, arm64 build, and user-reported manual Simulator acceptance. Search Food automated acceptance remains a separate HOLD.
- Repository routing remains HOLD / AMBER; `NEXT_TASK.md` is advisory, not authority to launch another task.

## Last task
- Task: Checkpoint the validated historical nutrition provenance slice.
- Status: **COMPLETE**. The exact seven-file implementation/test slice was inspected, committed as `439b3fd54`, and pushed normally. No new product functionality was added during checkpointing.
- Summary: Saved food carries the historical nutrition-source snapshot. Recent/Frequent/Favorites repeat review uses that snapshot; ordinary edits preserve it, and explicit reprocessing captures a new accepted analysis. Legacy entries display “Source not recorded,” not an inferred source.

## Changes
- Provenance commit `439b3fd54`: `ios/calorietracker/ContentView.swift`, `Models/FoodEntry.swift`, `Services/GeminiService.swift`, new `Services/SavedFoodReviewAnalysis.swift`, `Views/EditFoodEntryView.swift`, `Views/FoodResultView.swift`, and new `ios/calorietrackerTests/SavedNutritionSourceRoundTripTests.swift`.
- Historical source, detail, confidence, known-macro flags, and trace IDs now round-trip with the saved food. Nutrition values, serving calculations, and Search Food resolution were not changed. Trace IDs do not trigger silent re-resolution.
- Earlier FoodStore EDIT/REPLACE durability commit `e6e06b1af` remains pushed and separate.

## Validation
- Before the provenance correction: **4 named tests; 1 passed, 3 failed, 0 skipped**. Verified, AUSNUT, and mixed parent sources reopened incorrectly as AI estimate.
- Provenance round-trip suite: **8/8 passed, 0 failed, 0 skipped**, Xcode exit 0; adjacent ServingUnitFallback, CombinedMeal, and FoodStore ADD suites: **31/31 passed, 0 failed, 0 skipped**, Xcode exit 0. Both result bundles were readable and rechecked during checkpoint.
- Fresh-DerivedData arm64 iOS Simulator app build: **exit 0**, with the same two unrelated warnings (`ExerciseCatalogWarmup.swift:16`, `RestaurantFoodSearchIndex.swift:102`). No build/test rerun during checkpoint because the staged seven-file candidate matched the validated source.
- User-reported manual Simulator acceptance: Big Mac saved/reopened through Recent retained verified McDonald’s Australia source/detail and **557 Cal, P24.6 C44.9 F29.4**. AUSNUT Cavendish reopened through Frequent retained AUSNUT/FSANZ detail, medium-banana amount and **121 Cal, P1.8 C25.4 F0.3**. Big Mac repeat/resave/reopen preserved source and nutrition. These were human observations, not agent-run XCUITests or physical-device validation.
- Legacy/no-snapshot entry: **not mounted manually**; deterministic decode test confirms honest “Source not recorded.” Device Hub automation had failed separately; no XCUITest acceptance is claimed for this provenance slice.
- Exact staged file list/diff inspected; `git diff --cached --check` passed. Protected, scheme, and held Search Food changes were excluded.

## Architecture decisions
- The accepted historical source snapshot is authoritative on reopen; dataset IDs are traceability only and do not silently re-resolve nutrition. Optional decoding preserves old entries without migration or backfill.
- FoodStore write-acceptance and photo cleanup semantics remain those of the earlier durability checkpoint; no persistence redesign was part of this provenance slice.

## Known issues / risks
- Search Food exact-ID XCUITest acceptance remains HOLD: its local test-only edit has **0 named executions**. This is separate from the user’s successful normal-tap food journeys and provenance manual acceptance.
- No safe mounted legacy/no-snapshot fixture was available. Diary import/export and cross-device transfer of provenance were outside this slice. Material identity/macro edits after repeat have no separate source-invalidation policy unless explicitly reprocessed.
- Mixed-source/photo Review Food layouts and ChatView VoiceOver judgment lack equivalent manual acceptance. Two raw-image-byte photo-removal tests are pre-existing failures. FoodStore delete/combine/cloud-merge durability, Cloud Backup upload prefetch, and the two unrelated compiler warnings remain separate work.

## Protected working-tree changes
- Preserve untouched: `ios/calorietracker.xcodeproj/project.pbxproj`, `ios/calorietracker/Info.plist`, `ios/calorietracker/InfoPlist.xcstrings`, `ios/calorietracker/LocalModels.xcstrings`, `ios/calorietracker/Localizable.xcstrings`, and `ios/calorietracker/WeeklyChallenge.xcstrings`.
- Preserve untouched: `ios/calorietracker.xcodeproj/xcshareddata/xcschemes/calorietracker.xcscheme` and `ios/calorietrackerUITests/SearchFoodAcceptanceUITests.swift`.

## Git state
- Provenance commit `439b3fd54` was pushed normally to `origin/main`; this handoff is a separate documentation-only checkpoint. Earlier FoodStore commit `e6e06b1af` remains pushed. No history rewrite.
- Intentionally uncommitted: held `ios/calorietrackerUITests/SearchFoodAcceptanceUITests.swift` (0 named executions), six protected edits, and the scheme edit. No other task work is staged.

## Recommended next task
- Restore reliable identity-strict Search Food XCUITest execution for the existing held test-only edit; do not change production hit regions without independent product evidence.

## Human decision required
- None for this checkpoint. Automatic continuation remains disallowed because repository routing is HOLD.
