import Testing
@testable import calorietracker

struct RestaurantNutritionProviderTests {
    private let provider: LocalRestaurantNutritionProvider

    init() {
        provider = LocalRestaurantNutritionProvider(store: RestaurantDatasetStore(dataset: Self.fixture))
    }

    @Test func kfcZingerIdentifiesRestaurantAndItem() async {
        let result = await provider.match(RestaurantFoodQuery(rawText: "KFC Zinger", restaurantID: nil, itemTerms: [], quantity: nil, modifierTerms: []))
        #expect(result?.restaurant.id == "kfc_au")
        #expect(result?.menuItem.id == "kfc-au-zinger-burger")
        #expect(result?.clarificationPlan.groups.first?.reason == .mealCompleteness)
    }

    @Test func zingerContextWorksWithoutRestaurantName() async {
        let result = await provider.match(RestaurantFoodQuery(rawText: "Zinger", restaurantID: "kfc_au", itemTerms: [], quantity: nil, modifierTerms: []))
        #expect(result?.menuItem.name == "Zinger Burger")
    }

    @Test func noMayoModifierIsRetained() async {
        let result = await provider.match(RestaurantFoodQuery(rawText: "Zinger burger no mayo", restaurantID: "kfc_au", itemTerms: [], quantity: nil, modifierTerms: ["no mayo"]))
        #expect(result?.matchedModifiers.map(\.id) == ["no_mayo"])
    }

    @Test func wickedWingsQuantityDoesNotAskAboutUnrelatedMeal() async {
        let result = await provider.match(RestaurantFoodQuery(rawText: "2 Wicked Wings", restaurantID: "kfc_au", itemTerms: [], quantity: 2, modifierTerms: []))
        #expect(result?.menuItem.id == "kfc-au-wicked-wing")
        #expect(result?.quantity == 2)
        #expect(result?.clarificationPlan.isEmpty == true)
    }

    @Test func wickedWingsNutritionScalesByQuantity() async {
        let result = await provider.match(RestaurantFoodQuery(rawText: "3 Wicked Wings", restaurantID: "kfc_au", itemTerms: [], quantity: 3, modifierTerms: []))
        #expect(abs((result?.nutrition?.kilojoules ?? 0) - 3000) < 0.001)
        #expect(abs((result?.nutrition?.calories ?? 0) - 300) < 0.001)
    }

    @Test func combinedMealRetainsComponentsAndModifier() async {
        let result = await provider.match(RestaurantFoodQuery(rawText: "KFC Zinger burger no mayo and 2 Wicked Wings", restaurantID: nil, itemTerms: [], quantity: nil, modifierTerms: ["no mayo"]))
        #expect(result?.menuItem.id == "kfc-au-zinger-burger")
        #expect(result?.matchedModifiers.map(\.id) == ["no_mayo"])
        #expect(result?.additionalComponents.map(\.menuItem.id) == ["kfc-au-wicked-wing"])
        #expect(result?.additionalComponents.first?.quantity == 2)
        #expect(result?.clarificationPlan.isEmpty == true)
    }

    @Test func aliasesNormalizeAndDatasetMetadataDecodes() {
        #expect(RestaurantQueryNormalizer.normalize("KFC’s ZINGER-BURGER") == "kfcs zinger burger")
        #expect(RestaurantQueryNormalizer.quantity(in: "2 Wicked Wings") == 2)
        #expect(Self.fixture.datasetVersion == "kfc-au-test-1")
        #expect(Self.fixture.source.country == "AU")
        #expect(Self.fixture.menuItems.first?.provenance?.sourceType == .verifiedRestaurant)
    }

    @Test func verifiedRecordsAreAustralianOnly() {
        #expect(Self.fixture.menuItems.compactMap(\.provenance).allSatisfy { $0.country == "AU" && $0.sourceType == .verifiedRestaurant })
    }

    @Test func zingerBoxUsesPublishedDefaultAndClarifiesOnlyUnknownComponents() async {
        let result = await provider.match(RestaurantFoodQuery(rawText: "Zinger Box", restaurantID: "kfc_au", itemTerms: [], quantity: nil, modifierTerms: []))
        #expect(result?.menuItem.id == "kfc-au-zinger-box-regular")
        #expect(result?.menuItem.nutrition?.kilojoules == 4289)
        #expect(result?.clarificationPlan.groups.map(\.id) == ["chicken", "first-side", "second-side", "drink"])
    }

