import Foundation
import Testing
@testable import calorietracker

struct FoodAmountSemanticFirewallTests {
    private func user(_ text: String = "180 g", value: Double = 180, unit: FoodSemanticUnit = .grams,
                      scope: FoodAmountScope = .componentAmount, target: String? = "rice") -> ExplicitFoodQuantity {
        ExplicitFoodQuantity(id: "q1", originalText: text, value: value, unit: unit, scope: scope, componentName: target)
    }
    private func echo(_ q: ExplicitFoodQuantity) -> FoodQuantityProposal {
        FoodQuantityProposal(evidenceID: q.id, originalText: q.originalText, value: q.value, unit: q.unit, scope: q.scope)
    }
    private func estimate(_ value: Double, unit: FoodSemanticUnit = .grams) -> FoodQuantityProposal {
        FoodQuantityProposal(evidenceID: nil, originalText: nil, value: value, unit: unit, scope: .componentAmount)
    }
    private func component(_ name: String = "rice", user: FoodQuantityProposal? = nil,
                           estimated: FoodQuantityProposal? = nil, prep: FoodPreparationBasis = .cooked,
                           text: String? = nil) -> FoodComponentProposal {
        FoodComponentProposal(id: name, name: name, preparation: prep, preparationText: text,
            userAmount: user, estimatedAmount: estimated, assumptions: [])
    }
    private func proposal(_ components: [FoodComponentProposal], total: FoodQuantityProposal? = nil) -> FoodMealProposal {
        FoodMealProposal(components: components, mealTotal: total, question: nil, assumptions: [])
    }
    private func context(_ quantities: [ExplicitFoodQuantity] = [], description: String = "180 g rice with lentils and spinach",
                         constraints: [FoodPreparationConstraint] = []) -> FoodSemanticContext {
        FoodSemanticContext(description: description, userQuantities: quantities, preparationConstraints: constraints)
    }
    private func riceConstraint(explicit: Bool = false) -> FoodPreparationConstraint {
        FoodPreparationConstraint(componentName: "rice", explicitBasis: explicit ? .cooked : nil,
            explicitText: explicit ? "cooked" : nil, candidateBases: [.dry, .cooked], materialVariantUnresolved: false,
            candidateSourceIDs: [.ausnut("12102002"), .ausnut("12102003")])
    }

    @Test func componentSpecificExplicitGramsRemainComponentNotTotal() {
        let q = user()
        let result = FoodAmountSemanticFirewall.assess(proposal([component(user: echo(q)),
            component("lentils", estimated: estimate(45)), component("spinach", estimated: estimate(20))]), context: context([q]))
        #expect(result.outcome == .estimateWithUncertainty)
        #expect(result.accepted?.proposal.components[0].userAmount?.value == 180)
        #expect(result.accepted?.proposal.mealTotal == nil)
    }

    @Test func wholeMealTotalIsPreservedAndValidAllocationPasses() {
        let q = user(scope: .mealTotalAmount, target: nil)
        let result = FoodAmountSemanticFirewall.assess(proposal([
            component(estimated: estimate(120)), component("lentils", estimated: estimate(45)),
            component("spinach", estimated: estimate(15))], total: echo(q)), context: context([q]))
        #expect(result.accepted?.proposal.mealTotal == echo(q))
        #expect(result.outcome == .estimateWithUncertainty)
    }

    @Test func componentMassesCannotExceedExplicitMealTotal() {
        let q = user(scope: .mealTotalAmount, target: nil)
        let result = FoodAmountSemanticFirewall.assess(proposal([component(estimated: estimate(180)),
            component("lentils", estimated: estimate(45)), component("spinach", estimated: estimate(15))], total: echo(q)), context: context([q]))
        #expect(result.outcome == .invalidProviderOutput)
        #expect(result.reasons.contains("component_sum_exceeds_meal_total"))
        #expect(result.accepted == nil)
    }

    @Test func underallocationAndIncompatibleVolumeCannotBeSilentlyNormalised() {
        let q = user(scope: .mealTotalAmount, target: nil)
        for c in [component(estimated: estimate(120)), component(estimated: estimate(180, unit: .millilitres))] {
            #expect(FoodAmountSemanticFirewall.assess(proposal([c], total: echo(q)), context: context([q])).accepted == nil)
        }
    }

