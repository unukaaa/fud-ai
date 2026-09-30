import Foundation
import Testing
@testable import calorietracker

struct FoodConsumerLabelsTests {
    @Test func milkNamesUseDistinctOrdinaryTermsWithoutChangingSourceIDs() throws {
        let identities = try #require(AustralianNutritionService.searchableIdentities)
        let selected = ["19101001", "19101002", "19101003", "19102001", "19102002",
                        "19103001", "19103002", "19108002"]
        let sources = selected.compactMap { id in
            identities.first(where: { $0.id == id }).map { (id: "ausnut:\(id)", name: $0.name) }
        }
        #expect(sources.count == selected.count)
        let labels = FoodConsumerLabels.choices(sources)
        #expect(labels["ausnut:19101001"] == "Extra creamy milk")
        #expect(labels["ausnut:19101002"] == "Full cream milk")
        #expect(labels["ausnut:19101003"] == "Lactose-free full cream milk")
        #expect(labels["ausnut:19102001"] == "Light milk")
        #expect(labels["ausnut:19102002"] == "Lactose-free light milk")
        #expect(labels["ausnut:19103001"] == "Skim milk")
        #expect(labels["ausnut:19103002"] == "Lactose-free skim milk")
        #expect(labels["ausnut:19108002"] == "Lactose-free milk")
        #expect(Set(labels.values).count == labels.count)
        #expect(Set(labels.keys) == Set(sources.map { $0.id }))
    }

    @Test func chocolateTypesAndCocoaBoundaryRemainDistinct() {
        #expect(FoodConsumerLabels.food("Chocolate, milk") == "Milk chocolate")
        #expect(FoodConsumerLabels.food("Chocolate, white") == "White chocolate")
        #expect(FoodConsumerLabels.food("Chocolate, dark, high cocoa solids, >60% cocoa solids")
                == "Dark chocolate · over 60% cocoa")
        #expect(FoodConsumerLabels.food("Chocolate, dark, high cocoa solids, <60% cocoa solids")
                == "Dark chocolate · under 60% cocoa")
        #expect(FoodConsumerLabels.food("Chocolate, milk, no added sugar")
                == "Milk chocolate · no added sugar")
    }

    @Test func bananaAppleAndPreparationTruthSurviveSimplification() {
        #expect(FoodConsumerLabels.food("Banana, cavendish, peeled, raw") == "Cavendish banana")
        #expect(FoodConsumerLabels.food("Banana, lady finger or sugar, peeled, raw")
                == "Lady Finger banana")
        #expect(FoodConsumerLabels.food("Apple, raw, not further defined") == "Raw apple")
        for name in ["Rice, white, uncooked", "Rice, white, cooked",
                     "Chicken, breast, lean, raw", "Chicken, breast, lean, baked, roasted, fried, grilled or BBQ'd, no added fat",
                     "Tuna, raw", "Tuna, unflavoured, canned in water, drained",
                     "Coca-Cola Zero Sugar", "McDonald's Big Mac"] {
            #expect(FoodConsumerLabels.food(name) == name)
        }
    }

    @Test func collisionsFallBackToAuthoritativeNamesThenStableIDs() {
        let sources = [(id: "ausnut:1", name: "Milk, cow, fluid, regular fat (~3.5%)"),
                       (id: "ausnut:2", name: "Full cream milk"),
                       (id: "ausnut:3", name: "Same source name"),
                       (id: "ausnut:4", name: "Same source name")]
        let labels = FoodConsumerLabels.choices(sources)
        #expect(labels["ausnut:1"] == sources[0].name)
        #expect(labels["ausnut:2"] == sources[1].name)
        #expect(labels["ausnut:3"] == "Same source name · source ausnut:3")
        #expect(labels["ausnut:4"] == "Same source name · source ausnut:4")
        #expect(Set(labels.values).count == sources.count)
    }

    @Test func portionWordsReorderWithoutChangingMeasureIdentityOrWeight() throws {
        #expect(FoodConsumerLabels.portion("bar regular") == "Regular bar")
        #expect(FoodConsumerLabels.portion(ServingUnitOption(unit: "bar regular", gramsPerUnit: 50)
            .displayUnit(for: 2)) == "Regular bars")
        #expect(FoodConsumerLabels.portion("banana medium") == "Medium banana")
        #expect(FoodConsumerLabels.portion(ServingUnitOption(unit: "banana medium", gramsPerUnit: 118)
            .displayUnit(for: 2)) == "Medium bananas")
        #expect(FoodConsumerLabels.portion("egg large") == "Large egg")
        #expect(FoodConsumerLabels.portion("bar regular · 50 g") == "Regular bar · 50 g")
        #expect(FoodConsumerLabels.portion("can · 330 mL") == "can · 330 mL")
        let chocolate = try #require(AustralianNutritionService.identity(forID: "28101004"))
        let presentation = AUSNUTPortionPresentation.make(for: chocolate)
        let bar = try #require((presentation.primary + presentation.more).first { $0.title == "bar regular" })
        #expect(FoodConsumerLabels.portion(bar.title) == "Regular bar")
        #expect(bar.measureID == chocolate.measures[bar.index].measureID)
        #expect(bar.gramsPerUnit == chocolate.measures[bar.index].grams / chocolate.measures[bar.index].quantity)
        guard case .measure(let selectedIndex, let selectedQuantity) = bar.portion else {
            Issue.record("The selected source measure must retain its index")
            return
        }
        #expect(selectedIndex == bar.index)
        #expect(selectedQuantity == 1)
    }

    @Test func completeAUSNUTLabelAuditRetainsEveryIdentityWithoutVisibleCollisions() throws {
        let identities = try #require(AustralianNutritionService.searchableIdentities)
        let sources = identities.map { (id: "ausnut:\($0.id)", name: $0.name) }
        let labels = FoodConsumerLabels.choices(sources)
        let simplified = sources.filter { labels[$0.id] != $0.name }.count
        let rawGroups = Dictionary(grouping: sources, by: {
            FoodConsumerLabels.food($0.name).folding(
                options: [.caseInsensitive, .diacriticInsensitive], locale: Locale(identifier: "en_AU"))
        })
        let rawCollisionGroups = rawGroups.values.filter { $0.count > 1 }.count
        let authoritativeFallbacks = sources.filter {
            FoodConsumerLabels.food($0.name) != $0.name && labels[$0.id] == $0.name
        }.count
        let duplicates = labels.values.count - Set(labels.values.map {
            $0.folding(options: [.caseInsensitive, .diacriticInsensitive], locale: Locale(identifier: "en_AU"))
        }).count
        #expect(identities.count == 3_741)
        #expect(labels.count == identities.count)
        #expect(Set(labels.keys) == Set(sources.map { $0.id }))
        #expect(duplicates == 0)
        print("Consumer label audit: \(identities.count) identities, \(simplified) simplified, \(identities.count - simplified) unchanged, \(rawCollisionGroups) raw collision groups, \(authoritativeFallbacks) authoritative fallbacks, \(duplicates) ambiguous final labels")
    }
}
