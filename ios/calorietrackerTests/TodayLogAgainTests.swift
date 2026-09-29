import Foundation
import Testing
@testable import calorietracker

@MainActor
struct TodayLogAgainTests {
    @Test func recentHistoryMakesShortcutEligible() throws {
        let (store, suite) = try makeStore()
        defer { UserDefaults(suiteName: suite)?.removePersistentDomain(forName: suite) }
        let now = Date(timeIntervalSince1970: 1_800_000_000)
        #expect(store.recentEntries(days: 30, now: now).first == nil)

        #expect(store.addEntry(entry(at: now.addingTimeInterval(-86_400))))
        #expect(store.recentEntries(days: 30, now: now).first != nil)
    }

    @Test func recentSelectionRetainsExactSavedIdentityWhenNamesAndCaloriesMatch() throws {
        let (store, suite) = try makeStore()
        defer { UserDefaults(suiteName: suite)?.removePersistentDomain(forName: suite) }
        let now = Date(timeIntervalSince1970: 1_800_000_000)
        var older = entry(at: now.addingTimeInterval(-2 * 86_400))
        var newer = entry(at: now.addingTimeInterval(-86_400))
        older.customNote = "older saved entry"
        newer.customNote = "newer saved entry"
        #expect(store.addEntry(older))
        #expect(store.addEntry(newer))

        let latest = try #require(store.recentEntries(days: 30, now: now).first)
        #expect(latest.id == newer.id)
        #expect(latest.id != older.id)
        #expect(latest.name == older.name)
        #expect(latest.calories == older.calories)

        let repeated = latest.duplicatedForLogging(at: now)
        let review = repeated.analysisForRepeatReview()
        #expect(repeated.name == newer.name)
        #expect(repeated.customNote == newer.customNote)
        #expect(repeated.customNote != older.customNote)
        #expect(repeated.nutritionProvenance == newer.nutritionProvenance)
        #expect(review.historicalProvenanceSnapshot == newer.nutritionProvenance)
    }

    @Test func repeatCopyKeepsSavedIdentityServingAndProvenanceForSelectedDay() throws {
        let original = entry(at: Date(timeIntervalSince1970: 1_800_000_000))
        let selectedDay = Date(timeIntervalSince1970: 1_799_000_000)

        let repeated = original.duplicatedForLogging(at: selectedDay)
        let review = repeated.analysisForRepeatReview()

        #expect(repeated.id != original.id)
        #expect(repeated.timestamp == selectedDay)
        #expect(repeated.mealType == .currentMeal)
        #expect(repeated.name == original.name)
        #expect(repeated.servingSizeGrams == original.servingSizeGrams)
        #expect(repeated.selectedServingQuantity == original.selectedServingQuantity)
        #expect(repeated.nutritionProvenance == original.nutritionProvenance)
        #expect(review.historicalProvenanceSnapshot == original.nutritionProvenance)
        #expect(review.calories == original.calories)
    }

    @Test func editingRepeatCopyDoesNotChangeSavedEntry() {
        let original = entry(at: Date(timeIntervalSince1970: 1_800_000_000))
        var repeated = original.duplicatedForLogging(at: original.timestamp)
        repeated.calories = 222
        repeated.servingSizeGrams = 200
        repeated.mealType = .dinner

        #expect(repeated.id != original.id)
        #expect(original.calories == 121)
        #expect(original.servingSizeGrams == 118)
        #expect(original.mealType == .breakfast)
        #expect(original.nutritionProvenance?.displaySource == "AUSNUT Australia")
    }

    @Test func emptyRecentHistoryHasNoShortcutCandidate() throws {
        let (store, suite) = try makeStore()
        defer { UserDefaults(suiteName: suite)?.removePersistentDomain(forName: suite) }
        #expect(store.recentEntries(days: 30).first == nil)
    }

    @Test func reviewSubmissionGateAllowsOnlyOneRepeatedEntry() throws {
        let (store, suite) = try makeStore()
        defer { UserDefaults(suiteName: suite)?.removePersistentDomain(forName: suite) }
        let original = entry(at: Date(timeIntervalSince1970: 1_800_000_000))
        #expect(store.addEntry(original))
        let repeated = original.duplicatedForLogging(at: original.timestamp.addingTimeInterval(60))
        var gate = FoodSubmissionGate()

        if gate.begin() { #expect(store.addEntry(repeated)) }
        if gate.begin() { #expect(store.addEntry(repeated)) }

        #expect(store.entries.count == 2)
        #expect(store.entries.filter { $0.id == repeated.id }.count == 1)
    }

    private func makeStore() throws -> (FoodStore, String) {
        let suite = "TodayLogAgainTests.\(UUID().uuidString)"
        let defaults = try #require(UserDefaults(suiteName: suite))
        return (FoodStore(observesExternalChanges: false, defaults: defaults), suite)
    }

    private func entry(at timestamp: Date) -> FoodEntry {
        let provenance = FoodNutritionProvenance.capture(
            source: "AUSNUT Australia", detail: "FSANZ · AUSNUT 2023",
            confidence: "High", proteinIsKnown: true,
            carbsAreKnown: true, fatIsKnown: true
        )
        return FoodEntry(
            name: "Banana, cavendish, peeled, raw", calories: 121,
            protein: 1.8, carbs: 25.4, fat: 0.3, timestamp: timestamp,
            source: .textInput, mealType: .breakfast,
            servingSizeGrams: 118, selectedServingUnit: "medium banana",
            selectedServingQuantity: 1, nutritionProvenance: provenance
        )
    }
}
