import Foundation
import Testing
@testable import calorietracker

struct GroundedEstimateEngineTests {
    private func evaluateExisting(_ input: GroundedMealInput) -> GroundedMealResult {
        GroundedEstimateEngine.evaluate(input, resolver: ExistingFoodGrounder.resolve)
    }

    private func facts(_ kcal: Double, _ protein: Double, _ carbs: Double, _ fat: Double) -> NutritionFacts {
        NutritionFacts(calories: kcal, kilojoules: nil, proteinGrams: protein,
                       carbohydrateGrams: carbs, fatGrams: fat)
    }

    private func component(_ description: String, _ id: GroundedSourceID?,
                           _ amount: GroundedAmount?, estimate: NutritionFacts? = nil,
                           assumptions: [String] = []) -> GroundedComponentInput {
        GroundedComponentInput(description: description, sourceID: id, amount: amount,
                               estimatedNutrition: estimate, assumptions: assumptions)
    }

    private func grams(_ value: Double, _ origin: GroundedAmountProvenance) -> GroundedAmount {
        GroundedAmount(value: value, unit: .grams, provenance: origin)
    }

    private func meal(_ description: String, _ components: [GroundedComponentInput],
                      kind: GroundedInputKind = .text) -> GroundedMealInput {
        GroundedMealInput(description: description, inputKind: kind, components: components)
    }

