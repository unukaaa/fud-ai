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

    private static let fixture: RestaurantNutritionDataset = {
        let provenance = NutritionProvenance(sourceType: .verifiedRestaurant, restaurantID: "kfc_au", sourceURL: "https://example.test/kfc", country: "AU", capturedDate: "2026-09-25", lastVerifiedDate: "2026-09-25", datasetVersion: "kfc-au-test-1", sourceQuality: "test fixture")
        let item = RestaurantMenuItem(id: "kfc-au-zinger-burger", name: "Zinger Burger", aliases: ["Zinger", "Zinger burger", "KFC Zinger"], category: "burger", servingQuantity: 1, servingUnit: "burger", servingWeightGrams: nil, nutrition: NutritionFacts(calories: 200, kilojoules: 2000, proteinGrams: nil, carbohydrateGrams: nil, fatGrams: nil), components: [], modifiers: [RestaurantModifier(id: "no_mayo", name: "No mayo", aliases: ["no mayo"], removesComponentID: "mayo", addsComponentID: nil, nutritionDelta: nil, provenance: nil)], variants: [], mealConfigurations: [RestaurantMealConfiguration(id: "order", name: "Order", aliases: [], componentIDs: [], clarificationGroups: [RestaurantClarificationGroup(id: "order", reason: .mealCompleteness, title: "Order", choices: [RestaurantClarificationChoice(id: "burger", title: "Burger only", value: "standalone")], allowsMultiple: false, optional: false)])], provenance: provenance)
        let wing = RestaurantMenuItem(id: "kfc-au-wicked-wing", name: "Wicked Wing", aliases: ["Wicked Wings"], category: "chicken", servingQuantity: 1, servingUnit: "piece", servingWeightGrams: nil, nutrition: NutritionFacts(calories: 100, kilojoules: 1000, proteinGrams: nil, carbohydrateGrams: nil, fatGrams: nil), components: [], modifiers: [], variants: [], mealConfigurations: [], provenance: provenance)
        return RestaurantNutritionDataset(datasetVersion: "kfc-au-test-1", source: RestaurantDatasetSource(name: "Test fixture", version: "kfc-au-test-1", sourceURL: "https://example.test/kfc", country: "AU", lastUpdated: "2026-09-25"), restaurants: [Restaurant(id: "kfc_au", name: "KFC Australia", aliases: ["KFC"], country: "AU")], menuItems: [item, wing])
    }()
}
