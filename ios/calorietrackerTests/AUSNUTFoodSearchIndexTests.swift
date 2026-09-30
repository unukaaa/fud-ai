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

    @Test func chocolateRetainsAllOfficialFoodMeasures() throws {
        let chocolate = try #require(AustralianNutritionService.identity(forID: "28101004"))
        #expect(chocolate.measures.count == 24)
        #expect(chocolate.measures.contains { $0.measureID == 48776 && $0.name == "bar regular" && $0.grams == 50 })
        #expect(chocolate.measures.contains { $0.measureID == 48779 && $0.name == "row" && $0.grams == 20.6 })
        #expect(chocolate.measures.contains { $0.measureID == 48780 && $0.name == "square" && $0.grams == 6.5 })
        #expect(chocolate.measures.allSatisfy { !$0.name.lowercased().contains("density") })
    }

    @Test func officialMeasureIDsAndSourceContextRemainAttachedToTheirFood() throws {
        let identities = try #require(AustralianNutritionService.searchableIdentities)
        #expect(identities.count == 3741)
        #expect(Set(identities.map(\.id)).count == 3741)
        let measures = identities.flatMap(\.measures)
        #expect(measures.count == 6207)
        #expect(Set(measures.compactMap(\.measureID)).count == 6207)
        #expect(measures.allSatisfy { $0.measureID != nil && $0.grams.isFinite && $0.grams > 0 })
        #expect(measures.allSatisfy { $0.descriptors?.first != "density" })

        let beer = try #require(AustralianNutritionService.identity(forID: "29101001"))
        #expect(beer.measures.contains { $0.measureID == 40298 && $0.name == "can" && $0.volume == 330 })
        #expect(beer.measures.contains { $0.measureID == 40299 && $0.name == "can" && $0.volume == 375 })

        let panettone = try #require(AustralianNutritionService.identity(forID: "12305018"))
        #expect(panettone.measures.contains {
            $0.measureID == 49860 && $0.descriptors == ["turkish bread", "slice", nil, nil]
        })
        let banana = try #require(AustralianNutritionService.identity(forID: "16502001"))
        #expect(banana.measures.contains { $0.name == "banana medium" && $0.grams == 127.4 })
    }

    @Test func portionPolicyMakesOrdinaryChocolateFormsPrimaryWithoutLosingSpecialForms() throws {
        let food = try #require(AustralianNutritionService.identity(forID: "28101004"))
        let presentation = AUSNUTPortionPresentation.make(for: food)
        let primaryIDs = Set(presentation.primary.compactMap(\.measureID))
        #expect(presentation.primary.count == 4)
        #expect(primaryIDs == [48776, 48778, 48779, 48780]) // regular bar, chocolate, row, square
        #expect(presentation.primary.allSatisfy { !$0.title.contains("egg") && !$0.title.contains("bunny/bilby") })
        #expect(presentation.more.contains { $0.measureID == 48756 && $0.title.contains("Chocolate, milk · egg large") })
        #expect(presentation.more.contains { $0.measureID == 48761 && $0.title.contains("bunny/bilby") })
        #expect(Set((presentation.primary + presentation.more).compactMap(\.measureID)).count == 24)
    }

    @Test func portionPolicyUsesOneGenericRuleForFruitRiceBreadEggsAndBeverages() throws {
        let banana = try #require(AustralianNutritionService.identity(forID: "16502001"))
        let apple = try #require(AustralianNutritionService.identity(forID: "16101005"))
        #expect(AUSNUTPortionPresentation.make(for: banana).primary.first?.title == "banana medium")
        #expect(AUSNUTPortionPresentation.make(for: apple).primary.first?.title == "apple medium")

        let rice = try #require(AustralianNutritionService.identity(forID: "12102003"))
        #expect(Set(AUSNUTPortionPresentation.make(for: rice).primary.map(\.title)) == ["cup", "tablespoon"])
        let bread = try #require(AustralianNutritionService.identity(forID: "12202001"))
        #expect(AUSNUTPortionPresentation.make(for: bread).primary.contains { $0.title.contains("slice regular") })
        let beverage = try #require(AustralianNutritionService.identity(forID: "11802002"))
        let bottles = AUSNUTPortionPresentation.make(for: beverage)
        #expect((bottles.primary + bottles.more).contains { $0.title.contains("bottle") && ($0.sourceVolume ?? 0) > 0 })

        // AUSNUT chicken-egg records contain one generic egg measure, so size
        // behavior is exercised with source-shaped synthetic measures.
        let eggs = AUSNUTFoodIdentity(id: "fixture", name: "Egg, chicken", measures: [
            AUSNUTFoodMeasure(name: "egg large", quantity: 1, grams: 60,
                              measureID: 1, descriptors: ["egg", "large", nil, nil], volume: 0),
            AUSNUTFoodMeasure(name: "egg medium", quantity: 1, grams: 50,
                              measureID: 2, descriptors: ["egg", "medium", nil, nil], volume: 0),
            AUSNUTFoodMeasure(name: "egg small", quantity: 1, grams: 40,
                              measureID: 3, descriptors: ["egg", "small", nil, nil], volume: 0)
        ])
        let eggPresentation = AUSNUTPortionPresentation.make(for: eggs)
        #expect(eggPresentation.primary.first?.measureID == 2)
        #expect(Set(eggPresentation.primary.compactMap(\.measureID)) == [1, 2, 3])
    }

    @Test func portionPolicyDistinguishesBeerVolumesAndKeepsExtremeWeights() throws {
        let beer = try #require(AustralianNutritionService.identity(forID: "29101001"))
        let beerPresentation = AUSNUTPortionPresentation.make(for: beer)
        let beerOptions = beerPresentation.primary + beerPresentation.more
        #expect(beerOptions.count == beer.measures.count)
        #expect(beerOptions.contains { $0.measureID == 40298 && $0.title.contains("330 mL") })
        #expect(beerOptions.contains { $0.measureID == 40299 && $0.title.contains("375 mL") })
        #expect(Set(beerOptions.map { $0.title.lowercased() }).count == beerOptions.count)

        let tiny = try #require(AustralianNutritionService.identity(forID: "22101008"))
        let tinyOptions = AUSNUTPortionPresentation.make(for: tiny)
        #expect((tinyOptions.primary + tinyOptions.more).contains { $0.sourceGrams == 0.05 })
        let large = try #require(AustralianNutritionService.identity(forID: "11501003"))
        let largeOptions = AUSNUTPortionPresentation.make(for: large)
        #expect((largeOptions.primary + largeOptions.more).contains { $0.sourceGrams > 1_000 })

        let noMeasures = try #require(AustralianNutritionService.identity(forID: "29101005"))
        let empty = AUSNUTPortionPresentation.make(for: noMeasures)
        #expect(empty.primary.isEmpty && empty.more.isEmpty)
        #expect(AustralianNutritionService.analysis(
            for: AUSNUTFoodSelection(foodID: noMeasures.id), portion: .grams(100)
        )?.servingSizeGrams == 100)
    }

    @Test func everyBundledMeasureIsReachableThroughThePortionPolicy() throws {
        let foods = try #require(AustralianNutritionService.searchableIdentities)
        var sourceCount = 0
        var presentedCount = 0
        var foodsWithMeasures = 0
        var primaryDistribution: [Int: Int] = [:]
        var moreDistribution: [Int: Int] = [:]
        var unreachable = 0
        var duplicateTitles = 0
        var invalidWeights = 0
        var sourceMismatches = 0

        for food in foods {
            let presentation = AUSNUTPortionPresentation.make(for: food)
            let options = presentation.primary + presentation.more
            sourceCount += food.measures.count
            presentedCount += options.count
            foodsWithMeasures += food.measures.isEmpty ? 0 : 1
            primaryDistribution[presentation.primary.count, default: 0] += 1
            moreDistribution[presentation.more.count, default: 0] += 1
            let indices = Set(options.map(\.index))
            unreachable += food.measures.indices.filter { !indices.contains($0) }.count
            duplicateTitles += options.count - Set(options.map { $0.title.lowercased() }).count
            for option in options {
                let measure = food.measures[option.index]
                if !option.gramsPerUnit.isFinite || option.gramsPerUnit <= 0 { invalidWeights += 1 }
                if option.measureID != measure.measureID || option.sourceGrams != measure.grams
                    || option.sourceVolume != measure.volume || option.sourceQuantity != measure.quantity {
                    sourceMismatches += 1
                }
            }
        }
        print("AUSNUT_POLICY_AUDIT foods=\(foods.count) withMeasures=\(foodsWithMeasures) "
              + "withoutMeasures=\(foods.count - foodsWithMeasures) source=\(sourceCount) "
              + "presented=\(presentedCount) primary=\(primaryDistribution.sorted { $0.key < $1.key }) "
              + "more=\(moreDistribution.sorted { $0.key < $1.key }) unreachable=\(unreachable) "
              + "duplicateTitles=\(duplicateTitles) invalidWeights=\(invalidWeights) "
              + "sourceMismatches=\(sourceMismatches)")
        #expect(foods.count == 3741)
        #expect(sourceCount == 6207)
        #expect(presentedCount == sourceCount)
        #expect(unreachable == 0)
        #expect(duplicateTitles == 0)
        #expect(invalidWeights == 0)
        #expect(sourceMismatches == 0)
        #expect(primaryDistribution.keys.allSatisfy { (0...4).contains($0) })
    }

}
