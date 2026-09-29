import Foundation
import Testing
@testable import calorietracker

/// The source shown when a saved food is opened and logged again must be the
/// historical claim accepted at first logging, not a fresh name lookup.
@MainActor
struct SavedNutritionSourceRoundTripTests {
    @Test func verifiedRestaurantSourceSurvivesSaveReloadAndRepeat() async throws {
        let selection = RestaurantFoodSelection(
            restaurantID: "mcdonalds_au", itemID: "mcd-au-big-mac", variantID: nil
        )
        let resolution = await FoodQueryResolutionService.resolve(selection: selection)
        let original = try #require(resolution.analysis)
        let result = try roundTrip(original)

        #expect(original.nutritionSource == "Verified restaurant nutrition")
        #expect(result.saved.name == original.name)
        #expect(result.reopened.name == original.name)
        #expect(result.reopened.nutritionSource == original.nutritionSource)
        #expect(result.reopened.nutritionSourceDetail == original.nutritionSourceDetail)
        #expect(result.reopened.nutritionConfidence == original.nutritionConfidence)
        #expect(result.saved.nutritionProvenance?.classification == .verifiedRestaurant)
        #expect(result.saved.nutritionProvenance?.sourceReferences.contains {
            $0.sourceType == .restaurant && $0.itemID == selection.itemID
        } == true)
        #expect(result.reopened.historicalProvenanceSnapshot == result.saved.nutritionProvenance)
    }

    @Test func ausnutSourceSurvivesSaveReloadAndRepeat() throws {
        let resolution = FoodQueryResolutionService.resolve(
            selection: AUSNUTFoodSelection(foodID: "16502001"), portion: .grams(118)
        )
        let original = try #require(resolution.analysis)
        let result = try roundTrip(original)

        #expect(original.nutritionSource == "AUSNUT Australia")
        #expect(result.saved.name == original.name)
        #expect(result.reopened.servingSizeGrams == original.servingSizeGrams)
        #expect(result.reopened.nutritionSource == original.nutritionSource)
        #expect(result.reopened.nutritionSourceDetail == original.nutritionSourceDetail)
        #expect(result.reopened.nutritionConfidence == original.nutritionConfidence)
        #expect(result.saved.nutritionProvenance?.classification == .ausnut)
        #expect(result.saved.nutritionProvenance?.sourceReferences.contains {
            $0.sourceType == .ausnut && $0.itemID == "16502001"
        } == true)
        #expect(result.reopened.historicalProvenanceSnapshot == result.saved.nutritionProvenance)
    }

    @Test func aiEstimateSourceSurvivesSaveReloadAndRepeat() throws {
        let original = GeminiService.FoodAnalysis(
            name: "Homemade potato salad", calories: 180, protein: 3,
            carbs: 24, fat: 8, servingSizeGrams: 150
        )
        let result = try roundTrip(original)

        #expect(result.saved.name == original.name)
        #expect(result.reopened.nutritionSource == original.nutritionSource)
        #expect(result.reopened.nutritionConfidence == original.nutritionConfidence)
        #expect(result.saved.nutritionProvenance?.classification == .aiEstimate)
    }

    @Test func mixedSourceKeepsBothParentAndIngredientProvenance() throws {
        var original = GeminiService.FoodAnalysis(
            name: "Zinger Burger + homemade potato salad", calories: 628,
            protein: 35, carbs: 60, fat: 29, servingSizeGrams: 300
        )
        original.ingredients = [
            MealIngredient(name: "Zinger Burger", grams: 150, calories: 448,
                           protein: 32, carbs: 36, fat: 21,
                           nutritionSource: "Verified restaurant nutrition",
                           nutritionSourceDetail: "KFC Australia"),
            MealIngredient(name: "Homemade potato salad", grams: 150, calories: 180,
                           protein: 3, carbs: 24, fat: 8,
                           nutritionSource: "AI estimate")
        ]
        original.nutritionSource = "Mixed nutrition sources"
        original.nutritionSourceDetail = "KFC Australia · AI estimate"
        original.foodResolutionComponents = [FoodResolutionComponent(
            query: "Zinger Burger", name: "Zinger Burger", state: .verifiedRestaurant,
            quantity: 1, calories: 448, protein: 32, carbs: 36, fat: 21,
            sourceDetail: "KFC Australia", sourceItemID: "kfc-au-zinger-burger"
        )]
        let result = try roundTrip(original)

        #expect(result.saved.ingredients.map(\.nutritionSource) == original.ingredients.map(\.nutritionSource))
        #expect(result.reopened.ingredients.map(\.nutritionSource) == original.ingredients.map(\.nutritionSource))
        #expect(result.reopened.nutritionSource == original.nutritionSource)
        #expect(result.reopened.nutritionSourceDetail == original.nutritionSourceDetail)
        #expect(result.saved.nutritionProvenance?.classification == .mixed)
        #expect(result.saved.nutritionProvenance?.sourceReferences.contains {
            $0.sourceType == .restaurant && $0.itemID == "kfc-au-zinger-burger"
        } == true)
        #expect(result.reopened.historicalProvenanceSnapshot == result.saved.nutritionProvenance)
    }

    @Test func legacyEntryDecodesWithHonestUnknownSource() throws {
        let oldEntry = FoodEntry(
            name: "Big Mac", calories: 557, protein: 25, carbs: 45, fat: 30,
            source: .textInput
        )
        let encoded = try JSONEncoder().encode(oldEntry)
        let payload = try #require(JSONSerialization.jsonObject(with: encoded) as? [String: Any])
        #expect(payload["nutritionProvenance"] == nil)

        let decoded = try JSONDecoder().decode(FoodEntry.self, from: encoded)
        #expect(decoded.nutritionProvenance == nil)
        #expect(decoded.name == oldEntry.name)
        #expect(decoded.calories == oldEntry.calories)
        #expect(decoded.source == .textInput)
        let reopened = decoded.analysisForRepeatReview()
        #expect(reopened.nutritionSource == "Source not recorded")
        #expect(reopened.nutritionSource != "AI estimate")
    }

    @Test func repeatAndResaveKeepHistoricalSnapshotWithoutResolvingAgain() async throws {
        let resolution = await FoodQueryResolutionService.resolve(selection: RestaurantFoodSelection(
            restaurantID: "mcdonalds_au", itemID: "mcd-au-big-mac", variantID: nil
        ))
        let original = try #require(resolution.analysis)
        let first = try roundTrip(original)
        let second = try roundTrip(first.reopened)

        #expect(second.saved.nutritionProvenance == first.saved.nutritionProvenance)
        #expect(second.reopened.historicalProvenanceSnapshot == first.saved.nutritionProvenance)
    }

    @Test func partialKnownMacroFlagsSurviveRoundTrip() throws {
        var original = GeminiService.FoodAnalysis(
            name: "Partially verified food", calories: 220, protein: 0,
            carbs: 30, fat: 0, servingSizeGrams: 100
        )
        original.nutritionSource = "Verified restaurant nutrition"
        original.nutritionSourceDetail = "Published calories and carbohydrate only"
        original.nutritionConfidence = "Medium"
        original.proteinIsKnown = false
        original.fatIsKnown = false

        let result = try roundTrip(original)
        #expect(result.saved.nutritionProvenance?.classification == .partiallyVerifiedRestaurant)
        #expect(result.reopened.nutritionSourceDetail == original.nutritionSourceDetail)
        #expect(result.reopened.proteinIsKnown == false)
        #expect(result.reopened.carbsAreKnown == true)
        #expect(result.reopened.fatIsKnown == false)
    }

    @Test func entryCopiesRetainSnapshotAndCombinedIngredientSource() throws {
        let original = GeminiService.FoodAnalysis(
            name: "Homemade potato salad", calories: 180, protein: 3,
            carbs: 24, fat: 8, servingSizeGrams: 150
        )
        let saved = try roundTrip(original).saved
        let duplicate = saved.duplicatedForLogging(at: .now)
        let withIngredients = saved.withIngredients([
            MealIngredient(name: "Potato", grams: 150, calories: 180,
                           protein: 3, carbs: 24, fat: 8)
        ])

        #expect(duplicate.nutritionProvenance == saved.nutritionProvenance)
        #expect(withIngredients.nutritionProvenance == saved.nutritionProvenance)
        #expect(saved.asMealIngredient().nutritionSource == "AI estimate")
    }

    private func roundTrip(_ original: GeminiService.FoodAnalysis) throws
        -> (saved: FoodEntry, reopened: GeminiService.FoodAnalysis) {
        let suite = "SavedNutritionSourceRoundTripTests.\(UUID().uuidString)"
        let defaults = try #require(UserDefaults(suiteName: suite))
        defer { defaults.removePersistentDomain(forName: suite) }

        // Match FoodResultView's save mapping, including its historical snapshot.
        let entry = FoodEntry(
            name: original.name, calories: original.calories,
            protein: original.protein, carbs: original.carbs, fat: original.fat,
            source: .textInput, servingSizeGrams: original.servingSizeGrams,
            servingUnitOptions: original.servingUnitOptions,
            selectedServingUnit: original.selectedServingUnit,
            selectedServingQuantity: original.selectedServingQuantity,
            ingredients: original.ingredients, productMetadata: original.productMetadata,
            nutritionProvenance: original.historicalProvenanceSnapshot
        )
        let store = FoodStore(observesExternalChanges: false, defaults: defaults)
        #expect(store.addEntry(entry))
        let saved = try #require(FoodStore(observesExternalChanges: false, defaults: defaults).entries.first)
        let repeated = saved.duplicatedForLogging(at: .now)

        let reopened = repeated.analysisForRepeatReview()
        return (saved, reopened)
    }
}
