import Foundation
import Testing
@testable import calorietracker

@MainActor
struct AUSNUTSourcePresentationTests {
    private func exact(_ id: String) throws -> GeminiService.FoodAnalysis {
        let resolution = FoodQueryResolutionService.resolve(
            selection: AUSNUTFoodSelection(foodID: id), portion: .grams(100)
        )
        let analysis = try #require(resolution.analysis)
        #expect(resolution.ausnutSelection?.foodID == id)
        #expect(analysis.foodResolutionComponents.first?.sourceItemID == id)
        #expect(analysis.nutritionSource == "AUSNUT Australia")
        #expect(analysis.ingredients.isEmpty)
        #expect(analysis.proteinIsKnown && analysis.carbsAreKnown && analysis.fatIsKnown)
        return analysis
    }

    private func presentation(_ analysis: GeminiService.FoodAnalysis) -> AUSNUTSourcePresentation {
        AUSNUTSourcePresentation(
            source: analysis.nutritionSource,
            confidence: analysis.nutritionConfidence,
            ingredients: analysis.ingredients
        )
    }

    @Test func recipeDerivedExactAppleHasFullAUSNUTCoverage() throws {
        let apple = try exact("16101015")
        #expect(apple.name == "Apple, raw, not further defined")
        #expect(apple.calories == 54)
        #expect(apple.protein == 0.3)
        #expect(apple.carbs == 12.3)
        #expect(apple.fat == 0)
        #expect(apple.nutritionConfidence == "Medium") // FSANZ derivation confidence is retained.
        let source = presentation(apple)
        #expect(source.coverage == .full)
        #expect(source.badge == "✓ AUSNUT")
    }

    @Test func labelDataExactDarkChocolateHasFullAUSNUTCoverage() throws {
        let chocolate = try exact("28101001")
        #expect(chocolate.name.contains(">60% cocoa solids"))
        #expect(chocolate.calories == 575)
        #expect(chocolate.protein == 8.2)
        #expect(chocolate.carbs == 33.4)
        #expect(chocolate.fat == 44.3)
        #expect(chocolate.nutritionConfidence == "Medium") // Bundled derivation remains Label Data.
        let source = presentation(chocolate)
        #expect(source.coverage == .full)
        #expect(source.badge == "✓ AUSNUT")
        #expect(chocolate.nutritionSourceDetail?.contains("AUSNUT 2023") == true)
    }

    @Test func analysedExactRecordsRemainFullySourced() throws {
        for id in ["16502001", "19101002", "12102003", "28101004", "28101002"] {
            let analysis = try exact(id)
            #expect(analysis.nutritionConfidence == "High")
            #expect(presentation(analysis).coverage == .full)
        }
    }

    @Test func genuinelyPartialIngredientResolutionRemainsPartial() {
        var meal = GeminiService.FoodAnalysis(
            name: "Chicken with mystery sauce", calories: 400,
            protein: 60, carbs: 5, fat: 8, servingSizeGrams: 220
        )
        meal.ingredients = [
            MealIngredient(name: "Grilled chicken breast", grams: 200, calories: 330,
                           protein: 60, carbs: 0, fat: 8),
            MealIngredient(name: "Mystery sauce", grams: 20, calories: 70,
                           protein: 0, carbs: 5, fat: 5)
        ]
        let resolved = AustralianNutritionService.applyingBestAustralianMatch(to: meal)
        #expect(resolved.nutritionSource == "AUSNUT Australia")
        #expect(resolved.nutritionConfidence == "Medium")
        #expect(resolved.ingredients[0].nutritionSource == "AUSNUT Australia")
        #expect(resolved.ingredients[1].nutritionSource == nil)
        let source = presentation(resolved)
        #expect(source.coverage == .partial)
        #expect(source.badge == "⚠️ Partially AUSNUT")
    }

    @Test func mixedAndAIEstimatesKeepTheirOwnSourceClass() {
        let ai = GeminiService.FoodAnalysis(name: "Unresolved meal", calories: 200,
                                            protein: 5, carbs: 25, fat: 8, servingSizeGrams: 100)
        #expect(ai.nutritionSource == "AI estimate")
        #expect(presentation(ai).coverage == .notAUSNUT)
        var mixed = ai
        mixed.nutritionSource = "Mixed nutrition sources"
        #expect(presentation(mixed).coverage == .notAUSNUT)
        #expect(mixed.historicalProvenanceSnapshot.classification == .mixed)
    }

    @Test func savedExactAppleReopensWithoutNutritionOrConfidenceRewrite() throws {
        let original = try exact("16101015")
        let saved = FoodEntry(
            name: original.name, calories: original.calories,
            protein: original.protein, carbs: original.carbs, fat: original.fat,
            source: .textInput, servingSizeGrams: original.servingSizeGrams,
            ingredients: original.ingredients,
            nutritionProvenance: original.historicalProvenanceSnapshot
        )
        let restored = try JSONDecoder().decode(FoodEntry.self, from: JSONEncoder().encode(saved))
        let reopened = restored.analysisForRepeatReview()
        #expect(restored.nutritionProvenance?.classification == .ausnut)
        #expect(restored.nutritionProvenance?.sourceReferences.contains {
            $0.sourceType == .ausnut && $0.itemID == "16101015"
        } == true)
        #expect(reopened.calories == original.calories)
        #expect(reopened.protein == original.protein)
        #expect(reopened.carbs == original.carbs)
        #expect(reopened.fat == original.fat)
        #expect(reopened.nutritionConfidence == "Medium")
        #expect(reopened.nutritionSourceDetail == original.nutritionSourceDetail)
        #expect(presentation(reopened).coverage == .full)
        #expect(presentation(reopened).badge == "✓ AUSNUT")
    }
}
