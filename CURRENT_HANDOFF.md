# FOOD AI — Current Handoff

## Current checkpoint
- Branch: `main`
- HEAD: `0371f1ee2` (pushed AUSNUT feature commit; checkpoint documentation follows).
- Remote status: AUSNUT feature commit pushed normally to `origin/main`; no force push.
- Current development phase: Search Food V2 AUSNUT checkpoint complete; focused Search Food hardening is the separately approved next task.

## Last task
- Task: Bounded autonomy POC #3, Task 1 — package and push AUSNUT Search Food V2.
- Status: COMPLETE — reviewed, committed, and pushed the scoped feature; protected edits remain local.
- Summary: Stable AUSNUT ID discovery and explicit portion selection are now in the pushed checkpoint. The handoff and concise AGENTS guidance form a separate documentation commit.

## Changes
- Files changed: `ios/calorietracker/Services/AUSNUTFoodSearchIndex.swift`, `ios/calorietracker/Services/AustralianNutritionService.swift`, `ios/calorietracker/Services/FoodQueryInterpreter.swift`, `ios/calorietracker/Views/TextFoodInputView.swift`, `ios/calorietracker/ContentView.swift`, `ios/calorietrackerTests/AUSNUTFoodSearchIndexTests.swift`, `ios/calorietrackerTests/AUSNUTFoodSelectionTests.swift`, `ios/calorietrackerUITests/SearchFoodAcceptanceUITests.swift`.
- New files: AUSNUT search index and two focused test files; this handoff file is added by the checkpoint documentation commit.
- Behaviour changed: up to five combined suggestions; restaurant brand/product precedence; AUSNUT identity rows; explicit portion sheet; duplicate measure labels distinguished by weight; Analyse retained for composed meals.
- Nutrition values, restaurant datasets, interpreter/completeness logic, and Review Food layout were not changed by Task 4.
- No nutrition dataset, restaurant dataset, protected local file, or existing scheme edit was included.

## Validation
- Focused/unit tests: previously 14 executed across AUSNUT search/selection suites; 14 passed, 0 failures, 0 skips. Not rerun during packaging.
- XCUITest: first required subset executed 6: 5 passed, 1 banana test-interaction failure, 0 skips. Corrected banana-only rerun executed 1: 1 passed, 0 failures, 0 skips, `xcodebuild` exit 0. All six required journeys have passing executions, but not in one combined run.
- arm64 build: prior Task 4 iOS Simulator app build exited 0; the banana XCUITest rebuild also exited 0. No new build during packaging.
- Physical-device validation: not yet performed for Task 4.
- Reticle review: not performed; installed integration is browser/web-oriented and not suitable for this native SwiftUI screen.
- UI Skills / SwiftUI Designer review: Task 4 used UI Skills; SwiftUI Designer was unavailable then. A later read-only tooling audit activated UI Skills, Designer Helper, FWC SwiftUI, and swiftui-specialist; it did not change this feature.

## Architecture decisions
- Keep `RestaurantFoodSearchIndex` and `AUSNUTFoodSearchIndex` separate; the unified wrapper holds discovery identities only, never nutrition.
- Restaurant brands/products remain first. AUSNUT discovery accepts whole-query matches, not a component found within a composed meal.
- Selected AUSNUT ID and exact measure index/explicit grams pass to the authoritative Australian nutrition service. No silent 100 g default, name rematch, or AI fallback.
- Broad `rice`/`milk` ranking was not changed: dataset names alone provide no trustworthy popularity/default-serving signal.

## Known issues / risks
- An XCUITest whole-button tap activated the adjacent banana row; tapping the named cavendish label preserved the exact ID and passed. The product's physical tap-target reliability still merits device review; no product defect was established here.
- `rice` may rank rice bran first; `milk` may rank canned milk first. No unsupported consumer-preference claim was added.
- Native visual review, physical-device keyboard/portion flow, long-name presentation, and light/dark appearance still need human judgement.

## Protected working-tree changes
- Preserve unrelated uncommitted edits: `ios/calorietracker.xcodeproj/project.pbxproj`, `ios/calorietracker/Info.plist`, `ios/calorietracker/InfoPlist.xcstrings`, `ios/calorietracker/LocalModels.xcstrings`, `ios/calorietracker/Localizable.xcstrings`, `ios/calorietracker/WeeklyChallenge.xcstrings`.
- Preserve the existing uncommitted `ios/calorietracker.xcodeproj/xcshareddata/xcschemes/calorietracker.xcscheme` edit.

## Git state
- Committed: `0371f1ee2` — `Complete AUSNUT Search Food V2`; this handoff and the AGENTS guidance are checkpoint documentation.
- Pushed: `0371f1ee2` to `origin/main` by normal fast-forward; no force push.
- Uncommitted intended work: none at this Task 1 checkpoint after documentation is committed.
- Unrelated/protected modifications: the six files and scheme edit listed above remain uncommitted and untouched.

## Recommended next task
Perform the separately approved Search Food hardening task using verified native-iOS design guidance; then validate the focused UI paths. Physical-device judgement remains necessary for tap targets, keyboard stability, and visual polish.

## Human decision required
None.
