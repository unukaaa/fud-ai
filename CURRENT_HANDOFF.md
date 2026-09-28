# FOOD AI — Current Handoff

## Current checkpoint
- Branch: `main`.
- Last production checkpoint before this handoff-only commit: `3580a99efaadc2ab2cdc40f13a0cf37f696c97d8`.
- Remote status: local `main` and `origin/main` are synchronized at this handoff-only checkpoint. Workout warning corrections and Review Food V2 work remain uncommitted.
- Current development phase: Search Food hardening is pushed. The local Review Food V2 presentation slice remains on validation HOLD because Search Food suggestion activation is not reliable.

## Last task
- Task: Read-only ownership audit for `ExerciseCatalogWarmup.swift:16` only.
- Status: HOLD.
- Summary: `ExerciseLibraryService.shared` is MainActor-isolated by the app target's default actor isolation, yet warmup accesses it from a detached task. Its lazy initialization performs bundled catalog read/decode, immutable item construction, and sorting; these operations have no UI dependency. MainActor ownership belongs to the workout store's mutable custom-item merge/cache and view publication. No production code changed. Search Food / Review Food remain on HOLD.

## Changes
- Task 1 commit: `3580a99ef` — `Harden Search Food interaction and accessibility`, containing `AGENTS.md`, the prior handoff, `TextFoodInputView.swift`, and `SearchFoodAcceptanceUITests.swift`.
- Task 2: read-only source/model/design audit; no product edits.
- Files changed this task: this handoff only. Prior lookup/cache and filter-only corrections, Review Food files, Search Food, six protected files, scheme edit, and `ExerciseCatalogWarmup.swift` were not touched.
- Task 3 UI behaviour: compact inline emoji/identity summary; prominent calories and three macros; long name no longer competes horizontally with source badge; partial restaurant/AUSNUT source-card wording no longer claims full verification; ingredient rows show existing per-ingredient provenance when populated.
- No nutrition calculations, serving/editing actions, Search Food routing, restaurant/AUSNUT data, or component models were intentionally changed.

## Validation
- Current line-16 audit: read-only source/Git inspection; 0 tests, 0 builds, 0 XCUITest executions. Prior results below are historical, not rerun here.
- Focused/unit tests: new detached cache/lookup test passed within `ExerciseVisualAssetResolverTests`: 16 executions, 16 passed, 0 failed, 0 skipped on arm64 iPhone 17 Simulator; xcodebuild exited 0 and the result bundle confirmed counts. An initial method-selector attempt exited 0 but selected 0 tests, so it is not a pass. Prior `ExerciseSearchMatcherTests` 5/5 passed (not rerun this task).
- XCUITest: 0 executions this task. Prior uninstrumented acceptance: 7 executions / 4 passes / 3 failures / 0 skips, not green. Prior temporary diagnostics: 4 executions / 0 passes / 4 instrumentation failures / 0 skips, not product verdicts.
- arm64 build: latest iOS Simulator app build exited 0. Across the bounded mechanical warning corrections, the full app-warning count fell from 6 to 3 (latest step 4 to 3); `ExerciseCatalogWarmup.swift:17` is gone. Warm-up lines 16 and 18 and the out-of-scope Search Food warning remain. The unit-test target emitted separate, unrelated test-source warnings; these are not included in the app-build count.
- Physical-device validation: Task 3 not performed.
- Reticle review: not performed; not a native-iOS acceptance tool in this configuration.
- UI Skills / Designer Helper review: both activated for the audit; FWC Liquid Glass and swiftui-specialist guidance consulted. No glass was added to scrolling content.
- Simulator capture: previous diagnostic video, screenshots, and hierarchy showed Cavendish `16502001` first at x=30–310, y=254.3–328.7 pt, with Lady Finger `16502002` second. XCUITest synthesized x=141.7, y=283.3 pt inside Cavendish's AX frame, but Lady Finger opened. No new screenshot or native tap was obtained in the warning audit. Review Food V2 appearance remains unverified.

