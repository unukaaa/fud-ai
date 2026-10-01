import Foundation
import Testing
@testable import calorietracker

struct AUSNUTFoodSelectionTests {
    @Test func selectedIDAndExplicitGramsUseAUSNUTNutrition() throws {
        let suggestion = try #require(AUSNUTFoodSearchIndex.bundled()?.search("banana").first)
        let result = FoodQueryResolutionService.resolve(selection: suggestion.selection, portion: .grams(118))
        let analysis = try #require(result.analysis)

        #expect(result.isComplete)
        #expect(result.route?.state == .resolvedFood)
        #expect(result.ausnutSelection?.foodID == "16502001")
        #expect(result.components.count == 1)
        #expect(result.components[0].state == .ausnut)
        #expect(result.components[0].sourceItemID == "16502001")
        #expect(analysis.name == "Banana, cavendish, peeled, raw")
        #expect(analysis.calories == 113)
        #expect(analysis.protein == 1.7)
        #expect(analysis.servingSizeGrams == 118)
        #expect(analysis.selectedServingUnit == "g")
        #expect(analysis.nutritionSource == "AUSNUT Australia")
        #expect(analysis.nutritionSourceDetail?.contains("Food Standards Australia New Zealand") == true)
        #if DEBUG
        #expect(result.debugDiagnostics(for: "banana").components[0].selectedResolver == "AustralianNutritionService")
        #endif
    }

    @Test func missingPortionRequiresClarificationWithoutDefaultNutrition() {
        let result = FoodQueryResolutionService.resolve(
            selection: AUSNUTFoodSelection(foodID: "16502001"), portion: nil
        )
        #expect(!result.isComplete)
        #expect(result.analysis == nil)
        #expect(result.route?.state == .needsClarification)
        #expect(result.components[0].state == .unresolved)
        #expect(result.components[0].calories == nil)
    }

    @Test func selectedNaturalMeasureUsesItsRecordedWeight() throws {
        let selection = AUSNUTFoodSelection(foodID: "16502001")
        let identity = try #require(AustralianNutritionService.identity(forID: selection.foodID))
        let mediumIndex = try #require(identity.measures.firstIndex { $0.name == "banana medium" })
        let result = FoodQueryResolutionService.resolve(
            selection: selection, portion: .measure(index: mediumIndex, quantity: 2)
        )
        let analysis = try #require(result.analysis)

        #expect(result.isComplete)
        #expect(analysis.servingSizeGrams == 254.8)
        #expect(analysis.calories == 243)
        #expect(analysis.selectedServingUnit == "banana medium")
        #expect(analysis.selectedServingQuantity == 2)
        #expect(result.components[0].quantity == 2)
    }

    @Test func staleIDAndInvalidAmountsFailClosed() {
        let stale = AUSNUTFoodSelection(foodID: "not-an-ausnut-id")
        let unknown = FoodQueryResolutionService.resolve(selection: stale, portion: .grams(100))
        #expect(!unknown.isComplete)
        #expect(unknown.analysis == nil)
        #expect(unknown.components[0].sourceItemID == nil)

        let banana = AUSNUTFoodSelection(foodID: "16502001")
        for portion: AUSNUTPortion in [
            .grams(0), .grams(-1), .grams(.nan), .grams(.infinity),
            .measure(index: -1, quantity: 1), .measure(index: 999, quantity: 1),
            .measure(index: 0, quantity: 0), .measure(index: 0, quantity: .infinity)
        ] {
            let result = FoodQueryResolutionService.resolve(selection: banana, portion: portion)
            #expect(!result.isComplete)
            #expect(result.analysis == nil)
        }
    }

    @Test func selectedCookedRiceRemainsTheSelectedRecord() throws {
        let selection = AUSNUTFoodSelection(foodID: "12102003")
        let identity = try #require(AustralianNutritionService.identity(forID: selection.foodID))
        let cupIndex = try #require(identity.measures.firstIndex { $0.name == "cup" })
        let result = FoodQueryResolutionService.resolve(
            selection: selection, portion: .measure(index: cupIndex, quantity: 1)
        )
        let analysis = try #require(result.analysis)

        #expect(analysis.name == "Rice, white, cooked")
        #expect(analysis.servingSizeGrams == 190)
        #expect(analysis.calories == 299)
        #expect(result.components[0].sourceItemID == "12102003")
        #expect(analysis.selectedServingUnit == "cup")
    }