    @Test func packageFractionIsPreservedWithoutInventingPackageWeight() {
        let q = user("half a packet", value: 0.5, unit: .fraction, scope: .packageFraction, target: "crackers")
        let result = FoodAmountSemanticFirewall.assess(proposal([component("crackers", user: echo(q), estimated: estimate(100))]),
            context: context([q], description: "half a packet of crackers"))
        #expect(result.accepted?.proposal.components[0].userAmount == echo(q))
        #expect(result.accepted?.proposal.components[0].estimatedAmount?.value == 100)
        #expect(result.outcome == .estimateWithUncertainty)
    }

    @Test func servingCountPreservedSeparatelyFromEstimatedWeight() {
        let q = user("2 slices", value: 2, unit: .count, scope: .servingCount, target: "toast")
        let result = FoodAmountSemanticFirewall.assess(proposal([component("toast", user: echo(q), estimated: estimate(70))]),
            context: context([q], description: "2 slices of toast"))
        #expect(result.accepted?.proposal.components[0].userAmount == echo(q))
        #expect(result.accepted?.proposal.components[0].estimatedAmount?.value == 70)
    }

    @Test func naturalPortionPreservedNotReplacedByEstimatedGrams() {
        let q = user("1 banana", value: 1, unit: .count, scope: .naturalPortion, target: "banana")
        let result = FoodAmountSemanticFirewall.assess(proposal([component("banana", user: echo(q), estimated: estimate(120), prep: .raw)]),
            context: context([q], description: "1 banana"))
        #expect(result.accepted?.proposal.components[0].userAmount == echo(q))
        #expect(result.outcome == .estimateWithUncertainty)
    }

    @Test func customMillilitresPreservedWithoutDensityInvention() {
        let q = user("250 mL", value: 250, unit: .millilitres, target: "milk")
        let result = FoodAmountSemanticFirewall.assess(proposal([component("milk", user: echo(q))]),
            context: context([q], description: "250 mL milk"))
        #expect(result.accepted?.proposal.components[0].userAmount?.unit == .millilitres)
        #expect(result.accepted?.proposal.components[0].estimatedAmount == nil)
    }

    @Test func providerCannotOverwriteUserQuantityButRedundantEstimateIsLosslesslyDiscarded() {
        let q = user()
        let result = FoodAmountSemanticFirewall.assess(proposal([component(user: echo(q), estimated: estimate(250))]), context: context([q]))
        #expect(result.outcome == .repairable)
        #expect(result.original.components[0].estimatedAmount?.value == 250)
        #expect(result.accepted?.proposal.components[0].estimatedAmount == nil)
        #expect(result.accepted?.proposal.components[0].userAmount?.value == 180)
        let wrong = FoodQuantityProposal(evidenceID: "q1", originalText: "180 g", value: 250, unit: .grams, scope: .componentAmount)
        #expect(FoodAmountSemanticFirewall.assess(proposal([component(user: wrong)]), context: context([q])).outcome == .invalidProviderOutput)
    }

    @Test func scopeReinterpretationAndDuplicateExplicitAmountsFailClosed() {
        let q = user()
        let total = FoodQuantityProposal(evidenceID: "q1", originalText: "180 g", value: 180, unit: .grams, scope: .mealTotalAmount)
        #expect(FoodAmountSemanticFirewall.assess(proposal([component(estimated: estimate(180))], total: total), context: context([q])).accepted == nil)
        #expect(FoodAmountSemanticFirewall.assess(proposal([component(user: echo(q)), component("rice cooked", user: echo(q))]), context: context([q])).accepted == nil)
    }

    @Test func unknownScopeCannotBePromotedToComponentCertainty() {
        let q = user(scope: .unknownScope)
        #expect(FoodAmountSemanticFirewall.assess(proposal([component(user: echo(q))]), context: context([q])).outcome == .clarificationRequired)
    }

    @Test func dryCookedSourceAmbiguityRequiresClarificationEvenWhenProviderAssumesCooked() {
        let q = user()
        let result = FoodAmountSemanticFirewall.assess(proposal([component(user: echo(q))]), context: context([q], constraints: [riceConstraint()]))
        #expect(result.outcome == .clarificationRequired)
        #expect(result.reasons.contains("dry_or_cooked_basis:rice"))
        #expect(result.accepted == nil)
    }

