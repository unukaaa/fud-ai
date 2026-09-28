# FOOD AI — Current Handoff

## Current checkpoint
- Branch: `main`; exercise checkpoint pushed to `origin/main` as `5a09e3c134c4500e99ab4d31f89652dfef09de30`.
- Current phase: Search Food hit-target and uncommitted Review Food V2 acceptance remain on HOLD. The validated exercise concurrency/manifest-readiness slice is committed and pushed.

## Last task
- Task: Package and push the validated workout/exercise warning-fix slice.
- Status: COMPLETE. Search Food / Review Food HOLD is unchanged.
- Summary: Production commit `5a09e3c13` includes the prior data-only filter/cache/lookup corrections, async manifest readiness, DEBUG-only mounted-view test seam, focused exercise tests, and the corresponding handoff. It pushed normally to `origin/main`; no force push or history rewrite.

## Changes
- Production commit files: `CURRENT_HANDOFF.md`, `ExerciseLibraryItem.swift`, `ExerciseCatalogWarmup.swift`, `ExerciseLibraryService.swift`, `ExerciseSearchMatcher.swift`, `FreeExerciseDBAssetResolver.swift`, `FreeExerciseDBLoader.swift`, `AnimatedExerciseVisual.swift`, and `ExerciseVisualAssetResolverTests.swift`.
- This follow-up changes this handoff only to record the pushed SHA and final Git state. Warmup line 16 remains untouched; no nutrition, Search Food, Review Food, scheme, or protected-file edits were included.

## Validation
- Final focused suite: `ExerciseVisualAssetResolverTests` on arm64 iPhone 17 Simulator: **20 executed, 20 passed, 0 failed, 0 skipped**, `xcodebuild` exit 0 and result-bundle summary verified. Two new tests mount `AnimatedExerciseVisual`; the ready test also observes a decoded non-empty PNG image. Prior 18 resolver/cache tests remain green. One initial 20-test run had 18 passes/2 failures from a test-only nested-optional assertion error; the assertion was corrected and the final two suite runs passed 20/20.
- Final arm64 Simulator app: **clean build exit 0** after the last test-hook edit. App warnings remain **2**: catalog line 16 and out-of-scope `RestaurantFoodSearchIndex.swift:102`; line 18 remains warning-free. Test-target warnings are separate.
- XCUITest: not needed; mounted SwiftUI view was exercised in the focused test target. Physical device: not run; visual polish is not claimed.
- Design guidance: `swiftui-specialist` consulted for narrow observable-state invalidation. Reticle/UI Skills review not applicable to this backend/readiness task.
- Staged `git diff --check` passed before commit. No test/build was rerun during the packaging-only task; the verified results above are from the immediately preceding implementation gate.

## Architecture decisions
- `ExerciseVisualManifestCache` is MainActor-owned and observable. `start()` is idempotent; missing asset or invalid decode is a cached terminal failure, not a retry loop. Pending is distinct from failure.
- The parser and its immutable manifest value are nonisolated/Sendable. Decoding occurs in a detached utility task; terminal state is published on MainActor. Startup warmup awaits that same one-shot task, while a first view can start it independently.
- Eventual ready/failed rendering retains existing authored-frame/JPEG fallback rules; only the pending first render may temporarily show the neutral existing placeholder. No catalog line-16 ownership change was made.

## Known issues / risks
- Search Food identity-strict Banana/Big Mac/Six-nuggets acceptance remains unreliable. In prior diagnostics, a synthesized tap inside Cavendish's accessibility frame opened Lady Finger; native-vs-XCUITest hit testing remains unclassified. Do not judge or commit Review Food V2 until its intended identities can be reached reliably.
- Catalog warmup line 16 remains HOLD due to lazy-singleton first-access ownership/timing; no catalog-readiness redesign has been chosen. Search Food warning at `RestaurantFoodSearchIndex.swift:102` remains out of scope.
- The manifest's earlier single Simulator first-load measurement was 38.062 ms total (4.461 ms asset, 33.398 ms decode/validation), all observed on the main thread before this change. No new physical-device timing or visual-refresh measurement was made.
- Uncommitted Review Food V2 presentation remains separate from this pushed exercise slice.
- Exercise-manifest rendered refresh is now verified in a mounted Debug view with a gated cache. This does not replace physical-device judgment of animation/polish. The DEBUG-only seam has no release-build path or global mutable override.

## Protected working-tree changes
- Preserve unrelated edits to `ios/calorietracker.xcodeproj/project.pbxproj`, `ios/calorietracker/Info.plist`, `ios/calorietracker/InfoPlist.xcstrings`, `ios/calorietracker/LocalModels.xcstrings`, `ios/calorietracker/Localizable.xcstrings`, and `ios/calorietracker/WeeklyChallenge.xcstrings`.
- Preserve the existing `ios/calorietracker.xcodeproj/xcshareddata/xcschemes/calorietracker.xcscheme` edit. None of these protected/scheme files was staged, committed, reset, or modified in this task.

## Git state
- Committed/pushed: exercise slice `5a09e3c13` on `origin/main`, followed by a handoff-only checkpoint recording that state. Local/remote equality is verified as part of the checkpoint task.
- Uncommitted intended work: `FoodResultView.swift` and `SearchFoodAcceptanceUITests.swift` (Review Food V2/HOLD). No exercise production/test files remain uncommitted.
- Unrelated/protected modifications: six files plus scheme edit listed above remain local and uncommitted; no staged/conflicted files are intended after the handoff-only commit.

## Recommended next task
Resolve the independent Search Food hit-target HOLD with a bounded native-style Cavendish tap compared against the known XCUITest wrong-row tap. Do not judge or commit Review Food V2 until identity-strict navigation is reliable.

## Human decision required
No decision is needed for the validated exercise-manifest slice. Separately, unlock the Mac or provide a physical-device observation for the native-vs-XCUITest Search Food hit-target diagnosis. No Search Food product fix is justified by the current evidence.
