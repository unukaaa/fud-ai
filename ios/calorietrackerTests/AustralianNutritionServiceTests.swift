import Testing
@testable import calorietracker

struct AustralianNutritionServiceTests {
    @Test func grilledChickenUsesAustralianCookedProfile() {
        let analysis = food(name: "Grilled chicken breast", grams: 200, calories: 330)
        let result = AustralianNutritionService.applyingBestAustralianMatch(to: analysis)

        #expect(result.nutritionSource == "AUSNUT Australia")
        #expect(result.nutritionSourceDetail?.contains("Chicken, breast") == true)
        #expect(result.calories > 300 && result.calories < 330)
        #expect(result.protein > 65)
    }

    @Test func ambiguousGenericRiceStaysAnEstimate() {
        let analysis = food(name: "Cooked rice", grams: 150, calories: 200)
        let result = AustralianNutritionService.applyingBestAustralianMatch(to: analysis)

        #expect(result.nutritionSource == "AI estimate")
        #expect(result.calories == 200)
    }

    @Test func australianWhiteRiceCanUseLocalProfile() {
        let analysis = food(name: "Cooked white jasmine rice", grams: 150, calories: 220)
        let result = AustralianNutritionService.applyingBestAustralianMatch(to: analysis)

        #expect(result.nutritionSource == "AUSNUT Australia")
        #expect(result.calories > 150 && result.calories < 250)
    }

    @Test func plainBananaUsesCanonicalAustralianRawBanana() {
        let analysis = food(name: "Banana", grams: 118, calories: 105)
        let result = AustralianNutritionService.applyingBestAustralianMatch(to: analysis)

        #expect(result.nutritionSource == "AUSNUT Australia")
        #expect(result.nutritionSourceDetail?.contains("Banana, cavendish, peeled, raw") == true)
        #expect(result.calories == 113)
        #expect(result.protein == 1.7)
    }

    @Test func barcodeDataIsNeverOverridden() {
        var analysis = food(name: "Grilled chicken breast", grams: 200, calories: 999)
        analysis.productMetadata = FoodProductMetadata(
            barcode: "9300000000000",
            packageQuantity: nil,
            ingredientsText: nil,
            allergens: [],
            traces: [],
            nutriScore: nil,
            novaGroup: nil,
            ecoScore: nil,
            labels: [],
            categories: [],
            imageURL: nil
        )
        let result = AustralianNutritionService.applyingBestAustralianMatch(to: analysis)

        #expect(result.calories == 999)
        #expect(result.nutritionSource == "AI estimate")
    }

    private func food(name: String, grams: Double, calories: Int) -> GeminiService.FoodAnalysis {
        GeminiService.FoodAnalysis(
            name: name,
            calories: calories,
            protein: 10,
            carbs: 10,
            fat: 10,
            servingSizeGrams: grams
        )
    }
}
