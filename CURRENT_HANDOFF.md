---
schema_version: 1
state: HOLD
risk_lane: AMBER
last_task_status: COMPLETE
last_task_risk_lane: GREEN
auto_start_allowed: false
human_decision_required: false
next_task_envelope: NEXT_TASK.md
validation_evidence_ref: "#validation"
---

# FOOD AI — Current Handoff

## Current checkpoint
- Branch: `main`; Data Engine V2 foundation feature commits `38136d1f172660bbe0a228ed377024af9d4840d7` and `5e8c8c1487bab6cc83b4aa2634567b6a066eca9e` pushed to `origin/main`. Verify this handoff-only checkpoint HEAD from Git rather than embedding its own SHA here.
- Current development phase: Data Engine V2 synthetic foundation checkpointed. Repository routing remains HOLD / AMBER for the separate Search Food XCUITest gap; these GREEN results do not authorize automatic launch.

## Last task
- Task: Checkpoint the validated Data Engine V2 foundation.
- Status: **COMPLETE / GREEN**. Two logical feature commits were pushed normally; this handoff is a separate documentation-only checkpoint. The repository-wide Search Food routing status remains HOLD / AMBER.
- Summary: Missing-serving Open Food Facts barcodes use an explicit `100 g` basis; valid source servings remain unchanged. Typed source governance defaults closed. The canonical ingestion model classifies synthetic records PASS / QUARANTINE / REJECT without publishing non-PASS records. No new real dataset was downloaded or approved.

## Changes
- Barcode commit `38136d1f1`: `ios/calorietracker/Services/OpenFoodFactsService.swift` and `ios/calorietrackerTests/OpenFoodFactsServiceTests.swift`.
- Registry/quality-gate commit `5e8c8c148`: new `ios/calorietracker/Services/FoodSourceRegistry.swift`, `ios/calorietracker/Services/CanonicalFoodQualityGate.swift`, and their corresponding two focused test files.
- `CURRENT_HANDOFF.md`: documentation-only checkpoint. No protected, scheme, Search Food HOLD, automation, or dataset file was included in either feature commit.

## Validation
- Baseline: the new named missing-serving test executed and failed as expected (1 execution, 0 pass, 1 fail, 0 skip); the old implementation exposed `1 serving` for 100 g.
- Final combined focused run: **34 executed / 34 passed / 0 failed / 0 skipped**: `OpenFoodFactsServiceTests` 14, `FoodSourceRegistryTests` 7, `CanonicalFoodQualityGateTests` 13; readable `.xcresult`, `xcodebuild test` exit 0. Earlier isolated registry 7/7 and quality-gate 11/11, then 19/19 after the publication-rights gate, also passed.
- Final clean fresh-DerivedData arm64 iOS Simulator app build: **exit 0**, **2** pre-existing unrelated Swift warnings (`ExerciseCatalogWarmup.swift:16`, `RestaurantFoodSearchIndex.swift:102`). Xcode also printed a non-fatal “command failed with exit code 0” diagnostic.
- `git diff --check` and both staged `git diff --cached --check` checks: passed; exact staged file lists and diffs were inspected. No barcode UI, XCUITest, or physical-device acceptance was run.

## Architecture decisions
- A source's reported serving size is evidence of a serving; a missing size is not. `100 g` is an explicit nutrient basis and remains gram-scalable. Do not synthesize a serving or use ungrounded per-serving nutrients.
- Registry publication checks default closed: only an approved source with explicit legal basis, attribution decision, owner/date, capture/version/checksum, parser and upstream identity may bundle or query; bundling separately requires redistribution and bundling rights. Pilot/review/blocked/partner states cannot publish.
- Canonical nutrition basis is typed (`per100g`, `per100mL`, `exactServing`); missing optional nutrients remain unknown rather than zero. An assessment retains raw input and reasons, while only PASS exposes a publishable record. Source rights, provenance, identity, values, serving scale, version, kcal/kJ and macro plausibility, and cross-record ID/GTIN conflicts are checked deterministically. No AI repair or search integration was added.
- Existing FoodAnalysis and Review Food serving-unit handling are reused; no new nutrition system or UI change.

## Known issues / risks
- Search Food exact-ID XCUITest acceptance remains HOLD: local test-only edit has 0 named executions. This does not alter user-accepted normal taps.
- Barcode `100 g` presentation was unit-tested and built, not manually accepted in Review Food. Community-source nutrition quality remains externally variable.
- Registry and gate contain synthetic fixtures only; no AFCD, GS1, BFD, restaurant, or Open Food Facts bulk feed is approved or ingested. Legal/redistribution rights and source-specific parser/normalization quality need evidence before a real pilot.
- Two raw-image-byte photo-removal tests are pre-existing failures. FoodStore delete/combine/cloud-merge durability, Cloud Backup upload prefetch, and the two unrelated compiler warnings remain separate work.

## Protected working-tree changes
- Preserve untouched: `ios/calorietracker.xcodeproj/project.pbxproj`, `ios/calorietracker/Info.plist`, `ios/calorietracker/InfoPlist.xcstrings`, `ios/calorietracker/LocalModels.xcstrings`, `ios/calorietracker/Localizable.xcstrings`, and `ios/calorietracker/WeeklyChallenge.xcstrings`.
- Preserve untouched: `ios/calorietracker.xcodeproj/xcshareddata/xcschemes/calorietracker.xcscheme` and `ios/calorietrackerUITests/SearchFoodAcceptanceUITests.swift`.

## Git state
- Two validated feature commits were pushed normally to `origin/main`; this handoff is a separate documentation-only checkpoint. No history rewrite or force push.
- Pre-existing held Search Food XCUITest edit, six protected edits, and scheme edit remain local, uncommitted, and byte-identical to the pre-checkpoint state.

## Recommended next task
- First real-source pilot: perform a bounded AFCD subset **only after** official licence, commercial use, transformation, bundling, attribution, and version/update rights are verified and approved. Keep the existing Search Food XCUITest HOLD separate; do not treat this recommendation as automatic authorization.

## Human decision required
- None for the synthetic foundation. Explicit legal/source-owner decision is required before actual AFCD ingestion. Automatic continuation remains disallowed because repository routing is HOLD.
