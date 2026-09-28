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
- Review Food V2 presentation commit: `97e050d6031de1e0fc6c0621a37444809c5d2e4e`.
- ChatView accessibility commit: `0a67b27c5393dcbac51e91197c8c3ebdb1dfa93b`.
- Review Food and ChatView commits, plus the three Data Integrity commits below, were pushed normally to `origin/main`. Read Git for the current handoff-checkpoint HEAD SHA.
- Overall routing remains **HOLD**. The old `NEXT_TASK.md` pilot envelope is not authority for the current product work; its mismatch with this handoff fails closed.

## Last task
- Task: Checkpoint the completed three-task Data Integrity run.
- Status: **COMPLETE / GREEN** for this Git-only checkpoint; overall repository routing remains **HOLD** for unrelated Search Food decisions and acceptance gaps.
- Summary: WeightStore chronology, PortionSuggestionPolicy maximum, and DiaryImporter rejection coverage were committed as separate validated slices and pushed. No new product work was done in this checkpoint.

## Changes
- Data Integrity commits: `72dfdf6ec3614394f2f09da37993fb052676838e` (WeightStore chronology and its six tests), `aec7683223c2fc42c6cf6b807619c6f4218b27fd` (portion cap and its four tests), and `20a5f337d9fa0f84dc65a32000e4493eb7314e23` (DiaryImporter rejection tests). Other held work remains untouched.
- Review Food commit files: `ios/calorietracker/Views/FoodResultView.swift`, `ios/calorietracker/Views/ServingUnitEditor.swift`.
- Chat accessibility commit file: `ios/calorietracker/Views/ChatView.swift`.

## Validation
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
- Missing automated UI execution was not treated as a pass. The independent presentation/accessibility commits are checkpointed on clean compilation, source-diff review, and the stated manual Review Food evidence, with the untested configurations and VoiceOver limitation explicit.
- A selected Search Food suggestion still uses its stable dataset identity; the test-only interaction correction is held until its named tests execute.

## Known issues / risks
- CloudBackupService lookup-error semantics and FoodStore save/replacement durability were not part of this three-task run; they remain separate data-integrity risks for a read-only comparison before any implementation choice.
- The targeted Simulator restart restored two unit-test worker launches, but it is not a proven permanent fix. Search Food XCUITest startup and finalization still require a bounded named-test verdict before that held test slice can be accepted.
- Search Food XCUITest worker startup/finalization is unreliable. Do not weaken identity assertions or infer automated acceptance from manual taps.
- Review Food mixed-source/photo layouts and the shared serving editor in Edit Food Entry need later manual checks; the accepted examples do not cover them.
- ChatView labels need later VoiceOver judgment; idle-mic semantics were not changed.
- Search Food `protein bar`/reordered-token discovery needs a product decision before changing the conservative whole-query boundary. The restaurant-index initialization warning/performance path needs separate ownership evidence.
- Home-dashboard macro-card wrapping at large text and catalog line-16 concurrency ownership remain separate backlog items.

## Protected working-tree changes
- Preserve the existing unrelated edits to `ios/calorietracker.xcodeproj/project.pbxproj`, `ios/calorietracker/Info.plist`, `ios/calorietracker/InfoPlist.xcstrings`, `ios/calorietracker/LocalModels.xcstrings`, `ios/calorietracker/Localizable.xcstrings`, and `ios/calorietracker/WeeklyChallenge.xcstrings`.
- Preserve the separate `ios/calorietracker.xcodeproj/xcshareddata/xcschemes/calorietracker.xcscheme` edit. All seven contents, plus the held Search Food test, were hash-checked unchanged across the Data Integrity commits. None was staged, committed, reset, stashed, or modified by this checkpoint.

## Git state
- Committed and pushed: Review Food and ChatView commits above, then the three exact Data Integrity commits listed above, followed by this handoff-only checkpoint. No force push, rebase, reset, or history rewrite.
- Intentionally uncommitted: `ios/calorietrackerUITests/SearchFoodAcceptanceUITests.swift` remains a separate HOLD slice with 0 named executions.
- Unrelated/protected modifications: the six files and scheme listed above. No staged files remain after the three Data Integrity commits and handoff checkpoint.

## Recommended next task
In a separate approved task, perform a read-only comparison of CloudBackupService presence-lookup errors versus FoodStore save/replacement durability, then recommend the smallest safe next data-integrity boundary. Do not auto-start it from this handoff.

## Human decision required
Before broadening reordered-token Search Food discovery (for example `protein bar`), decide what positive whole-food identity evidence is required without promoting a component of a composed meal. This is not permission to start that work automatically.