## Architecture decisions
- Review Food already receives parent nutrition, serving metadata, and `MealIngredient` source/detail fields. This slice uses existing display data only; no nutrition or provenance model redesign is required.
- Retain photo carousel, ingredient/nutrition/serving editors, and fixed Add action. Do not add decorative Liquid Glass to the scrolling content.
- Task 2 audit ranked contradictory partial-source wording and hidden mixed provenance High; empty emoji space, long-name compression, four equal cards, and fixed-width serving controls Medium; raw technical source IDs and duplicate details Low. The implementation addressed only the first coherent summary/provenance slice.
- Workout ownership: project-wide default actor isolation is MainActor. `WorkoutsView.refreshDisplayItems()` snapshots an immutable `[ExerciseLibraryItem]` and `ExerciseLibraryFilterRequest` on the UI actor, computes in the existing detached user-initiated task, then publishes through `MainActor.run` with its generation guard. Exercise items contain only immutable strings/string arrays; sort is a value enum; matcher uses strings and a fixed immutable alias map. The explicit-array `ExerciseLibraryService` initializer and its filtering/compare helpers are nonisolated; default loading and `shared` remain MainActor-isolated. No runtime scheduling or filter ordering logic changed.
- Image lookup ownership: `FreeExerciseDBRecord` is a Sendable immutable value of strings/arrays. `FreeExerciseDBRecordsCache.records()` guards every read/write of its private cached array, including file read/decode, with `NSLock`; only that manually synchronized property uses `nonisolated(unsafe)`. Resource URL lookup uses Foundation Bundle/FileManager, and image lookup lazily constructs immutable static arrays/dictionaries with pure string normalization. Only these data-only members and `warmImageLookup()` became nonisolated. UIKit `NSDataAsset` manifest loading and the shared catalog loader remain MainActor-isolated; no runtime scheduling or synchronization changed.
- Catalog ownership audit: `shared` is a lazy `static let` of an immutable service, but its default initializer invokes `FreeExerciseDBLoader.load()`. The loader reads/decode-caches bundled JSON under the existing lock, maps Sendable record values into immutable `ExerciseLibraryItem` values, and sorts names; no SwiftUI/UIKit access or mutable UI state occurs in that chain. `StrengthWorkoutStore.exerciseLibrary` reads the base array, merges device-local custom items, and mutates its own cached service/fingerprint on MainActor; `UserExerciseEditorView` also reads `shared` from UI. The smallest plausible correction is a narrowly nonisolated, Sendable catalog loader/service singleton while keeping mutable store publication MainActor-owned. This needs a separate implementation/validation task; do not broadly annotate the workout store or move decoding onto MainActor.

## Known issues / risks
- Task 3 acceptance is not green. The XCUITest wrong-row activation is proven, but native hit testing was not compared because the Mac was locked. SwiftUI popover hit testing, XCUITest synthesis, and transient layout shift remain competing explanations. No demonstrated static dataset-ID mapping defect exists. Do not weaken identity assertions or infer reliable handoff.
- Three app warnings remain: `ExerciseCatalogWarmup.swift:16` still reaches MainActor-isolated `ExerciseLibraryService.shared` and remains HOLD due to lazy-singleton first-access semantics; `:18` reaches the UIKit `NSDataAsset` manifest and is unreviewed/high-risk; `RestaurantFoodSearchIndex.swift:102` is out of scope during Search Food HOLD. Do not move heavy loading wholesale to MainActor merely to clear warnings.
- Line-16 timing risk: making the immutable singleton legally nonisolated would preserve the synchronous API and once-only initialization, but would not guarantee background execution. The detached warmup is only scheduled at app startup; if a UI consumer reaches `shared` first, the same decode/map/sort can run on MainActor and cause a hitch. A guaranteed off-main loader with MainActor publication would need explicit readiness/fallback semantics and could change initialization order or visible behavior. No decision to redesign catalog readiness/publication has been made; keep implementation on HOLD.
- Review Food Task 3 visual layout, Dynamic Type, dark mode, and physical-device feel have not been verified.
- Existing serving-unit wrapping, raw technical source IDs, and duplicate detail presentation remain outside this slice.

## Protected working-tree changes
- Preserve unrelated uncommitted edits: `ios/calorietracker.xcodeproj/project.pbxproj`, `ios/calorietracker/Info.plist`, `ios/calorietracker/InfoPlist.xcstrings`, `ios/calorietracker/LocalModels.xcstrings`, `ios/calorietracker/Localizable.xcstrings`, `ios/calorietracker/WeeklyChallenge.xcstrings`.
- Preserve the existing uncommitted `ios/calorietracker.xcodeproj/xcshareddata/xcschemes/calorietracker.xcscheme` edit. None was staged, committed, reset, or edited during this run.

## Git state
- Committed/pushed: production hardening `3580a99ef`, earlier handoff-only HOLD checkpoint `9ee1e1f42`, and this handoff-only checkpoint. No production/test files were included in this checkpoint.
- Uncommitted intended work: existing Task 3 `FoodResultView.swift`, `SearchFoodAcceptanceUITests.swift`, earlier exercise-resolver and filter-only corrections, and the lookup/cache correction and test.
- Unrelated/protected modifications: six files and scheme edit listed above remain local and uncommitted. No staged/conflicted files are intended.

## Recommended next task
For concurrency, scope a separate minimal implementation/validation task for a Sendable nonisolated catalog singleton and loader, with an explicit first-access timing check; decide separately whether a strict never-on-main guarantee warrants asynchronous publication. Leave line 18's UIKit manifest for its own decision. Search Food / Review Food remain on HOLD; their next acceptance diagnostic is still an independent native-style Cavendish tap after the Mac is unlocked. Do not commit Review Food V2 until identity-strict journeys pass.

## Human decision required
Unlock the Mac (or provide a physical-device observation) before an independent native-versus-XCUITest classification can be made. No product correction is authorized by the current evidence.