    @Test func presentedChocolateOptionsResolveExactSourceMeasures() throws {
        let food = try #require(AustralianNutritionService.identity(forID: "28101004"))
        let presentation = AUSNUTPortionPresentation.make(for: food)
        let expected: [(Int, Double, Bool)] = [
            (48776, 50, true), (48779, 20.6, true), (48780, 6.5, true),
            (48756, 325, false)
        ]
        for (measureID, grams, isPrimary) in expected {
            let options = isPrimary ? presentation.primary : presentation.more
            let option = try #require(options.first { $0.measureID == measureID })
            let resolved = try #require(AustralianNutritionService.analysis(
                for: AUSNUTFoodSelection(foodID: food.id), portion: option.portion
            ))
            #expect(food.measures[option.index].measureID == measureID)
            #expect(option.gramsPerUnit == grams)
            #expect(resolved.name == food.name)
            #expect(resolved.servingSizeGrams == grams)
            #expect(resolved.nutritionSource == "AUSNUT Australia")
            #expect(resolved.nutritionSourceDetail?.contains("Food Standards Australia New Zealand") == true)
        }
    }

    @Test func presentedFruitBeerAndRiceKeepSourceWeights() throws {
        let cases: [(String, Int, Double)] = [
            ("16502001", 44188, 127.4), // banana medium
            ("16101005", 44111, 165.6), // apple medium
            ("29101001", 40298, 332.97), // 330 mL can
            ("29101001", 40299, 378.37499999999994), // 375 mL can
            ("12102003", 41290, 15.2), // tablespoon
            ("12102003", 41291, 190) // cup
        ]
        for (foodID, measureID, grams) in cases {
            let food = try #require(AustralianNutritionService.identity(forID: foodID))
            let presentation = AUSNUTPortionPresentation.make(for: food)
            let option = try #require((presentation.primary + presentation.more)
                .first { $0.measureID == measureID })
            let resolved = try #require(AustralianNutritionService.analysis(
                for: AUSNUTFoodSelection(foodID: foodID), portion: option.portion
            ))
            #expect(food.measures[option.index].measureID == measureID)
            #expect(option.gramsPerUnit == grams)
            #expect(resolved.servingSizeGrams == grams)
            #expect(resolved.nutritionSource == "AUSNUT Australia")
        }
    }

    @Test func explicitGramsWorkWithoutNaturalMeasures() throws {
        let food = try #require(AustralianNutritionService.identity(forID: "29101005"))
        let presentation = AUSNUTPortionPresentation.make(for: food)
        #expect(presentation.primary.isEmpty)
        #expect(presentation.more.isEmpty)
        let resolved = try #require(AustralianNutritionService.analysis(
            for: AUSNUTFoodSelection(foodID: food.id), portion: .grams(37)
        ))
        #expect(resolved.servingSizeGrams == 37)
        #expect(resolved.selectedServingUnit == "g")
        #expect(resolved.selectedServingQuantity == 37)
        #expect(resolved.nutritionSource == "AUSNUT Australia")
    }

    @Test func sourcedVolumeAllowsCustomMillilitresWithoutInventedConversion() throws {
        for (foodID, millilitres) in [("19101002", 125.0), ("11802002", 250.0),
                                      ("29101001", 250.0)] {
            let food = try #require(AustralianNutritionService.identity(forID: foodID))
            let presentation = AUSNUTPortionPresentation.make(for: food)
            let basis = try #require(AUSNUTVolumeBasis.make(for: presentation))
            let source = food.measures[basis.measure.index]
            #expect(source.measureID == basis.measure.measureID)
            let portion = try #require(basis.portion(millilitres: millilitres))
            let resolved = try #require(AustralianNutritionService.analysis(
                for: AUSNUTFoodSelection(foodID: foodID), portion: portion
            ))
            let expectedGrams = millilitres * source.grams / (source.volume ?? .nan)
            #expect(abs(resolved.servingSizeGrams - expectedGrams) < 0.001)
            #expect(resolved.nutritionSource == "AUSNUT Australia")
            #expect(resolved.selectedServingUnit == "mL")
            #expect(resolved.selectedServingQuantity == millilitres)
            #expect(resolved.servingUnitOptions.contains {
                $0.unit == "mL" && abs($0.gramsPerUnit - source.grams / (source.volume ?? .nan)) < 0.000001
            })
            let sameGrams = try #require(AustralianNutritionService.analysis(
                for: AUSNUTFoodSelection(foodID: foodID), portion: .grams(expectedGrams)
            ))
            #expect(resolved.calories == sameGrams.calories)
            #expect(resolved.protein == sameGrams.protein)
            #expect(resolved.carbs == sameGrams.carbs)
            #expect(resolved.fat == sameGrams.fat)
            #expect(basis.portion(millilitres: 0) == nil)
        }
    }

    @Test func duplicateCanLabelsRetainDistinctSourceMeasures() throws {
        let food = try #require(AustralianNutritionService.identity(forID: "29101001"))
        let options = AUSNUTPortionPresentation.make(for: food)
        let all = options.primary + options.more
        let can330 = try #require(all.first { $0.measureID == 40298 })
        let can375 = try #require(all.first { $0.measureID == 40299 })
        #expect(can330.index != can375.index)
        #expect(can330.title.contains("330 mL"))
        #expect(can375.title.contains("375 mL"))
        #expect(can330.sourceVolume == 330)
        #expect(can375.sourceVolume == 375)
        #expect(can330.sourceGrams == food.measures[can330.index].grams)
        #expect(can375.sourceGrams == food.measures[can375.index].grams)
        for option in [can330, can375] {
            let resolved = try #require(AustralianNutritionService.analysis(
                for: AUSNUTFoodSelection(foodID: food.id), portion: option.portion
            ))
            #expect(resolved.selectedServingUnit == option.title)
            #expect(resolved.selectedServingQuantity == 1)
            #expect(resolved.servingSizeGrams == option.sourceGrams)
            #expect(resolved.nutritionSource == "AUSNUT Australia")
        }
    }

    @Test func customMillilitresFailClosedWithoutOneConsistentSourceBasis() throws {
        let chocolate = try #require(AustralianNutritionService.identity(forID: "28101004"))
        #expect(AUSNUTVolumeBasis.make(for: AUSNUTPortionPresentation.make(for: chocolate)) == nil)
        let noMeasures = try #require(AustralianNutritionService.identity(forID: "29101005"))
        #expect(AUSNUTVolumeBasis.make(for: AUSNUTPortionPresentation.make(for: noMeasures)) == nil)

        let conflicting = AUSNUTFoodIdentity(id: "fixture", name: "Synthetic liquid", measures: [
            AUSNUTFoodMeasure(name: "cup", quantity: 1, grams: 250, measureID: 1,
                              descriptors: ["cup", nil, nil, nil], volume: 250),
            AUSNUTFoodMeasure(name: "bottle", quantity: 1, grams: 300, measureID: 2,
                              descriptors: ["bottle", nil, nil, nil], volume: 250)
        ])
        #expect(AUSNUTVolumeBasis.make(for: AUSNUTPortionPresentation.make(for: conflicting)) == nil)
        #expect(AustralianNutritionService.analysis(
            for: AUSNUTFoodSelection(foodID: noMeasures.id),
            portion: .millilitres(value: 250, basisIndex: 0)
        ) == nil)
        let grams = try #require(AustralianNutritionService.analysis(
            for: AUSNUTFoodSelection(foodID: noMeasures.id), portion: .grams(250)
        ))
        #expect(grams.selectedServingUnit == "g")
        #expect(grams.selectedServingQuantity == 250)
    }
}