    @Test func exactAUSNUTIdentityUsesExistingSourceScalingAndProvenance() throws {
        let id = GroundedSourceID.ausnut("16502001")
        let input = meal("118 g Cavendish banana", [component("banana", id, grams(118, .user))])
        let result = evaluateExisting(input)
        let existing = try #require(AustralianNutritionService.analysis(
            for: AUSNUTFoodSelection(foodID: "16502001"), portion: .grams(118)
        ))
        #expect(result.evidence == .sourced)
        #expect(result.groundedCount == 1)
        #expect(result.unresolvedCount == 0)
        #expect(result.nutritionComplete)
        #expect(result.components[0].source?.sourceID == id)
        #expect(result.components[0].source?.sourceType == .ausnut)
        #expect(result.components[0].source?.sourceVersion == "AUSNUT 2023")
        #expect(result.calculatedNutrition?.calories == Double(existing.calories))
        #expect(result.calculatedNutrition?.proteinGrams == existing.protein)
        #expect(result.calculatedNutrition?.carbohydrateGrams == existing.carbs)
        #expect(result.calculatedNutrition?.fatGrams == existing.fat)
    }

    @Test func exactRestaurantItemUsesPublishedServingWithoutGuessingConfiguration() {
        let id = GroundedSourceID.restaurant(restaurantID: "mcdonalds_au", itemID: "mcd-au-big-mac")
        let result = evaluateExisting(meal("Big Mac", [
            component("Big Mac", id, GroundedAmount(value: 1, unit: .servings, provenance: .source))
        ]))
        #expect(result.evidence == .sourced)
        #expect(result.calculatedNutrition?.calories == 557)
        #expect(result.calculatedNutrition?.proteinGrams == 24.6)
        #expect(result.components[0].source?.sourceID == id)
        #expect(result.components[0].source?.sourceType == .verifiedRestaurant)

        let configured = GroundedSourceID.restaurant(restaurantID: "kfc_au", itemID: "kfc-au-zinger-burger")
        let unresolved = evaluateExisting(meal("Zinger order", [
            component("Zinger order", configured,
                      GroundedAmount(value: 1, unit: .servings, provenance: .source))
        ]))
        #expect(unresolved.evidence == .estimate)
        #expect(unresolved.components[0].source == nil)
        #expect(unresolved.needsExternalEstimate)
    }

    @Test func estimatedAmountKeepsTrustedNutritionButDowngradesMealEvidence() {
        let id = GroundedSourceID.ausnut("16502001")
        let result = evaluateExisting(meal("banana, amount guessed", [
            component("Cavendish banana", id, grams(120, .estimated),
                      assumptions: ["Amount estimated at 120 g"])
        ]))
        #expect(result.evidence == .sourcedEstimate)
        #expect(result.estimatedAmountCount == 1)
        #expect(result.components[0].source?.sourceID == id)
        #expect(result.components[0].input.assumptions == ["Amount estimated at 120 g"])
        #expect(result.nutritionComplete)
    }

    @Test func unresolvedComponentPreservesGroundedProgressWithoutClaimingCompleteNutrition() {
        let result = evaluateExisting(meal("banana with sauce", [
            component("Cavendish banana", .ausnut("16502001"), grams(100, .estimated)),
            component("sauce", nil, nil, assumptions: ["Sauce type and amount unknown"])
        ]))
        #expect(result.evidence == .estimate)
        #expect(result.groundedCount == 1)
        #expect(result.unresolvedCount == 1)
        #expect(result.needsExternalEstimate)
        #expect(!result.nutritionComplete)
        #expect(result.calculatedNutrition?.calories != nil)
        #expect(result.components[1].input.description == "sauce")
        #expect(result.components[1].input.assumptions == ["Sauce type and amount unknown"])
    }

    @Test func estimatedNutritionNeverBecomesVerifiedAndBadAmountsFailClosed() {
        let estimate = facts(80, 1, 7, 5)
        let result = evaluateExisting(meal("unknown sauce", [
            component("sauce", nil, nil, estimate: estimate)
        ]))
        #expect(result.evidence == .estimate)
        #expect(result.groundedCount == 0)
        #expect(result.calculatedNutrition?.calories == 80)
        #expect(result.components[0].source == nil)

        let invalid = evaluateExisting(meal("invalid amount", [
            component("banana", .ausnut("16502001"), grams(.nan, .user))
        ]))
        #expect(invalid.unresolvedCount == 1)
        #expect(invalid.calculatedNutrition == nil)
        #expect(!invalid.nutritionComplete)
    }

    @Test func questionBudgetNormallyAsksAtMostOnce() {
        #expect(GroundedQuestionBudget.nextStep(
            questionsAsked: 0, materialAmbiguity: false,
            largeConsequentialDifference: false) == .proceed)
        #expect(GroundedQuestionBudget.nextStep(
            questionsAsked: 0, materialAmbiguity: true,
            largeConsequentialDifference: false) == .ask)
        #expect(GroundedQuestionBudget.nextStep(
            questionsAsked: 1, materialAmbiguity: true,
            largeConsequentialDifference: false) == .estimate)
        #expect(GroundedQuestionBudget.nextStep(
            questionsAsked: 1, materialAmbiguity: true,
            largeConsequentialDifference: true) == .ask)
        #expect(GroundedQuestionBudget.nextStep(
            questionsAsked: 2, materialAmbiguity: true,
            largeConsequentialDifference: true) == .estimate)
    }

    @Test func unsupportedBarcodeNeverStartsNetworkOrFabricatesNutrition() {
        let barcode = GroundedSourceID.barcode("9300000000000")
        let result = evaluateExisting(meal("unavailable barcode", [
            component("product", barcode, grams(100, .user))
        ], kind: .photo))
        #expect(result.evidence == .estimate)
        #expect(result.needsExternalEstimate)
        #expect(result.components[0].input.sourceID == barcode)
        #expect(result.components[0].source == nil)
        #expect(result.calculatedNutrition == nil)
    }

    @Test func deterministicAggregationAddsContributionsWithoutPromotingEstimates() {
        let exact = GroundedSourceID.ausnut("synthetic-exact")
        let resolver: GroundedEstimateEngine.Resolver = { id, amount in
            guard id == exact, amount.unit == .grams else { return nil }
            return GroundedSourceResolution(
                sourceID: id, sourceName: "Synthetic exact source", sourceType: .ausnut,
                sourceVersion: "synthetic-test-v1", sourceURL: nil,
                nutrition: self.facts(100, 10, 15, 4).scaled(by: amount.value / 100)
            )
        }
        let result = GroundedEstimateEngine.evaluate(meal("two components and sauce", [
            component("first", exact, grams(100, .user)),
            component("second", exact, grams(50, .estimated)),
            component("sauce", nil, nil, estimate: facts(80, 1, 7, 5))
        ]), resolver: resolver)
        #expect(result.evidence == .estimate)
        #expect(result.groundedCount == 2)
        #expect(result.estimatedAmountCount == 1)
        #expect(result.nutritionComplete)
        #expect(result.calculatedNutrition?.calories == 230)
        #expect(result.calculatedNutrition?.proteinGrams == 16)
        #expect(result.calculatedNutrition?.carbohydrateGrams == 29.5)
        #expect(result.calculatedNutrition?.fatGrams == 11)
        #expect(result.components[2].source == nil)
    }

    @Test func mismatchedSourceIDAndUntrustedSourceTypeCannotClaimGrounding() {
        let requested = GroundedSourceID.ausnut("requested")
        let wrongID = GroundedEstimateEngine.evaluate(meal("requested", [
            component("requested", requested, grams(100, .user))
        ]), resolver: { _, _ in
            GroundedSourceResolution(
                sourceID: .ausnut("other"), sourceName: "Other", sourceType: .ausnut,
                sourceVersion: "synthetic-test-v1", sourceURL: nil,
                nutrition: self.facts(100, 1, 1, 1)
            )
        })
        #expect(wrongID.groundedCount == 0)
        #expect(wrongID.needsExternalEstimate)

        let untrusted = GroundedEstimateEngine.evaluate(meal("requested", [
            component("requested", requested, grams(100, .user))
        ]), resolver: { id, _ in
            GroundedSourceResolution(
                sourceID: id, sourceName: "Unverified", sourceType: .aiEstimate,
                sourceVersion: nil, sourceURL: nil,
                nutrition: self.facts(100, 1, 1, 1)
            )
        })
        #expect(untrusted.groundedCount == 0)
        #expect(untrusted.components[0].source == nil)
    }

    @Test func controlledTwelveMealBenchmarkKeepsArithmeticAndCoverageDeterministic() {
        // These are synthetic decompositions and nutrition fixtures, not claims
        // about real food accuracy or an AI model's interpretation quality.
        let per100: [String: NutritionFacts] = [
            "cereal": facts(370, 8, 78, 3), "milk": facts(65, 3, 5, 4),
            "berries": facts(50, 1, 12, 0), "chicken": facts(165, 31, 0, 4),
            "avocado": facts(160, 2, 9, 15), "bread": facts(250, 9, 48, 3),
            "ham": facts(145, 21, 2, 5), "cheese": facts(400, 25, 2, 33),
            "pasta": facts(155, 6, 31, 1), "beef": facts(250, 26, 0, 17),
            "tomato": facts(20, 1, 4, 0), "rice": facts(130, 3, 28, 0),
            "egg": facts(145, 13, 1, 10), "steak": facts(220, 27, 0, 12),
            "wrap": facts(300, 8, 50, 8), "salad": facts(30, 2, 5, 0),
            "yoghurt": facts(95, 8, 10, 3), "granola": facts(450, 10, 65, 17),
            "apple": facts(52, 0, 14, 0)
        ]
        let resolver: GroundedEstimateEngine.Resolver = { id, amount in
            if case .ausnut(let key) = id, amount.unit == .grams, let base = per100[key] {
                return GroundedSourceResolution(
                    sourceID: id, sourceName: "Synthetic \(key)", sourceType: .ausnut,
                    sourceVersion: "synthetic-test-v1", sourceURL: nil,
                    nutrition: base.scaled(by: amount.value / 100)
                )
            }
            return ExistingFoodGrounder.resolve(id, amount: amount)
        }
        func sourced(_ name: String, _ amount: Double,
                     _ origin: GroundedAmountProvenance = .estimated) -> GroundedComponentInput {
            component(name, .ausnut(name), grams(amount, origin))
        }
        let cases: [(GroundedMealInput, GroundedMealResult.Evidence)] = [
            (meal("cereal with full cream milk, banana and berries", [
                sourced("cereal", 45), sourced("milk", 200), component("banana variety", nil, nil),
                sourced("berries", 70)
            ]), .estimate),
            (meal("chicken avocado sandwich", [
                sourced("chicken", 100), sourced("avocado", 50), sourced("bread", 80)
            ]), .sourcedEstimate),
            (meal("ham and cheese toastie", [
                sourced("ham", 50), sourced("cheese", 30), sourced("bread", 80)
            ]), .sourcedEstimate),
            (meal("spaghetti bolognese", [
                sourced("pasta", 180), sourced("beef", 100), sourced("tomato", 100)
            ]), .sourcedEstimate),
            (meal("chicken curry with rice", [
                sourced("chicken", 120), sourced("rice", 180),
                component("curry sauce", nil, nil, estimate: facts(130, 2, 9, 10),
                          assumptions: ["Sauce estimated"])
            ]), .estimate),
            (meal("scrambled eggs on toast", [sourced("egg", 120), sourced("bread", 80)]), .sourcedEstimate),
            (meal("steak sandwich", [
                sourced("steak", 130), sourced("bread", 80), component("sauce", nil, nil)
            ]), .estimate),
            (meal("chicken salad wrap", [
                sourced("chicken", 100), sourced("salad", 80), sourced("wrap", 70)
            ], kind: .voice), .sourcedEstimate),
            (meal("yoghurt with berries and granola", [
                sourced("yoghurt", 180), sourced("berries", 80), sourced("granola", 40)
            ]), .sourcedEstimate),
            (meal("simple whole food", [sourced("apple", 165, .user)]), .sourced),
            (meal("exact restaurant food", [component(
                "Big Mac", .restaurant(restaurantID: "mcdonalds_au", itemID: "mcd-au-big-mac"),
                GroundedAmount(value: 1, unit: .servings, provenance: .source)
            )]), .sourced),
            (meal("true unknown food", [component("unknown food", nil, nil)]), .estimate)
        ]
        var total = 0, grounded = 0, unresolved = 0, estimatedAmounts = 0
        var awaitingExternalNutrition = 0, structuralDeadEnds = 0, questionRecommendations = 0
        var stateCounts: [String: Int] = [:]
        for (input, expected) in cases {
            let result = GroundedEstimateEngine.evaluate(input, resolver: resolver)
            #expect(result.evidence == expected)
            #expect(result.input.description == input.description)
            #expect(result.components.count == input.components.count)
            total += result.components.count
            grounded += result.groundedCount
            unresolved += result.unresolvedCount
            estimatedAmounts += result.estimatedAmountCount
            awaitingExternalNutrition += result.calculatedNutrition == nil ? 1 : 0
            structuralDeadEnds += result.components.isEmpty ? 1 : 0
            stateCounts[String(describing: result.evidence), default: 0] += 1
            // This fixture labels only the unresolved banana variety as a
            // material identity question; it is not a learned materiality rule.
            let materialAmbiguity = input.description == "cereal with full cream milk, banana and berries"
            if GroundedQuestionBudget.nextStep(
                questionsAsked: 0, materialAmbiguity: materialAmbiguity,
                largeConsequentialDifference: false
            ) == .ask { questionRecommendations += 1 }
        }
        print("GROUNDED_SYNTHETIC_BENCHMARK meals=\(cases.count) components=\(total) "
              + "grounded=\(grounded) unresolved=\(unresolved) "
              + "estimatedAmounts=\(estimatedAmounts) states=\(stateCounts) "
              + "questionRecommendations=\(questionRecommendations) "
              + "awaitingExternalNutrition=\(awaitingExternalNutrition) "
              + "structuralDeadEnds=\(structuralDeadEnds)")
        #expect(cases.count == 12)
        #expect(total == 30)
        #expect(grounded == 26)
        #expect(unresolved == 3)
        #expect(estimatedAmounts == 24)
        #expect(questionRecommendations == 1)
        #expect(awaitingExternalNutrition == 1)
        #expect(structuralDeadEnds == 0)
    }
}
