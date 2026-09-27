import Foundation
import Testing
@testable import calorietracker

struct AUSNUTFoodSearchIndexTests {
    @Test func exactDatasetNameKeepsStableID() throws {
        let index = try #require(AUSNUTFoodSearchIndex.bundled())
        let result = try #require(index.search("Banana, cavendish, peeled, raw").first)

        #expect(result.foodID == "16502001")
        #expect(result.title == "Banana, cavendish, peeled, raw")
        #expect(result.matchReason == .exact)
    }

    @Test func prefixAndTokenPrefixFindOrdinaryFoods() throws {
        let index = try #require(AUSNUTFoodSearchIndex.bundled())
        #expect(index.search("broccoli").contains { $0.foodID == "24202001" })
        #expect(index.search("chicken bre").contains { $0.foodID == "18301009" })
        let milk = index.search("milk")
        #expect(milk.count == 5)
        #expect(milk.contains { $0.title.hasPrefix("Milk, cow") })
    }

    @Test func broadQueryReturnsDistinguishableAlternativesWithoutSelectingOne() throws {
        let index = try #require(AUSNUTFoodSearchIndex.bundled())
        let results = index.search("rice")

        #expect(results.count == 5)
        #expect(Set(results.map(\.foodID)).count == results.count)
        #expect(Set(results.map(\.title)).count == results.count)
        #expect(results.allSatisfy { $0.matchReason != .exact })
    }

    @Test func rankingIsDeterministicAndAvoidsSingleWordSubstringSpam() throws {
        let index = try #require(AUSNUTFoodSearchIndex.bundled())
        #expect(index.search("chicken breast").map(\.foodID)
                == index.search("chicken breast").map(\.foodID))
        #expect(index.search("rice").allSatisfy { $0.title.lowercased().hasPrefix("rice") })
        #expect(index.search("notarealfoodname").isEmpty)
    }

    @Test func stableIDLookupFailsClosedAndRetainsAttribution() throws {
        let banana = try #require(AustralianNutritionService.identity(forID: "16502001"))
        #expect(banana.name == "Banana, cavendish, peeled, raw")
        #expect(banana.source.contains("Food Standards Australia New Zealand"))
        #expect(banana.measures.contains { $0.name == "banana medium" && $0.grams > 0 })
        #expect(AustralianNutritionService.identity(forID: "banana") == nil)
        #expect(AustralianNutritionService.identity(forID: "00000000") == nil)
    }

    @Test func suggestionsCarryIdentityButNoNutritionOrDefaultPortion() throws {
        let index = try #require(AUSNUTFoodSearchIndex.bundled())
        let suggestion = try #require(index.search("banana").first)
        let fields = Set(Mirror(reflecting: suggestion).children.compactMap(\.label))
        #expect(fields == ["foodID", "title", "matchReason"])
    }

    @Test func unifiedDiscoveryPreservesRestaurantPrecedenceAndBrandIdentity() throws {
        let search = UnifiedFoodSearchIndex(
            restaurants: try #require(RestaurantFoodSearchIndex.bundled()),
            ausnut: try #require(AUSNUTFoodSearchIndex.bundled())
        )
        let kfc = search.search("KFC")
        #expect(kfc.count <= 5)
        if case .restaurant(let brand) = try #require(kfc.first) {
            #expect(brand.kind == .brand)
        } else { Issue.record("KFC brand identity was not first") }
        #expect(kfc.allSatisfy { if case .restaurant = $0 { true } else { false } })

        let bigMac = search.search("Big Mac")
        if case .restaurant(let item) = try #require(bigMac.first) {
            #expect(item.itemID == "mcd-au-big-mac")
        } else { Issue.record("Verified Big Mac was not first") }
    }

    @Test func unifiedDiscoveryUsesWholeQueryIdentityForOrdinaryFood() throws {
        let search = UnifiedFoodSearchIndex(
            restaurants: try #require(RestaurantFoodSearchIndex.bundled()),
            ausnut: try #require(AUSNUTFoodSearchIndex.bundled())
        )
        let banana = search.search("banana")
        if case .ausnut(let food) = try #require(banana.first) {
            #expect(food.foodID == "16502001")
        } else { Issue.record("Banana did not resolve to AUSNUT discovery") }
        #expect(search.search("broccoli").contains {
            if case .ausnut(let food) = $0 { food.foodID == "24202001" } else { false }
        })
        #expect(search.search("chicken breast").contains {
            if case .ausnut(let food) = $0 { food.foodID == "18301009" } else { false }
        })
        #expect(search.search("chicken avocado sandwich").isEmpty)
        #expect(search.search("eggs toast oil").isEmpty)
    }

    @Test func repeatedMeasureLabelsAreDistinguishableWithoutChangingIndexes() {
        let identity = AUSNUTFoodIdentity(id: "test", name: "Test", measures: [
            AUSNUTFoodMeasure(name: "can", quantity: 1, grams: 330),
            AUSNUTFoodMeasure(name: "can", quantity: 1, grams: 500),
            AUSNUTFoodMeasure(name: "can", quantity: 1, grams: 330),
            AUSNUTFoodMeasure(name: "cup", quantity: 1, grams: 200)
        ])
        let choices = AUSNUTPortionChoice.choices(for: identity)
        #expect(choices.map(\.index) == [0, 1, 3])
        #expect(Set(choices.map(\.title)).count == choices.count)
        #expect(choices[0].title.contains("330 g"))
        #expect(choices[1].title.contains("500 g"))
    }
}
