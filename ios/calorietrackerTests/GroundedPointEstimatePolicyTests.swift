import Foundation
import Testing
@testable import calorietracker

struct GroundedPointEstimatePolicyTests {
    private func input(_ name: String = "banana", grams: Double = 120, id: GroundedSourceID? = nil) -> EstimateGroundedComponent {
        EstimateGroundedComponent(exactInput: GroundedComponentInput(description: name, sourceID: id,
            amount: GroundedAmount(value: grams, unit: .grams, provenance: .estimated), estimatedNutrition: nil,
            assumptions: ["Assumed edible weight"]), scopedEstimateQuery: name + " raw")
    }
    private func point(_ c: EstimateGroundedComponent) throws -> GroundedComponentPoint {
        try #require(GroundedPointEstimatePolicy.point(for: EstimateGroundedMealEngine.evaluate([c]).components[0]))
    }
    private func validated(_ names: [String], grams: Double = 120) throws -> ValidatedFoodProposal {
        let proposal = FoodMealProposal(components: names.enumerated().map { i, name in
            FoodComponentProposal(id: "c\(i)", name: name, preparation: .raw, preparationText: nil,
                userAmount: nil, estimatedAmount: FoodQuantityProposal(evidenceID: nil, originalText: nil,
                    value: grams, unit: .grams, scope: .componentAmount), assumptions: ["Typical amount estimated"])
        }, mealTotal: nil, question: nil, assumptions: [])
        return try #require(FoodAmountSemanticFirewall.assess(proposal,
            context: FoodSemanticContext(description: names.joined(separator: " with "), userQuantities: [], preparationConstraints: [])).accepted)
    }

    @Test func exactSourceWinsWithoutRepresentativeSubstitution() throws {
        let p = try point(input(id: .ausnut("16502001")))
        #expect(p.method == .exactSource && p.evidence.count == 1)
        #expect(p.contributors[0].sourceID == .ausnut("16502001"))
    }
    @Test func fittingNFDUsesItsOwnWholeProfile() throws {
        let p = try point(input("apple"))
        #expect(p.method == .scopedSingleRecord && p.evidence.map(\.sourceID) == [.ausnut("16101015")])
        #expect(p.nutrition == p.envelope.lower && p.envelope.lower == p.envelope.upper)
    }
    @Test func bananaTwoRecordMedianDoesNotClaimAVariety() throws {
        let p = try point(input())
        #expect(p.method == .energyOrderedProfileMedian && p.weights == [0.5, 0.5])
        #expect(Set(p.evidence.map(\.sourceID)) == [.ausnut("16502001"), .ausnut("16502002")])
        #expect(p.nutrition.calories == p.evidence.map { $0.nutrition.calories! }.reduce(0, +) / 2)
        #expect(p.evidence.allSatisfy { $0.sourceVersion == "AUSNUT 2023" })
        #expect(!p.assumptions.isEmpty && !p.uncertainty.isEmpty)
    }
    @Test func representativeUsesOneCoherentWeightVectorForAllMacros() throws {
        let p = try point(input())
        let expected = NutritionFacts.adding(p.contributors.map { $0.nutrition.scaled(by: 0.5) })
        #expect(p.nutrition == expected)
        #expect(p.nutrition.proteinGrams! >= p.envelope.lower.proteinGrams!)
        #expect(p.nutrition.fatGrams! <= p.envelope.upper.fatGrams!)
    }
    @Test func oddProfileMedianIsAnActualCompleteCentralProfileNotIndependentMedians() throws {
        let identities = [AUSNUTFoodIdentity(id: "a", name: "Testfood, raw, variant A", measures: []),
                          AUSNUTFoodIdentity(id: "b", name: "Testfood, raw, variant B", measures: []),
                          AUSNUTFoodIdentity(id: "c", name: "Testfood, raw, variant C", measures: [])]
        let basis = try #require(EstimateGroundingPolicy.ausnutBasis(scopedQuery: "testfood raw",
            amount: GroundedAmount(value: 100, unit: .grams, provenance: .estimated),
            index: AUSNUTFoodSearchIndex(identities: identities), identity: { id in identities.first { $0.id == id } },
            resolver: { id, _ in
                let n: NutritionFacts
                switch id {
                case .ausnut("a"): n = NutritionFacts(calories: 100, proteinGrams: 9, carbohydrateGrams: 1, fatGrams: 2)
                case .ausnut("b"): n = NutritionFacts(calories: 200, proteinGrams: 1, carbohydrateGrams: 9, fatGrams: 8)
                default: n = NutritionFacts(calories: 300, proteinGrams: 5, carbohydrateGrams: 5, fatGrams: 1)
                }
                return GroundedSourceResolution(sourceID: id, sourceName: "Testfood", sourceType: .ausnut,
                    sourceVersion: "synthetic", sourceURL: nil, nutrition: n)
            }))
        let r = EstimateGroundedMealEngine.evaluate([input("testfood")], basisResolver: { _, _ in basis })
        let p = try #require(GroundedPointEstimatePolicy.point(for: r.components[0]))
        #expect(p.contributors.map(\.sourceID) == [.ausnut("b")])
        #expect(p.nutrition.proteinGrams == 1 && p.nutrition.carbohydrateGrams == 9 && p.nutrition.fatGrams == 8)
    }
    @Test func incompatiblePreparationCannotSupplyPoint() {
        let c = EstimateGroundedComponent(exactInput: input().exactInput, scopedEstimateQuery: "rice")
        #expect(GroundedPointEstimatePolicy.point(for: EstimateGroundedMealEngine.evaluate([c]).components[0]) == nil)
    }
    @Test func estimatedAmountScalesTrustedNutritionDeterministically() throws {
        let p = try point(input(grams: 60)), twice = try point(input(grams: 120))
        // Existing AUSNUT calorie rounding is retained; do not replace source arithmetic.
        #expect(abs(twice.nutrition.calories! - p.nutrition.calories! * 2) <= 1)
        #expect(abs(twice.nutrition.proteinGrams! - p.nutrition.proteinGrams! * 2) <= 0.1)
    }
    @Test func naturalPortionKeepsUserCountSeparateFromEstimatedGrams() throws {
        try natural(scope: .naturalPortion, unit: .count, value: 1, text: "one banana")
    }
    @Test func packetFractionKeepsOriginalFractionWithoutInventedPackageWeight() throws {
        try natural(scope: .packageFraction, unit: .fraction, value: 0.5, text: "half a packet")
    }
    private func natural(scope: FoodAmountScope, unit: FoodSemanticUnit, value: Double, text: String) throws {
        let q = FoodQuantityProposal(evidenceID: "q1", originalText: text, value: value, unit: unit, scope: scope)
        let proposal = FoodMealProposal(components: [FoodComponentProposal(id: "c1", name: "banana", preparation: .raw,
            preparationText: nil, userAmount: q, estimatedAmount: FoodQuantityProposal(evidenceID: nil,
                originalText: nil, value: 120, unit: .grams, scope: .componentAmount), assumptions: ["Edible weight estimated, not a package conversion"])],
            mealTotal: nil, question: nil, assumptions: [])
        let v = try #require(FoodAmountSemanticFirewall.assess(proposal, context: FoodSemanticContext(description: text,
            userQuantities: [ExplicitFoodQuantity(id: "q1", originalText: text, value: value, unit: unit, scope: scope,
                componentName: "banana")], preparationConstraints: [])).accepted)
        let r = GroundedPointEstimatePolicy.evaluate(v) { EstimateGroundedMealEngine.evaluate(GroundedPointEstimatePolicy.components(from: $0)) }
        #expect(r.loggable && r.evidence == .sourcedEstimate)
        #expect(r.validatedInput.proposal.components[0].userAmount == q)
        #expect(r.grounding.components[0].exactResult.input.amount?.provenance == .estimated)
    }
    @Test func completeMealAggregatesWithoutUpgradingEstimateToSourced() throws {
        let v = try validated(["banana", "apple"])
        let r = GroundedPointEstimatePolicy.evaluate(v) { EstimateGroundedMealEngine.evaluate(GroundedPointEstimatePolicy.components(from: $0)) }
        #expect(r.loggable && r.evidence == .sourcedEstimate)
        #expect(r.completeNutrition == NutritionFacts.adding(r.points.compactMap { $0?.nutrition }))
        #expect(r.grounding.availableEnvelope != nil)
    }
    @Test func partialMealNeverExposesCompleteNutrition() throws {
        let v = try validated(["banana", "fictional moon snack"])
        let r = GroundedPointEstimatePolicy.evaluate(v) { EstimateGroundedMealEngine.evaluate(GroundedPointEstimatePolicy.components(from: $0)) }
        #expect(!r.loggable && r.completeNutrition == nil && r.availablePoint != nil && r.evidence == .estimate)
    }
    @Test func droppedOrChangedComponentCannotMasqueradeAsWholeMeal() throws {
        let v = try validated(["banana", "apple"])
        let r = GroundedPointEstimatePolicy.evaluate(v) { _ in EstimateGroundedMealEngine.evaluate([input()]) }
        #expect(!r.loggable && r.reasons.contains("component_coverage_mismatch"))
    }
    @Test func changedExplicitAmountCannotReachLoggablePoint() throws {
        let v = try validated(["banana"])
        let r = GroundedPointEstimatePolicy.evaluate(v) { _ in EstimateGroundedMealEngine.evaluate([input(grams: 200)]) }
        #expect(!r.loggable && r.reasons.contains("unsupported_or_changed_amount_basis:c0"))
    }
    @Test func sourceOrderDoesNotChooseRepresentativeVariant() throws {
        let index = try #require(AUSNUTFoodSearchIndex.bundled())
        let reverse = AUSNUTFoodSearchIndex(identities: Array(try #require(AustralianNutritionService.searchableIdentities).reversed()))
        let a = try #require(EstimateGroundingPolicy.ausnutBasis(scopedQuery: "banana raw", amount: input().exactInput.amount!, index: index))
        let b = try #require(EstimateGroundingPolicy.ausnutBasis(scopedQuery: "banana raw", amount: input().exactInput.amount!, index: reverse))
        let normal = EstimateGroundedMealEngine.evaluate([input()], basisResolver: { _, _ in a })
        let reversed = EstimateGroundedMealEngine.evaluate([input()], basisResolver: { _, _ in b })
        #expect(try #require(GroundedPointEstimatePolicy.point(for: normal.components[0])).nutrition ==
                #require(GroundedPointEstimatePolicy.point(for: reversed.components[0])).nutrition)
    }
}
