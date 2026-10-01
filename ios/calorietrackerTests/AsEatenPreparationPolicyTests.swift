import Testing
@testable import calorietracker

struct AsEatenPreparationPolicyTests {
    private func evidence(_ bases: Set<FoodPreparationBasis>, explicit: FoodPreparationBasis? = nil,
                          context: AsEatenPreparationEvidence.Context = .ordinaryMeal,
                          relationship: AsEatenPreparationEvidence.AmountRelationship = .consumedFood,
                          mode: AsEatenPreparationEvidence.Mode = .estimate,
                          source: FoodPreparationBasis? = nil) -> AsEatenPreparationEvidence {
        AsEatenPreparationEvidence(mode: mode, context: context, relationship: relationship,
            explicitUserBasis: explicit, exactSourceBasis: source, supportedBases: bases)
    }

    @Test func explicitCookedAndDryRiceRemainDistinct() {
        for state in [FoodPreparationBasis.cooked, .dry] {
            let result = AsEatenPreparationPolicy.assess(evidence([.dry, .cooked], explicit: state))
            #expect(result.basis == state && !result.requiresClarification && result.assumption == nil)
        }
    }
    @Test func ordinaryMealRiceAndPastaUsePreparedBasisWithAssumption() {
        for _ in ["I ate 100 g rice with chicken", "150 g pasta with bolognese", "100 g rice"] {
            let result = AsEatenPreparationPolicy.assess(evidence([.dry, .cooked]))
            #expect(result.basis == .cooked && !result.requiresClarification)
            #expect(result.assumption != nil)
        }
    }
    @Test func recipeRiceAndUncookedPastaRemainPreCook() {
        #expect(AsEatenPreparationPolicy.assess(evidence([.dry, .cooked], context: .recipeIngredient)).basis == .dry)
        #expect(AsEatenPreparationPolicy.assess(evidence([.dry, .cooked], explicit: .dry)).basis == .dry)
    }
    @Test func explicitRawChickenWinsAndMealContextChickenMayBePrepared() {
        #expect(AsEatenPreparationPolicy.assess(evidence([.raw, .cooked], explicit: .raw)).basis == .raw)
        #expect(AsEatenPreparationPolicy.assess(evidence([.raw, .cooked])).basis == .cooked)
    }
    @Test func weighedOatsIngredientIsDistinctFromConsumedPorridge() {
        let oats = AsEatenPreparationPolicy.assess(evidence([.dry, .cooked], relationship: .ingredientBeforeCooking))
        let porridge = AsEatenPreparationPolicy.assess(evidence([.cooked]))
        #expect(oats.basis == .dry && porridge.basis == .cooked)
        #expect(oats.assumption != nil && porridge.assumption != nil)
        // Policy never changes 30 g into a cooked yield or invents cooking water.
        #expect(oats.reason == "pre_cook_ingredient_amount")
    }
    @Test func bowlOfPorridgeUsesPreparedBasisButDoesNotInventAnAmount() {
        let result = AsEatenPreparationPolicy.assess(evidence([.cooked]))
        #expect(result.basis == .cooked && result.assumption != nil)
    }
    @Test func barcodeBasisCannotBeOverriddenByAsEatenConvention() {
        #expect(AsEatenPreparationPolicy.assess(evidence([.dry, .cooked], source: .dry)).basis == .dry)
        let conflict = AsEatenPreparationPolicy.assess(evidence([.dry, .cooked], explicit: .cooked, source: .dry))
        #expect(conflict.basis == .dry && conflict.requiresClarification)
    }
    @Test func exactModeAndGenuineAmbiguityRemainStrict() {
        #expect(AsEatenPreparationPolicy.assess(evidence([.dry, .cooked], mode: .exactSource)).basis == nil)
        #expect(AsEatenPreparationPolicy.assess(evidence([.dry, .cooked], context: .genuinelyAmbiguous)).requiresClarification)
        #expect(AsEatenPreparationPolicy.assess(evidence([.raw, .fried], context: .genuinelyAmbiguous)).requiresClarification)
    }
    @Test func estimateConventionPassesFirewallAndAssumptionSurvivesWithoutIdentityClaim() throws {
        let p = FoodMealProposal(components: [FoodComponentProposal(id: "rice", name: "rice", preparation: .cooked,
            preparationText: nil, userAmount: nil,
            estimatedAmount: FoodQuantityProposal(evidenceID: nil, originalText: nil, value: 180, unit: .grams, scope: .componentAmount),
            assumptions: [])], mealTotal: nil, question: nil, assumptions: [])
        let constraint = FoodPreparationConstraint(componentName: "rice", explicitBasis: nil, explicitText: nil,
            candidateBases: [.dry, .cooked], materialVariantUnresolved: false,
            candidateSourceIDs: [.ausnut("12102002"), .ausnut("12102003")], estimateInterpretation: evidence([.dry, .cooked]))
        let result = FoodAmountSemanticFirewall.assess(p, context: FoodSemanticContext(description: "rice for lunch",
            userQuantities: [], preparationConstraints: [constraint]))
        let accepted = try #require(result.accepted)
        #expect(result.outcome == .estimateWithUncertainty)
        #expect(accepted.proposal.components[0].assumptions.contains { $0.contains("ordinary_meal_as_eaten") })
    }
    @Test func contradictoryProviderDryBasisCannotReachGroundingInMealContext() {
        let p = FoodMealProposal(components: [FoodComponentProposal(id: "rice", name: "rice", preparation: .dry,
            preparationText: nil, userAmount: nil, estimatedAmount: nil, assumptions: [])], mealTotal: nil, question: nil, assumptions: [])
        let constraint = FoodPreparationConstraint(componentName: "rice", explicitBasis: nil, explicitText: nil,
            candidateBases: [.dry, .cooked], materialVariantUnresolved: false,
            candidateSourceIDs: [.ausnut("12102002"), .ausnut("12102003")], estimateInterpretation: evidence([.dry, .cooked]))
        let result = FoodAmountSemanticFirewall.assess(p, context: FoodSemanticContext(description: "rice for lunch",
            userQuantities: [], preparationConstraints: [constraint]))
        #expect(result.outcome == .invalidProviderOutput && result.accepted == nil)
    }
}