    @Test func specifiedBoxChickenAndDrinkSuppressThoseQuestions() async {
        let result = await provider.match(RestaurantFoodQuery(rawText: "Zinger Box with 3 Wicked Wings and Pepsi Max", restaurantID: "kfc_au", itemTerms: [], quantity: nil, modifierTerms: []))
        #expect(result?.menuItem.id == "kfc-au-zinger-box-regular")
        #expect(result?.clarificationPlan.groups.map(\.id) == ["first-side", "second-side"])
    }

    @Test func boostWondermelonResolvesAndClarifiesSize() async {
        let result = await provider.match(RestaurantFoodQuery(rawText: "Boost Wondermelon", restaurantID: nil, itemTerms: [], quantity: nil, modifierTerms: []))
        #expect(result?.restaurant.id == "boost_au")
        #expect(result?.menuItem.id == "boost-au-wondermelon")
        #expect(result?.clarificationPlan.groups.map(\.reason) == [.size])
    }

    @Test func boostExplicitSizeUsesVerifiedMacros() async {
        let result = await provider.match(RestaurantFoodQuery(rawText: "large Wondermelon", restaurantID: "boost_au", itemTerms: [], quantity: nil, modifierTerms: []))
        #expect(result?.selectedVariant?.id == "boost-au-wondermelon-original")
        #expect(result?.nutrition?.kilojoules == 798)
        #expect(result?.nutrition?.proteinGrams == 13.1)
        #expect(result?.clarificationPlan.isEmpty == true)
    }

    @Test func boostProteinAdditionIsRetainedWithoutInventedDelta() async {
        let result = await provider.match(RestaurantFoodQuery(rawText: "medium Wondermelon with protein", restaurantID: "boost_au", itemTerms: [], quantity: nil, modifierTerms: ["with protein"]))
        #expect(result?.selectedVariant?.id == "boost-au-wondermelon-medium")
        #expect(result?.matchedModifiers.map(\.id) == ["boost-protein-booster"])
        #expect(result?.nutrition?.kilojoules == 651)
        #expect(result?.matchedModifiers.first?.nutritionDelta == nil)
    }

    @Test func verifiedMatchConvertsToReviewableFoodAnalysis() async {
        let result = await provider.match(RestaurantFoodQuery(rawText: "large Wondermelon", restaurantID: "boost_au", itemTerms: [], quantity: nil, modifierTerms: []))
        let analysis = result?.foodAnalysis
        #expect(analysis?.calories == 191)
        #expect(analysis?.protein == 13.1)
        #expect(analysis?.nutritionSource == "Verified restaurant nutrition")
        #expect(analysis?.nutritionConfidence == "High")
        #expect(analysis?.servingSizeIsKnown == false)
    }

    @Test func vagueZingerMealFallsBackInsteadOfUsingBurgerCalories() async {
        let result = await provider.match(RestaurantFoodQuery(rawText: "KFC Zinger Meal", restaurantID: nil, itemTerms: [], quantity: nil, modifierTerms: []))
        #expect(result == nil)
    }

    @Test func burgerOnlyClarificationDoesNotRepeat() async {
        let result = await provider.match(RestaurantFoodQuery(rawText: "KFC Zinger Clarification: Order: Zinger Burger only", restaurantID: nil, itemTerms: [], quantity: nil, modifierTerms: []))
        #expect(result?.menuItem.id == "kfc-au-zinger-burger")
        #expect(result?.clarificationPlan.isEmpty == true)
    }

    @Test func resolvedBoxClarificationsDoNotRepeat() async {
        let text = "KFC Zinger Box Clarification: Chicken: 3 Wicked Wings; First side: Regular Chips; Second side: Regular Potato & Gravy; Drink: Regular Pepsi Max"
        let result = await provider.match(RestaurantFoodQuery(rawText: text, restaurantID: nil, itemTerms: [], quantity: nil, modifierTerms: []))
        #expect(result?.menuItem.id == "kfc-au-zinger-box-regular")
        #expect(result?.clarificationPlan.isEmpty == true)
    }

