# FOOD AI — Current Handoff

## Current checkpoint
- Branch: `main`; HEAD and `origin/main`: `f01e43cda` (no commit or push this task).
- Current phase: Search Food hit-target and uncommitted Review Food V2 acceptance remain on HOLD. Exercise-manifest readiness, including mounted-view refresh, is locally validated and ready for a carefully scoped commit.

## Last task
- Task: Deterministic mounted-view refresh verification for async `ExerciseVisualManifest` readiness.
- Status: COMPLETE for the exercise-manifest slice. Search Food / Review Food HOLD is unchanged.
- Summary: A DEBUG-only injected cache and render/frame callbacks let tests mount the real `AnimatedExerciseVisual` while decoding is gated. The mounted view first reports pending, then publishes the authored PNG asset and loads a non-empty image after ready; a separate test reports the original JPEG fallback only after failed. Both prove one asset load/decode. Default production resolution is unchanged; no global override was added.

## Changes
- This task changed `ios/calorietracker/Services/FreeExerciseDBAssetResolver.swift`, `ios/calorietracker/Views/AnimatedExerciseVisual.swift`, `ios/calorietrackerTests/ExerciseVisualAssetResolverTests.swift`, and this handoff. The prior uncommitted line-18 warmup change remains in `ExerciseCatalogWarmup.swift`.
- Warmup line 16 and catalog loading are unchanged. Existing unrelated edits within the resolver/test files predate this task and remain intact.
- No nutrition, Search Food, Review Food, scheme, or protected-file changes were made.

## Validation
- Final focused suite: `ExerciseVisualAssetResolverTests` on arm64 iPhone 17 Simulator: **20 executed, 20 passed, 0 failed, 0 skipped**, `xcodebuild` exit 0 and result-bundle summary verified. Two new tests mount `AnimatedExerciseVisual`; the ready test also observes a decoded non-empty PNG image. Prior 18 resolver/cache tests remain green. One initial 20-test run had 18 passes/2 failures from a test-only nested-optional assertion error; the assertion was corrected and the final two suite runs passed 20/20.
- Final arm64 Simulator app: **clean build exit 0** after the last test-hook edit. App warnings remain **2**: catalog line 16 and out-of-scope `RestaurantFoodSearchIndex.swift:102`; line 18 remains warning-free. Test-target warnings are separate.
- XCUITest: not needed; mounted SwiftUI view was exercised in the focused test target. Physical device: not run; visual polish is not claimed.
- Design guidance: `swiftui-specialist` consulted for narrow observable-state invalidation. Reticle/UI Skills review not applicable to this backend/readiness task.
- `git diff --check` for task files passed. One sandboxed clean-build attempt failed before compilation due to Xcode cache/Simulator permissions; the permission-corrected final clean build passed.

## Architecture decisions
- `ExerciseVisualManifestCache` is MainActor-owned and observable. `start()` is idempotent; missing asset or invalid decode is a cached terminal failure, not a retry loop. Pending is distinct from failure.
- The parser and its immutable manifest value are nonisolated/Sendable. Decoding occurs in a detached utility task; terminal state is published on MainActor. Startup warmup awaits that same one-shot task, while a first view can start it independently.
- Eventual ready/failed rendering retains existing authored-frame/JPEG fallback rules; only the pending first render may temporarily show the neutral existing placeholder. No catalog line-16 ownership change was made.

## Known issues / risks
- Search Food identity-strict Banana/Big Mac/Six-nuggets acceptance remains unreliable. In prior diagnostics, a synthesized tap inside Cavendish's accessibility frame opened Lady Finger; native-vs-XCUITest hit testing remains unclassified. Do not judge or commit Review Food V2 until its intended identities can be reached reliably.
- Catalog warmup line 16 remains HOLD due to lazy-singleton first-access ownership/timing; no catalog-readiness redesign has been chosen. Search Food warning at `RestaurantFoodSearchIndex.swift:102` remains out of scope.
- The manifest's earlier single Simulator first-load measurement was 38.062 ms total (4.461 ms asset, 33.398 ms decode/validation), all observed on the main thread before this change. No new physical-device timing or visual-refresh measurement was made.
- Uncommitted Review Food V2 presentation and prior workout changes remain separate from this task.
- Exercise-manifest rendered refresh is now verified in a mounted Debug view with a gated cache. This does not replace physical-device judgment of animation/polish. The DEBUG-only seam has no release-build path or global mutable override.

## Protected working-tree changes
- Preserve unrelated edits to `ios/calorietracker.xcodeproj/project.pbxproj`, `ios/calorietracker/Info.plist`, `ios/calorietracker/InfoPlist.xcstrings`, `ios/calorietracker/LocalModels.xcstrings`, `ios/calorietracker/Localizable.xcstrings`, and `ios/calorietracker/WeeklyChallenge.xcstrings`.
- Preserve the existing `ios/calorietracker.xcodeproj/xcshareddata/xcschemes/calorietracker.xcscheme` edit. None was staged, committed, reset, or modified in this task.

## Git state
- Committed/pushed: unchanged; local `main` and `origin/main` match at `f01e43cda`.
- Uncommitted intended work: validated manifest-readiness implementation/tests, this handoff update, earlier workout changes, and Review Food V2 files. The resolver/test files also contain earlier unrelated workout edits, so any later commit must stage exact hunks/files deliberately. No staged or conflicted files; no commit or push this task.
- Unrelated/protected changes: six files plus scheme edit listed above, still local and uncommitted.

## Recommended next task
Package the validated exercise-manifest readiness slice as a focused local commit only after auditing exact staged hunks against the earlier workout edits in shared files; do not include Search Food, Review Food, protected edits, or the scheme. Separately, Search Food remains on HOLD pending native-vs-XCUITest Cavendish hit-target evidence.

## Human decision required
No decision is needed for the validated exercise-manifest slice. Separately, unlock the Mac or provide a physical-device observation for the native-vs-XCUITest Search Food hit-target diagnosis. No Search Food product fix is justified by the current evidence.
