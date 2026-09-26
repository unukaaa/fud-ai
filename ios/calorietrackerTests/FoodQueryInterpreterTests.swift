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

    @Test(arguments: [
        ("one egg", "1 egg"), ("two eggs", "2 eggs"), ("too eggs", "2 eggs"),
        ("four eggs", "4 eggs"), ("for wicked wings", "4 Wicked Wing")
    ])
    func spokenQuantitiesStayAttached(input: String, expected: String) {
        #expect(FoodQueryInterpreter.interpret(input).interpretedText.contains(expected))
    }

    @Test(arguments: [("six nuggies", "6"), ("ten nuggets", "10")])
    func nuggetQuantitiesSurviveInterpretation(input: String, quantity: String) {
        let result = FoodQueryInterpreter.interpret(input).interpretedText.lowercased()
        #expect(result.contains(quantity))
        #expect(result.contains("nugget"))
    }

    @Test(arguments: [
        ("nana", "banana"), ("aple", "apple"), ("stake mash veg", "steak mash vegetables"),
        ("greek yog berries", "greek yoghurt berries"), ("coffy milk", "coffee milk"),
        ("latay", "latte"), ("too eggs ry toast", "2 eggs rye toast")
    ])
    func ordinaryNoiseIsRecoveredWithoutBranding(input: String, expected: String) {
        let result = FoodQueryInterpreter.interpret(input)
        #expect(result.interpretedText == expected)
        #expect(result.items.isEmpty)
    }

    @Test(arguments: [
        "zero", "meal", "box", "chips", "toast", "rice", "milk", "shake", "wing", "mac",
        "big", "original", "medium", "large", "water", "juice", "coffee", "latte"
    ])
    func additionalShortGenericInputsDoNotBecomeBranded(input: String) {
        #expect(FoodQueryInterpreter.interpret(input).items.isEmpty)
    }

    @Test func punctuationCasingAndFillerPreserveBothRestaurantFoods() {
        for input in [
            "ZINGER BURGER COKE ZERO", "Zinger burger, Coke Zero", "zinger burger + coke zero",
            "zinger burger and coke zero", "i had a zinger burger and coke zero"
        ] {
            let names = FoodQueryInterpreter.interpret(input).items.map(\.interpretedName)
            #expect(names.contains("Zinger Burger"))
            #expect(names.contains("Coca-Cola Zero Sugar"))
        }
    }

    @Test func deterministicRestaurantRouteRejectsUnresolvedFoodRemainder() async {
        #expect(await RestaurantNutritionAnalysisService.match(description: "Big Mac apple") == nil)
        #expect(await RestaurantNutritionAnalysisService.match(description: "zinger burger homemade potato salad") == nil)
        #expect(await RestaurantNutritionAnalysisService.match(description: "maccas nuggets banana") == nil)
    }

    @Test func cleanQuantityAndRestaurantContextStillResolve() async {
        let wings = await RestaurantNutritionAnalysisService.match(description: "2 Wicked Wings")
        #expect(wings?.menuItem.id == "kfc-au-wicked-wing")
        #expect(wings?.quantity == 2)
        let zinger = await RestaurantNutritionAnalysisService.match(description: "kfc zinga buga")
        #expect(zinger?.menuItem.id == "kfc-au-zinger-burger")
    }

    @Test func clarificationPayloadStillPreservesParentMeal() async {
        let bigMac = await RestaurantNutritionAnalysisService.match(
            description: "Big Mac meal\nClarification: Size: Medium with Coke No Sugar"
        )
        #expect(bigMac?.menuItem.id == "mcd-au-big-mac-meal")
        #expect(bigMac?.foodAnalysis?.calories == 876)
        let boost = await RestaurantNutritionAnalysisService.match(
            description: "Wondermelon\nClarification: Size: Original"
        )
        #expect(boost?.menuItem.id == "boost-au-wondermelon")
        #expect(boost?.foodAnalysis?.calories == 191)
    }

    @Test func representativeInterpreterPerformanceRemainsInteractive() {
        let queries = [
            "banana",
            "big mac medium chips coke zero",
            "zinger burger coke zero 2 wicked wings",
            "i had 2 eggs rye toast avocado coffee skim milk"
        ]
        let clock = ContinuousClock()
        let elapsed = clock.measure {
            for query in queries { _ = FoodQueryInterpreter.interpret(query) }
        }
        #expect(elapsed < .seconds(2))
    }
}