    private static let fixture: RestaurantNutritionDataset = {
        let provenance = NutritionProvenance(sourceType: .verifiedRestaurant, restaurantID: "kfc_au", sourceURL: "https://example.test/kfc", country: "AU", capturedDate: "2026-09-25", lastVerifiedDate: "2026-09-25", datasetVersion: "kfc-au-test-1", sourceQuality: "test fixture")
        let item = RestaurantMenuItem(id: "kfc-au-zinger-burger", name: "Zinger Burger", aliases: ["Zinger", "Zinger burger", "KFC Zinger"], category: "burger", servingQuantity: 1, servingUnit: "burger", servingWeightGrams: nil, nutrition: NutritionFacts(calories: 200, kilojoules: 2000, proteinGrams: nil, carbohydrateGrams: nil, fatGrams: nil), components: [], modifiers: [RestaurantModifier(id: "no_mayo", name: "No mayo", aliases: ["no mayo"], removesComponentID: "mayo", addsComponentID: nil, nutritionDelta: nil, provenance: nil)], variants: [], mealConfigurations: [RestaurantMealConfiguration(id: "order", name: "Order", aliases: [], componentIDs: [], clarificationGroups: [RestaurantClarificationGroup(id: "order", reason: .mealCompleteness, title: "Order", choices: [RestaurantClarificationChoice(id: "burger", title: "Burger only", value: "standalone")], allowsMultiple: false, optional: false)])], provenance: provenance)
        let wing = RestaurantMenuItem(id: "kfc-au-wicked-wing", name: "Wicked Wing", aliases: ["Wicked Wings"], category: "chicken", servingQuantity: 1, servingUnit: "piece", servingWeightGrams: nil, nutrition: NutritionFacts(calories: 100, kilojoules: 1000, proteinGrams: nil, carbohydrateGrams: nil, fatGrams: nil), components: [], modifiers: [], variants: [], mealConfigurations: [], provenance: provenance)
        let box = RestaurantMenuItem(id: "kfc-au-zinger-box-regular", name: "Zinger Burger Box - Regular", aliases: ["Zinger Box", "Zinger Burger Box"], category: "meal", servingQuantity: 1, servingUnit: "box", servingWeightGrams: nil, nutrition: NutritionFacts(calories: 1025.8, kilojoules: 4289, proteinGrams: nil, carbohydrateGrams: nil, fatGrams: nil), components: [], modifiers: [], variants: [], mealConfigurations: [RestaurantMealConfiguration(id: "box-components", name: "Components", aliases: [], componentIDs: [], clarificationGroups: [RestaurantClarificationGroup(id: "chicken", reason: .component, title: "Chicken", choices: [], allowsMultiple: false, optional: false), RestaurantClarificationGroup(id: "first-side", reason: .component, title: "First side", choices: [], allowsMultiple: false, optional: false), RestaurantClarificationGroup(id: "second-side", reason: .component, title: "Second side", choices: [], allowsMultiple: false, optional: false), RestaurantClarificationGroup(id: "drink", reason: .component, title: "Drink", choices: [], allowsMultiple: false, optional: false)])], provenance: provenance)
        let boostProvenance = NutritionProvenance(sourceType: .verifiedRestaurant, restaurantID: "boost_au", sourceURL: "https://www.boostjuice.com.au/", country: "AU", capturedDate: "2026-09-25", lastVerifiedDate: "2026-09-25", datasetVersion: "boost-au-test-1", sourceQuality: "official test fixture")
        let boost = RestaurantMenuItem(id: "boost-au-wondermelon", name: "Wondermelon", aliases: ["Wondermelon", "Wonder Melon", "Boost Wondermelon"], category: "smoothie", servingQuantity: 1, servingUnit: "drink", servingWeightGrams: nil, nutrition: nil, components: [], modifiers: [RestaurantModifier(id: "boost-protein-booster", name: "Protein booster", aliases: ["with protein", "protein"], removesComponentID: nil, addsComponentID: "boost-protein-booster", nutritionDelta: nil, provenance: boostProvenance)], variants: [RestaurantMenuItemVariant(id: "boost-au-wondermelon-medium", name: "Medium", aliases: ["medium", "med"], nutrition: NutritionFacts(calories: 156, kilojoules: 651, proteinGrams: 10.2, carbohydrateGrams: 23, fatGrams: 1.9), provenance: boostProvenance), RestaurantMenuItemVariant(id: "boost-au-wondermelon-original", name: "Original", aliases: ["large", "original", "ori"], nutrition: NutritionFacts(calories: 191, kilojoules: 798, proteinGrams: 13.1, carbohydrateGrams: 27.3, fatGrams: 2.3), provenance: boostProvenance)], mealConfigurations: [], provenance: boostProvenance)
        return RestaurantNutritionDataset(datasetVersion: "kfc-au-test-1", source: RestaurantDatasetSource(name: "Test fixture", version: "kfc-au-test-1", sourceURL: "https://example.test/kfc", country: "AU", lastUpdated: "2026-09-25"), restaurants: [Restaurant(id: "kfc_au", name: "KFC Australia", aliases: ["KFC"], country: "AU"), Restaurant(id: "boost_au", name: "Boost Juice Australia", aliases: ["Boost", "Boost Juice"], country: "AU")], menuItems: [item, wing, box, boost])
    }()
}
