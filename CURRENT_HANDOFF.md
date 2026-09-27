# FOOD AI — Current Handoff

## Current checkpoint
- Branch: `main`.
- Last production checkpoint before this handoff-only commit: `3580a99efaadc2ab2cdc40f13a0cf37f696c97d8`.
- Remote status before this handoff-only commit: local `main` and `origin/main` matched at that checkpoint; 0 ahead / 0 behind.
- Current development phase: Search Food hardening is pushed. The local Review Food V2 presentation slice remains on validation HOLD because Search Food selection is not reliable in the required UI journeys.

## Last task
- Task: Search Food hit-target investigation for Banana, Big Mac, and Six nuggets.
- Status: HOLD.
- Summary: Focused XCUITest reproduction found intermittent tap/hit-target failure before Review Food. Narrow runs passed for each investigated Banana/Big Mac route, but the required three-journey run failed Banana and Six nuggets. No production fix was justified; the experimental test tap changes were restored. Review Food V2 remains uncommitted.

## Changes
- Task 1 commit: `3580a99ef` — `Harden Search Food interaction and accessibility`, containing `AGENTS.md`, the prior handoff, `TextFoodInputView.swift`, and `SearchFoodAcceptanceUITests.swift`.
- Task 2: read-only source/model/design audit; no product edits.
- Existing uncommitted Review Food work: `ios/calorietracker/Views/FoodResultView.swift` and `ios/calorietrackerUITests/SearchFoodAcceptanceUITests.swift`. The hit-target investigation changed only this handoff in its final working tree.
- Task 3 UI behaviour: compact inline emoji/identity summary; prominent calories and three macros; long name no longer competes horizontally with source badge; partial restaurant/AUSNUT source-card wording no longer claims full verification; ingredient rows show existing per-ingredient provenance when populated.
- No nutrition calculations, serving/editing actions, Search Food routing, restaurant/AUSNUT data, or component models were intentionally changed.

## Validation
- Focused/unit tests: no unit tests rerun because production code did not change. Prior `FoodQueryInterpreterTests` suite: 59 executions, 59 passed, 0 failures/skips.
- XCUITest this investigation: initial Banana+Big Mac run, 2 executions / 1 pass / 1 failure / 0 skips (Banana passed, Big Mac missed Review Food). Identified-button narrow runs: Big Mac 1/1 pass, Banana 1/1 pass, 0 skips; both commands exited 0. Required Banana+Big Mac+Six nuggets run: 3 executions / 1 pass / 2 failures / 0 skips (Big Mac passed; Banana did not open portion; Six nuggets did not reach Review Food). Total this investigation: 7 executions, 4 passes, 3 failures, 0 skips. Failed multi-test runs stalled during Xcode result finalization after test completion; exact stale processes were stopped. Passing narrow runs finalized normally.
- arm64 build: no separate build rerun because production code did not change; prior arm64 iOS Simulator app build exited 0. XCUITest invocations compiled current app/test targets.
- Physical-device validation: Task 3 not performed.
- Reticle review: not performed; not a native-iOS acceptance tool in this configuration.
- UI Skills / Designer Helper review: both activated for the audit; FWC Liquid Glass and swiftui-specialist guidance consulted. No glass was added to scrolling content.
- Simulator screenshot review: a live Big Mac Search Food screenshot showed the row visibly inside the popover while XCUITest reported an invalid activation point for its nested label. Failed multi-test result bundles did not finalize, so the required three retained Review Food screenshots could not be reviewed together; rendered Task 3 appearance remains unverified.

## Architecture decisions
- Review Food already receives parent nutrition, serving metadata, and `MealIngredient` source/detail fields. This slice uses existing display data only; no nutrition or provenance model redesign is required.
- Retain photo carousel, ingredient/nutrition/serving editors, and fixed Add action. Do not add decorative Liquid Glass to the scrolling content.
- Task 2 audit ranked contradictory partial-source wording and hidden mixed provenance High; empty emoji space, long-name compression, four equal cards, and fixed-width serving controls Medium; raw technical source IDs and duplicate details Low. The implementation addressed only the first coherent summary/provenance slice.

## Known issues / risks
- Task 3 acceptance is not green. XCUITest sometimes reports invalid activation points for search rows while the keyboard and anchored popover are open. An identified-button tap improved individual Big Mac and Banana runs but failed Banana and Six nuggets in the three-journey run. The exact product-versus-XCUITest cause remains unproven; do not weaken identity assertions or infer reliable handoff. Dataset IDs and their selection closures are stable in source; no demonstrated identity-map defect was found.
- Review Food Task 3 visual layout, Dynamic Type, dark mode, and physical-device feel have not been verified.
- Existing serving-unit wrapping, raw technical source IDs, and duplicate detail presentation remain outside this slice.

## Protected working-tree changes
- Preserve unrelated uncommitted edits: `ios/calorietracker.xcodeproj/project.pbxproj`, `ios/calorietracker/Info.plist`, `ios/calorietracker/InfoPlist.xcstrings`, `ios/calorietracker/LocalModels.xcstrings`, `ios/calorietracker/Localizable.xcstrings`, `ios/calorietracker/WeeklyChallenge.xcstrings`.
- Preserve the existing uncommitted `ios/calorietracker.xcodeproj/xcshareddata/xcschemes/calorietracker.xcscheme` edit. None was staged, committed, reset, or edited during this run.

## Git state
- Prior production commit/push: `3580a99ef` to `origin/main` by normal fast-forward; no force push or history rewrite.
- Uncommitted intended work after this handoff-only checkpoint: existing Task 3 `FoodResultView.swift` and `SearchFoodAcceptanceUITests.swift`. Experimental tap changes were restored; no Search Food production or test change remains from the investigation.
- Unrelated/protected modifications: six files and scheme edit listed above remain local and uncommitted. No staged/conflicted files are intended.

## Recommended next task
With explicit approval, isolate the anchored-popover/keyboard hit-target failure using a bounded UI diagnostic that records the actual post-tap screen and accessibility frames, then fix only the demonstrated Search Food selection problem and rerun all three identity-strict journeys. Do not commit the Review Food slice until that gate is trustworthy.

## Human decision required
Approve any deeper Search Food popover/keyboard hit-target diagnostic or correction beyond this completed, inconclusive investigation.
