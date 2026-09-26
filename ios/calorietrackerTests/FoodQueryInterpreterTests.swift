import Testing
@testable import calorietracker

struct FoodQueryInterpreterTests {
    @Test func originalDeviceFailurePreservesBothFoods() {
        let result = FoodQueryInterpreter.interpret("zingo buga cog zero")
        #expect(result.items.map(\.interpretedName) == ["Zinger Burger", "Coca-Cola Zero Sugar"])
        #expect(result.interpretedText.contains("Zinger Burger"))
        #expect(result.interpretedText.contains("Coca-Cola Zero Sugar"))
        #expect(result.hasMultipleItems)
    }

    @Test(arguments: [
        ("kfc zinga buga", "Zinger Burger"),
        ("maccas bigmak", "Big Mac"),
        ("six nuggies", "6 Piece Chicken McNuggets"),
        ("wonda melon original", "Wondermelon")
    ])
    func noisyRestaurantLanguageFindsCanonicalFood(input: String, expected: String) {
        let result = FoodQueryInterpreter.interpret(input)
        #expect(result.items.contains { $0.interpretedName == expected })
    }

    @Test func quantityAndGenericLanguageAreConservativelyNormalized() {
        #expect(FoodQueryInterpreter.interpret("too eggs ry toast").interpretedText.contains("2 eggs"))
        #expect(FoodQueryInterpreter.interpret("chiken rice brocoli").interpretedText.contains("chicken rice broccoli"))
        #expect(FoodQueryInterpreter.interpret("coffy milk").interpretedText.contains("coffee milk"))
    }

    @Test(arguments: ["apple", "coke", "burger", "chicken", "wonder"])
    func ambiguousShortInputDoesNotBecomeBrandedFood(input: String) {
        let result = FoodQueryInterpreter.interpret(input)
        #expect(result.items.isEmpty)
        #expect(result.interpretedText == input)
    }

    @Test func modifierRelationshipIsNotSplitFromFood() {
        let result = FoodQueryInterpreter.interpret("big mak no sauce")
        #expect(result.interpretedText.contains("Big Mac no sauce"))
    }

    @Test func productionRestaurantRouteUsesInterpreterBeforeResolver() async {
        let result = await RestaurantNutritionAnalysisService.match(description: "maccas bigmak")
        #expect(result?.menuItem.id == "mcd-au-big-mac")
        #expect(result?.foodAnalysis?.calories == 557)
    }

    @Test func mixedRestaurantDatasetQueryIsNotPartiallyResolved() async {
        let result = await RestaurantNutritionAnalysisService.match(description: "zingo buga cog zero")
        #expect(result == nil)
    }

    @Test func plausibilityGuardFlagsContradictoryTinyResult() {
        let intent = FoodQueryInterpreter.interpret("zinga buga")
        let analysis = GeminiService.FoodAnalysis(name: "Food", calories: 10, protein: 0, carbs: 0, fat: 0, servingSizeGrams: 1)
        let guarded = FoodQueryInterpreter.applyingPlausibilityGuard(to: analysis, intent: intent)
        #expect(guarded.nutritionConfidence == "Low")
        #expect(guarded.nutritionSourceDetail?.contains("conflict") == true)
    }
}