    @Test func explicitCookedRiceDoesNotAskAgainAndCannotBeChangedToDry() {
        let q = user()
        let ctx = context([q], description: "180 g cooked rice", constraints: [riceConstraint(explicit: true)])
        #expect(FoodAmountSemanticFirewall.assess(proposal([component(user: echo(q), text: "cooked")]), context: ctx).outcome == .valid)
        #expect(FoodAmountSemanticFirewall.assess(proposal([component(user: echo(q), prep: .dry, text: "cooked")]), context: ctx).accepted == nil)
    }

    @Test func materialSugarVariantRequiresQuestionButOrdinaryBananaVarietyDoesNot() {
        let cola = FoodPreparationConstraint(componentName: "cola", explicitBasis: nil, explicitText: nil,
            candidateBases: [.other], materialVariantUnresolved: true,
            candidateSourceIDs: [.ausnut("fixture-regular"), .ausnut("fixture-no-sugar")])
        #expect(FoodAmountSemanticFirewall.assess(proposal([component("cola", estimated: estimate(375), prep: .other)]),
            context: context(constraints: [cola])).outcome == .clarificationRequired)
        let banana = FoodPreparationConstraint(componentName: "banana", explicitBasis: nil, explicitText: nil,
            candidateBases: [.raw], materialVariantUnresolved: false,
            candidateSourceIDs: [.ausnut("16502001"), .ausnut("16502002")])
        #expect(FoodAmountSemanticFirewall.assess(proposal([component("banana", estimated: estimate(120), prep: .raw)]),
            context: context(constraints: [banana])).outcome == .estimateWithUncertainty)
    }

    @Test func contradictoryOutputCannotInvokeGroundingOrAggregation() {
        let q = user(scope: .mealTotalAmount, target: nil)
        var called = false
        let result = SemanticGroundingGateway.evaluate(proposal([component(estimated: estimate(240))], total: echo(q)), context: context([q])) { _ in
            called = true
            return EstimateGroundedMealEngine.evaluate([])
        }
        #expect(!called && result.newResult == nil)
    }

    @Test func validProposalReachesExistingGroundingAndRetainsSourceUncertainty() {
        let p = proposal([component("banana", estimated: estimate(120), prep: .raw)])
        let result = SemanticGroundingGateway.evaluate(p, context: context()) { accepted in
            let c = accepted.proposal.components[0]
            return EstimateGroundedMealEngine.evaluate([EstimateGroundedComponent(exactInput:
                GroundedComponentInput(description: c.name, sourceID: nil,
                    amount: GroundedAmount(value: c.estimatedAmount!.value, unit: .grams, provenance: .estimated),
                    estimatedNutrition: nil, assumptions: ["Raw preparation assumed"]), scopedEstimateQuery: "banana raw")])
        }
        #expect(result.newResult?.evidence == .sourcedEstimate)
        #expect(result.newResult?.estimateGroundedCount == 1)
        #expect(result.newResult?.components[0].estimateBasis?.candidateSourceIDs.count == 2)
    }

    @Test func semanticFailurePreservesIndependentPriorProgressWithoutPublishingCurrentMeal() {
        let prior = EstimateGroundedMealEngine.evaluate([EstimateGroundedComponent(exactInput:
            GroundedComponentInput(description: "banana raw", sourceID: nil,
                amount: GroundedAmount(value: 120, unit: .grams, provenance: .estimated),
                estimatedNutrition: nil, assumptions: []), scopedEstimateQuery: "banana raw")])
        let result = SemanticGroundingGateway.evaluate(proposal([component(estimated: estimate(-1))]),
            context: context(), priorProgress: prior) { _ in EstimateGroundedMealEngine.evaluate([]) }
        #expect(result.newResult == nil)
        #expect(result.preservedPriorProgress?.availableEnvelope == prior.availableEnvelope)
        #expect(result.preservedPriorProgress?.estimateGroundedCount == 1)
    }

    @Test func malformedNonfiniteOmittedAndWrongTargetAmountsFailClosed() {
        let q = user()
        for p in [proposal([]), proposal([component(estimated: estimate(.infinity))]), proposal([component()]),
                  proposal([component("spinach", user: echo(q))])] {
            #expect(FoodAmountSemanticFirewall.assess(p, context: context([q])).outcome == .invalidProviderOutput)
        }
    }

    @Test func proposalRoundTripRetainsOriginalQuantityScopeAndAssumptions() throws {
        let q = user()
        let p = proposal([component(user: echo(q))])
        #expect(try JSONDecoder().decode(FoodMealProposal.self, from: JSONEncoder().encode(p)) == p)
    }
}
