import Testing
@testable import calorietracker

struct RestaurantFoodSearchIndexTests {
    private func bundledIndex() throws -> RestaurantFoodSearchIndex {
        try #require(RestaurantFoodSearchIndex.bundled())
    }

    @Test func brandOnlyQueriesUseDatasetAliasesAndOfferAvailableItems() throws {
        let index = try bundledIndex()
        let kfc = index.search("KFC")
        #expect(kfc.first?.kind == .brand)
        #expect(kfc.first?.restaurantID == "kfc_au")
        #expect(kfc.first?.itemID == nil)
        #expect(kfc.first?.subtitle == "Verified items available")
        #expect(kfc.count == 6)
        #expect(kfc.dropFirst().allSatisfy { $0.kind == .product && $0.restaurantID == "kfc_au" })

        let maccas = index.search("Maccas")
        #expect(maccas.first?.kind == .brand)
        #expect(maccas.first?.restaurantID == "mcdonalds_au")
        #expect(maccas.dropFirst().allSatisfy { $0.restaurantID == "mcdonalds_au" })
        #expect(index.search("McDonald's").first?.id == maccas.first?.id)
    }

    @Test func productNamesPrefixesAndAliasesHaveStableRanking() throws {
        let index = try bundledIndex()
        let zinger = index.search("Zinger")
        #expect(zinger.first?.itemID == "kfc-au-zinger-burger")
        #expect(zinger.first?.matchReason == .exact)
        #expect(zinger.contains { $0.itemID == "kfc-au-zinger-meal-regular" })
        #expect(zinger.contains { $0.itemID == "kfc-au-zinger-box-regular" })

        let partialBurger = index.search("zinger bur")
        #expect(partialBurger.first?.itemID == "kfc-au-zinger-burger")
        #expect(partialBurger.first?.matchReason == .prefix)

        let bigMac = index.search("big ma")
        #expect(bigMac.first?.itemID == "mcd-au-big-mac")
        #expect(bigMac.first?.variantID == nil)
    }

    @Test func variantResultsCarryBothStableIdentities() throws {
        let index = try bundledIndex()
        let melon = index.search("wonderm")
        #expect(melon.map(\.variantID) == [nil, "boost-au-wondermelon-medium", "boost-au-wondermelon-original"])
        #expect(melon.allSatisfy { $0.itemID == "boost-au-wondermelon" })

        let nuggets = index.search("6 nug")
        #expect(nuggets.first?.itemID == "mcd-au-chicken-mcnuggets")
        #expect(nuggets.first?.variantID == "mcd-au-mcnuggets-6")
        #expect(nuggets.first?.kind == .product)
    }

    @Test func unrelatedOrEmptyTextDoesNotInventProducts() throws {
        let index = try bundledIndex()
        #expect(index.search("purple spaceship battery").isEmpty)
        #expect(index.search("  ").isEmpty)
        #expect(index.search("KFC", limit: 2).count == 3)
    }

    @Test func aNewRestaurantNeedsOnlyDatasetRecords() {
        let restaurant = Restaurant(id: "fixture_au", name: "Fixture Kitchen Australia",
                                    aliases: ["Fixture Kitchen"], country: "AU")
        let provenance = NutritionProvenance(sourceType: .verifiedRestaurant,
            restaurantID: restaurant.id, sourceURL: nil, country: "AU",
            capturedDate: nil, lastVerifiedDate: nil, datasetVersion: nil, sourceQuality: nil)
        let item = RestaurantMenuItem(id: "fixture-wrap", name: "Garden Wrap",
            aliases: ["garden roll"], category: "meal", servingQuantity: nil,
            servingUnit: nil, servingWeightGrams: nil, nutrition: nil,
            components: [], modifiers: [], variants: [], mealConfigurations: [],
            provenance: provenance)
        let source = RestaurantDatasetSource(name: "Fixture", version: "1", sourceURL: nil,
                                             country: "AU", lastUpdated: "2026-01-01")
        let dataset = RestaurantNutritionDataset(datasetVersion: "1", source: source,
                                                 restaurants: [restaurant], menuItems: [item])
        let index = RestaurantFoodSearchIndex(store: RestaurantDatasetStore(dataset: dataset))
        #expect(index.search("Fixture Kitchen").first?.kind == .brand)
        #expect(index.search("garden ro").first?.itemID == "fixture-wrap")
    }
}
