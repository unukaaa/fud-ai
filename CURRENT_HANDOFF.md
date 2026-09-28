# FOOD AI — Current Handoff

## Current checkpoint
- Branch: `main`; previous synchronized handoff checkpoint `8a778d77b551ed7a6ffccf6b18150c28c989372d` followed exercise commit `5a09e3c13`. This document is the next handoff-only checkpoint.
- Current phase: Search Food hit-target and uncommitted Review Food V2 acceptance remain on HOLD. The validated exercise concurrency/manifest-readiness slice is committed and pushed.

## Last task
- Task: Prove or disprove `-collect-test-diagnostics never` with one intentionally failing UI test.
- Status: HOLD. Search Food / Review Food HOLD is unchanged.
- Summary: The prebuilt isolated probe again stalled before its named UI test began. It was interrupted once after 153.14 seconds; no expected assertion failure occurred. The diagnostic flag's post-failure effect remains unproven.

## Changes
- Production commit files: `CURRENT_HANDOFF.md`, `ExerciseLibraryItem.swift`, `ExerciseCatalogWarmup.swift`, `ExerciseLibraryService.swift`, `ExerciseSearchMatcher.swift`, `FreeExerciseDBAssetResolver.swift`, `FreeExerciseDBLoader.swift`, `AnimatedExerciseVisual.swift`, and `ExerciseVisualAssetResolverTests.swift`.
- This task changes only this handoff. The prior temporary probe is absent from source (final `calorietrackerUITests.swift` diff is empty); its compiled copy was used via `test-without-building`. No production, Search Food, Review Food, scheme, or protected file was edited.

## Validation
- Final focused suite: `ExerciseVisualAssetResolverTests` on arm64 iPhone 17 Simulator: **20 executed, 20 passed, 0 failed, 0 skipped**, `xcodebuild` exit 0 and result-bundle summary verified. Two new tests mount `AnimatedExerciseVisual`; the ready test also observes a decoded non-empty PNG image. Prior 18 resolver/cache tests remain green. One initial 20-test run had 18 passes/2 failures from a test-only nested-optional assertion error; the assertion was corrected and the final two suite runs passed 20/20.
- Final arm64 Simulator app: **clean build exit 0** after the last test-hook edit. App warnings remain **2**: catalog line 16 and out-of-scope `RestaurantFoodSearchIndex.swift:102`; line 18 remains warning-free. Test-target warnings are separate.
- XCUITest: not needed; mounted SwiftUI view was exercised in the focused test target. Physical device: not run; visual polish is not claimed.
- Design guidance: `swiftui-specialist` consulted for narrow observable-state invalidation. Reticle/UI Skills review not applicable to this backend/readiness task.
- Staged `git diff --check` passed before commit. No test/build was rerun during the packaging-only task; the verified results above are from the immediately preceding implementation gate.
- Native hit-target diagnostic: prior XCUITest evidence placed Cavendish `16502001` at x=30–310, y=254.3–328.7 pt and synthesized a tap at x=141.7, y=283.3 pt, but Lady Finger `16502002` opened. This task booted iPhone 18 Pro `FC84C07A-0C1B-4E64-8453-C29AC98C0FD0` with `--arch=arm64` and verified `Booted`. The installed Xcode bundle has no `Simulator.app`; native computer-use could not resolve `Simulator`/`com.apple.iphonesimulator`, while `Device Hub` yielded no interactive window (timeout). The Banana search screen, keyboard/popover, pre-tap screenshot, native click coordinate, and post-tap identity could not be captured. **Native taps: 0; tests/builds: 0. No classification is supported.**
- Xcode finalization audit (Xcode 27.0): among 48 existing `/private/tmp` result bundles after this probe, 37 have `Info.plist` and 11 remain incomplete with `Staging`/`Data`. Multiple incomplete UI **and unit** bundles contain `simctl_diagnostics/diagnose.log` ending `TIMEOUT - Waited 600 seconds for all devices to finish gathering but they never did`; a three-journey UI log had already reported **3 executed / 2 failed** before `** BUILD INTERRUPTED **`. Conversely, a finalized six-test UI bundle contains **6 executed / 6 failed**. Failure or screenshot attachment alone is therefore insufficient to explain every stall; the strongest observed correlate is verbose simulator-diagnostic harvesting/finalization, not Search Food code.
- Unrelated probe: `xcodebuild -project ios/calorietracker.xcodeproj -scheme calorietracker -destination 'platform=iOS Simulator,id=FC84C07A-0C1B-4E64-8453-C29AC98C0FD0' -parallel-testing-enabled NO -collect-test-diagnostics never -resultBundlePath /private/tmp/foodai-xcode-finalization-probe-20260928.xcresult -only-testing:calorietrackerUITests/calorietrackerUITests/testResultBundleFailureProbe ARCHS=arm64 ONLY_ACTIVE_ARCH=YES test`. It compiled but no named test case executed; the test runner did not appear during the bounded wait. The stale command was interrupted once (exit 75). Its finalized bundle reports one **runner cancellation**, not an executed test failure. **Actual probe tests executed: 0.** This does not validate the flag's reliability after a real failing test. No second attempt was made.
- Current one-attempt proof command: `/usr/bin/time -p xcodebuild test-without-building -xctestrun /Users/thedon/Library/Developer/Xcode/DerivedData/calorietracker-aawbdnvcapxlahfgtubegjqzlyvy/Build/Products/calorietracker_calorietracker_iphonesimulator27.0-arm64.xctestrun -destination 'platform=iOS Simulator,id=FC84C07A-0C1B-4E64-8453-C29AC98C0FD0' -destination-timeout 60 -parallel-testing-enabled NO -collect-test-diagnostics never -resultBundlePath /private/tmp/foodai-xcode-failure-flag-proof-20260928.xcresult -only-testing:calorietrackerUITests/calorietrackerUITests/testResultBundleFailureProbe`. Existing compiled test symbol was verified before the run. No rebuild or second test attempt occurred.
- Current result: output reached only `Testing started`, not `Test Case ... started`; interrupt diagnostics said `waiting for workers to materialize`. No UI-test runner process appeared. Interrupted after **153.14 s**, `xcodebuild` exit **75**. The fresh result bundle has `Info.plist` and is readable, but `xcresulttool` reports **runner cancellation** as one failed record; **named test executions: 0, expected assertion failures: 0**. No `simctl_diagnostics/diagnose.log` or 600-second timeout appeared, but no actual test failure occurred, so the flag is **neither proven nor disproven** as a post-failure mitigation.

