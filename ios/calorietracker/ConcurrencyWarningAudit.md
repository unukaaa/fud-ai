# Swift concurrency warning audit

## Baseline

The targeted iOS build completed successfully. The current baseline contains five warning locations:

- `ExerciseCatalogWarmup.swift`: detached warm-up accesses the actor-isolated exercise catalog.
- `FreeExerciseDBAssetResolver.swift`: image URL resolution crosses the actor boundary from a synchronous helper.
- `WorkoutsView.swift`: detached workout filtering calls an actor-isolated filter method.

These warnings are one architectural group: the workout catalog intentionally performs loading and filtering away from the main actor, while the project currently gives the catalog helpers main-actor isolation by default.

## Decision

This group is intentionally unresolved. Moving the work to the main actor could reintroduce UI hitches, while making the whole catalog and its image/file dependencies nonisolated would require a broader Sendable/ownership review. No `@MainActor` blanket annotation, unsafe isolation escape, warning suppression, or runtime-behaviour change was introduced.

## Phase 2D tests

The existing clarification predicate and prompt types are private implementation details inside `ContentView.swift`, and the current test target has no presentation-independent seam for them. Adding tests would require extracting/refactoring that UI state or mocking the Gemini pipeline, which is outside this maintenance scope. The existing real-device Phase 2D coverage remains the source of truth; no new UI or AI tests were added.
