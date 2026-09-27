import Foundation
import Testing
@testable import calorietracker

struct AUSNUTFoodSelectionTests {
    @Test func selectedIDAndExplicitGramsUseAUSNUTNutrition() throws {
        let suggestion = try #require(AUSNUTFoodSearchIndex.bundled()?.search("banana").first)
        let result = FoodQueryResolutionService.resolve(selection: suggestion.selection, portion: .grams(118))
        let analysis = try #require(result.analysis)

        #expect(result.isComplete)
        #expect(result.route?.state == .resolvedFood)
        #expect(result.ausnutSelection?.foodID == "16502001")
        #expect(result.components.count == 1)
        #expect(result.components[0].state == .ausnut)
        #expect(result.components[0].sourceItemID == "16502001")
        #expect(analysis.name == "Banana, cavendish, peeled, raw")
        #expect(analysis.calories == 113)
        #expect(analysis.protein == 1.7)
        #expect(analysis.servingSizeGrams == 118)
        #expect(analysis.selectedServingUnit == "g")
        #expect(analysis.nutritionSource == "AUSNUT Australia")
        #expect(analysis.nutritionSourceDetail?.contains("Food Standards Australia New Zealand") == true)
        #if DEBUG
        #expect(result.debugDiagnostics(for: "banana").components[0].selectedResolver == "AustralianNutritionService")
        #endif
    }

    @Test func missingPortionRequiresClarificationWithoutDefaultNutrition() {
        let result = FoodQueryResolutionService.resolve(
            selection: AUSNUTFoodSelection(foodID: "16502001"), portion: nil
        )
        #expect(!result.isComplete)
        #expect(result.analysis == nil)
        #expect(result.route?.state == .needsClarification)
        #expect(result.components[0].state == .unresolved)
        #expect(result.components[0].calories == nil)
    }

    @Test func selectedNaturalMeasureUsesItsRecordedWeight() throws {
        let selection = AUSNUTFoodSelection(foodID: "16502001")
        let identity = try #require(AustralianNutritionService.identity(forID: selection.foodID))
        let mediumIndex = try #require(identity.measures.firstIndex { $0.name == "banana medium" })
        let result = FoodQueryResolutionService.resolve(
            selection: selection, portion: .measure(index: mediumIndex, quantity: 2)
        )
        let analysis = try #require(result.analysis)

        #expect(result.isComplete)
        #expect(analysis.servingSizeGrams == 254.8)
        #expect(analysis.calories == 243)
        #expect(analysis.selectedServingUnit == "banana medium")
        #expect(analysis.selectedServingQuantity == 2)
        #expect(result.components[0].quantity == 2)
    }

    @Test func staleIDAndInvalidAmountsFailClosed() {
        let stale = AUSNUTFoodSelection(foodID: "not-an-ausnut-id")
        let unknown = FoodQueryResolutionService.resolve(selection: stale, portion: .grams(100))
        #expect(!unknown.isComplete)
        #expect(unknown.analysis == nil)
        #expect(unknown.components[0].sourceItemID == nil)

        let banana = AUSNUTFoodSelection(foodID: "16502001")
        for portion: AUSNUTPortion in [
            .grams(0), .grams(-1), .grams(.nan), .grams(.infinity),
            .measure(index: -1, quantity: 1), .measure(index: 999, quantity: 1),
            .measure(index: 0, quantity: 0), .measure(index: 0, quantity: .infinity)
        ] {
            let result = FoodQueryResolutionService.resolve(selection: banana, portion: portion)
            #expect(!result.isComplete)
            #expect(result.analysis == nil)
        }
    }

    @Test func selectedCookedRiceRemainsTheSelectedRecord() throws {
        let selection = AUSNUTFoodSelection(foodID: "12102003")
        let identity = try #require(AustralianNutritionService.identity(forID: selection.foodID))
        let cupIndex = try #require(identity.measures.firstIndex { $0.name == "cup" })
        let result = FoodQueryResolutionService.resolve(
            selection: selection, portion: .measure(index: cupIndex, quantity: 1)
        )
        let analysis = try #require(result.analysis)

        #expect(analysis.name == "Rice, white, cooked")
        #expect(analysis.servingSizeGrams == 190)
        #expect(analysis.calories == 299)
        #expect(result.components[0].sourceItemID == "12102003")
        #expect(analysis.selectedServingUnit == "cup")
    }
}