## Architecture decisions
- `ExerciseVisualManifestCache` is MainActor-owned and observable. `start()` is idempotent; missing asset or invalid decode is a cached terminal failure, not a retry loop. Pending is distinct from failure.
- The parser and its immutable manifest value are nonisolated/Sendable. Decoding occurs in a detached utility task; terminal state is published on MainActor. Startup warmup awaits that same one-shot task, while a first view can start it independently.
- Eventual ready/failed rendering retains existing authored-frame/JPEG fallback rules; only the pending first render may temporarily show the neutral existing placeholder. No catalog line-16 ownership change was made.

## Known issues / risks
- Search Food identity-strict Banana/Big Mac/Six-nuggets acceptance remains unreliable. In prior diagnostics, a synthesized tap inside Cavendish's accessibility frame opened Lady Finger. This host currently lacks an interactive native Simulator window, so native-vs-XCUITest hit testing remains unclassified. Do not judge or commit Review Food V2 until its intended identities can be reached reliably.
- Xcode result-bundle finalization can hang while collecting simulator diagnostics; XCUITest runner startup can also stall independently (`waiting for workers to materialize` in the current attempt). `-collect-test-diagnostics never` is supported and retains `-resultBundlePath`, but its post-failure reliability remains unproven. For future bounded UI runs, use `-parallel-testing-enabled NO`, a fresh `-resultBundlePath`, normal output, and provisionally `-collect-test-diagnostics never`; retain a watchdog and demand named-test execution plus a readable result before claiming a verdict. The flag avoids verbose sysdiagnose but sacrifices those diagnostics when a failure needs deeper triage.
- Catalog warmup line 16 remains HOLD due to lazy-singleton first-access ownership/timing; no catalog-readiness redesign has been chosen. Search Food warning at `RestaurantFoodSearchIndex.swift:102` remains out of scope.
- The manifest's earlier single Simulator first-load measurement was 38.062 ms total (4.461 ms asset, 33.398 ms decode/validation), all observed on the main thread before this change. No new physical-device timing or visual-refresh measurement was made.
- Uncommitted Review Food V2 presentation remains separate from this pushed exercise slice.
- Exercise-manifest rendered refresh is now verified in a mounted Debug view with a gated cache. This does not replace physical-device judgment of animation/polish. The DEBUG-only seam has no release-build path or global mutable override.

## Protected working-tree changes
- Preserve unrelated edits to `ios/calorietracker.xcodeproj/project.pbxproj`, `ios/calorietracker/Info.plist`, `ios/calorietracker/InfoPlist.xcstrings`, `ios/calorietracker/LocalModels.xcstrings`, `ios/calorietracker/Localizable.xcstrings`, and `ios/calorietracker/WeeklyChallenge.xcstrings`.
- Preserve the existing `ios/calorietracker.xcodeproj/xcshareddata/xcschemes/calorietracker.xcscheme` edit. None of these protected/scheme files was staged, committed, reset, or modified in this task.

## Git state
- Committed/pushed before this checkpoint: exercise slice `5a09e3c13` and handoff-only commit `8a778d77b` on `origin/main`. This document alone records the newer HOLD evidence.
- Uncommitted intended work outside this handoff: `FoodResultView.swift` and `SearchFoodAcceptanceUITests.swift` (Review Food V2/HOLD). No exercise production/test or temporary probe source file remains uncommitted.
- Unrelated/protected modifications: six files plus scheme edit listed above remain local and uncommitted; no staged/conflicted files are intended after the handoff-only commit.

## Recommended next task
Diagnose the independent XCUITest worker-materialization stall on the current iPhone 18 Pro simulator without changing app behaviour or the scheme. Once a named UI test can start, make one fresh intentional-failure run with `-collect-test-diagnostics never` to evaluate post-failure finalization. Separately, Search Food's native Cavendish tap still requires an interactive Simulator or observable physical-device tap before Review Food V2 can be judged.

## Human decision required
None. Test infrastructure and native hit testing remain on HOLD; no Search Food product fix is justified by the current evidence.
