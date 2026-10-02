import Foundation
import Testing
@testable import calorietracker

struct AINutritionFallbackTests {
    private func component(_ name: String = "fish", id: String = "c", grams: Double = 100,
                           preparation: FoodPreparationBasis = .cooked, user: FoodQuantityProposal? = nil) -> FoodComponentProposal {
        FoodComponentProposal(id: id, name: name, preparation: preparation, preparationText: nil,
            userAmount: user, estimatedAmount: user?.unit == .grams ? nil : FoodQuantityProposal(evidenceID: nil, originalText: nil, value: grams, unit: .grams, scope: .componentAmount),
            assumptions: ["Controlled edible amount estimate"])
    }
    private func proposal(_ components: [FoodComponentProposal]) -> FoodMealProposal {
        FoodMealProposal(components: components, mealTotal: nil, question: nil, assumptions: [])
    }
    private func context(_ quantities: [ExplicitFoodQuantity] = [], constraints: [FoodPreparationConstraint] = []) -> FoodSemanticContext {
        FoodSemanticContext(description: "100 g fish and 2 eggs", userQuantities: quantities, preparationConstraints: constraints)
    }
    private func unresolved(_ v: ValidatedFoodProposal) -> EstimateGroundedMealResult {
        EstimateGroundedMealEngine.evaluate(GroundedPointEstimatePolicy.components(from: v), resolver: { _,_ in nil }, basisResolver: { _,_ in nil })
    }
    private func response(_ r: AIComponentNutritionRequest, calories: Double = 60, protein: Double = 3,
                          carbohydrate: Double = 5, fat: Double = 3, lower: Double = 45, upper: Double = 75,
                          amount: Double? = nil, basis: String = "consumedComponent", prep: FoodPreparationBasis? = nil,
                          id: String? = nil, quantity: FoodQuantityProposal? = nil, uncertainty: [String] = ["Recipe and composition estimated"]) -> AIComponentNutritionResponse {
        AIComponentNutritionResponse(proposal: AIComponentNutritionProposal(requestID: r.requestID, componentID: id ?? r.componentID,
            description: r.description, basis: basis, preparation: prep ?? r.preparation, preparationText: r.preparationText,
            consumedGrams: amount ?? r.consumedGrams, amountProvenance: r.amountProvenance, originalUserQuantity: quantity ?? r.originalUserQuantity,
            calories: calories, protein: protein, carbohydrate: carbohydrate, fat: fat, calorieLower: lower, calorieUpper: upper,
            assumptions: ["Synthetic fixture, not external truth"], uncertainty: uncertainty),
            metadata: AINutritionProviderMetadata(provider: "fixture", model: "offline", timestamp: Date(timeIntervalSince1970: 0), contractVersion: AIComponentNutritionRequest.version))
    }
    private func request() throws -> AIComponentNutritionRequest {
        let r = AINutritionFallbackPrototype.evaluate(proposal([component()]), context: context(), permissions: ["c": .noApprovedRepresentativeBasis], grounding: unresolved)
        return try #require(r.requests.first)
    }
    @Test(arguments: ["Fish", "Salad", "Tomato sauce", "Peanut butter", "Dark chocolate", "Zucchini", "Wrap flatbread", "Pepperoni pizza", "Peas"])
    func independentlyReviewedUnresolvedCategoriesCanUseOnlyEstimateLane(name: String) {
        let p = proposal([component(name, preparation: .other)])
        let r = AINutritionFallbackPrototype.evaluate(p, context: context(), permissions: ["c": .noApprovedRepresentativeBasis], grounding: unresolved, fallback: { response($0) })
        #expect(r.loggable && r.evidence == .estimate && r.components[0].aiEstimate != nil)
        #expect(r.components[0].trustedPoint == nil && r.requests.count == 1)
    }
    @Test func actualTrustedAttemptsPrecedeFallbackAndSourceIDsStayAuthoritative() {
        let p = proposal([component("banana", preparation: .raw)])
        var calls = 0
        let r = AINutritionFallbackPrototype.evaluate(p, context: context(), permissions: ["c": .noApprovedRepresentativeBasis], fallback: { _ in calls += 1; return nil })
        #expect(r.loggable && r.evidence == .sourcedEstimate && calls == 0)
        #expect(Set(r.components[0].trustedPoint!.evidence.map(\.sourceID)) == [.ausnut("16502001"), .ausnut("16502002")])
    }
    @Test func noPermissionAndRepresentationOrRetrievalPendingCannotUseFallback() {
        for permission in [[:], ["c": AINutritionFallbackReason.representationPending], ["c": .retrievalPending]] {
            var calls = 0
            let r = AINutritionFallbackPrototype.evaluate(proposal([component()]), context: context(), permissions: permission, grounding: unresolved, fallback: { _ in calls += 1; return nil })
            #expect(!r.loggable && calls == 0 && r.requests.isEmpty)
        }
    }
    @Test func contradictoryRiceScopeBlocksBothTrustedAndFallbackCalls() {
        let q = ExplicitFoodQuantity(id: "q", originalText: "180 g", value: 180, unit: .grams, scope: .componentAmount, componentName: "rice")
        let echo = FoodQuantityProposal(evidenceID: "q", originalText: "180 g", value: 180, unit: .grams, scope: .mealTotalAmount)
        let p = proposal([component("rice", grams: 180, user: echo)])
        var trusted = 0, ai = 0
        let r = AINutritionFallbackPrototype.evaluate(p, context: FoodSemanticContext(description: "180 g rice with lentils", userQuantities: [q], preparationConstraints: []), permissions: ["c": .noApprovedRepresentativeBasis], grounding: { v in trusted += 1; return unresolved(v) }, fallback: { _ in ai += 1; return nil })
        #expect(r.assessment.accepted == nil && trusted == 0 && ai == 0 && !r.loggable)
    }
    @Test func invalidEggCountCannotUseNutritionFallback() {
        let q = ExplicitFoodQuantity(id: "q", originalText: "2 eggs", value: 2, unit: .count, scope: .servingCount, componentName: "eggs")
        let echo = FoodQuantityProposal(evidenceID: "q", originalText: "2 eggs", value: 2, unit: .count, scope: .naturalPortion)
        let r = AINutritionFallbackPrototype.evaluate(proposal([component("eggs", user: echo)]), context: context([q]), permissions: ["c": .noApprovedRepresentativeBasis], grounding: unresolved, fallback: { response($0) })
        #expect(r.assessment.accepted == nil && r.requests.isEmpty && !r.loggable)
    }
    @Test func unresolvedRicePreparationCannotUseFallback() {
        let constraint = FoodPreparationConstraint(componentName: "rice", explicitBasis: nil, explicitText: nil, candidateBases: [.dry, .cooked], materialVariantUnresolved: false, candidateSourceIDs: [.ausnut("12102002"), .ausnut("12102003")])
        let r = AINutritionFallbackPrototype.evaluate(proposal([component("rice")]), context: context(constraints: [constraint]), permissions: ["c": .noApprovedRepresentativeBasis], grounding: unresolved, fallback: { response($0) })
        #expect(r.assessment.outcome == .clarificationRequired && r.requests.isEmpty)
    }
    @Test func colaRegularNoSugarCannotBeBypassed() {
        let constraint = FoodPreparationConstraint(componentName: "cola", explicitBasis: nil, explicitText: nil, candidateBases: [.other], materialVariantUnresolved: true, candidateSourceIDs: [.ausnut("fixture-regular"), .ausnut("fixture-no-sugar")])
        let r = AINutritionFallbackPrototype.evaluate(proposal([component("cola", preparation: .other)]), context: context(constraints: [constraint]), permissions: ["c": .noApprovedRepresentativeBasis], grounding: unresolved, fallback: { response($0) })
        #expect(r.assessment.outcome == .clarificationRequired && !r.loggable && r.requests.isEmpty)
    }
    @Test func unknownPreparationAndUnansweredQuestionRemainBlocked() {
        let c = component(preparation: .unknown)
        let unknown = AINutritionFallbackPrototype.evaluate(proposal([c]), context: context(), permissions: ["c": .noApprovedRepresentativeBasis], grounding: unresolved)
        #expect(unknown.requests.isEmpty && !unknown.loggable)
        let p = FoodMealProposal(components: [component()], mealTotal: nil, question: "Which kind?", assumptions: [])
        #expect(AINutritionFallbackPrototype.evaluate(p, context: context(), permissions: ["c": .noApprovedRepresentativeBasis], grounding: unresolved).requests.isEmpty)
    }
    @Test func amountPreparationComponentAndBasisEchoesCannotChange() throws {
        let q = try request()
        for p in [response(q, amount: 200), response(q, basis: "per100g"), response(q, prep: .raw), response(q, id: "whole-meal")] {
            #expect(AIComponentNutritionValidator.assess(p, for: q).outcome == .invalid)
        }
    }
    @Test func originalCountEvidenceSurvivesAndCannotBeOverwritten() throws {
        let original = FoodQuantityProposal(evidenceID: "q", originalText: "2 eggs", value: 2, unit: .count, scope: .servingCount)
        let evidence = ExplicitFoodQuantity(id: "q", originalText: "2 eggs", value: 2, unit: .count, scope: .servingCount, componentName: "eggs")
        let r = AINutritionFallbackPrototype.evaluate(proposal([component("eggs", user: original)]), context: context([evidence]), permissions: ["c": .noApprovedRepresentativeBasis], grounding: unresolved)
        let q = try #require(r.requests.first)
        #expect(q.originalUserQuantity == original && q.amountProvenance == "estimated")
        let changed = FoodQuantityProposal(evidenceID: "q", originalText: "2 eggs", value: 1, unit: .count, scope: .naturalPortion)
        #expect(AIComponentNutritionValidator.assess(response(q, quantity: changed), for: q).accepted == nil)
    }
    @Test func nonfiniteNegativeImpossibleMassAndEnergyFailClosed() throws {
        let q = try request()
        for p in [response(q, calories: .nan), response(q, protein: -1), response(q, fat: 101), response(q, calories: 1000, upper: 1100), response(q, calories: .infinity)] {
            #expect(AIComponentNutritionValidator.assess(p, for: q).outcome == .invalid)
        }
    }
    @Test func missingUncertaintyAndInvalidRangeCannotAggregate() throws {
        let q = try request()
        #expect(AIComponentNutritionValidator.assess(response(q, uncertainty: []), for: q).accepted == nil)
        #expect(AIComponentNutritionValidator.assess(response(q, lower: 70, upper: 50), for: q).accepted == nil)
    }
    @Test func macroEnergySanityUsesRangeNotPerfectAtwaterEquality() throws {
        let q = try request()
        #expect(AIComponentNutritionValidator.assess(response(q), for: q).outcome == .valid)
        #expect(AIComponentNutritionValidator.assess(response(q, lower: 60, upper: 70), for: q).outcome == .requiresReview)
    }
    @Test func mixedAggregationRetainsTrustedNutritionAndCannotBecomeSourced() {
        let p = proposal([component("banana", id: "a", preparation: .raw), component("fish", id: "b")])
        let before = AINutritionFallbackPrototype.evaluate(p, context: context(), permissions: ["b": .noApprovedRepresentativeBasis])
        let after = AINutritionFallbackPrototype.evaluate(p, context: context(), permissions: ["b": .noApprovedRepresentativeBasis], fallback: { response($0) })
        #expect(!before.loggable && after.loggable && after.evidence == .estimate)
        #expect(after.components[0].trustedPoint?.nutrition == before.components[0].trustedPoint?.nutrition)
        #expect(after.completeNutrition == NutritionFacts.adding(after.components.compactMap(\.nutrition)))
        #expect(after.components[1].aiEstimate?.response.metadata.model == "offline")
    }
    @Test func fallbackFailurePreservesTrustedProgressButNoCompleteTotal() {
        let p = proposal([component("banana", id: "a", preparation: .raw), component("fish", id: "b")])
        let r = AINutritionFallbackPrototype.evaluate(p, context: context(), permissions: ["b": .noApprovedRepresentativeBasis])
        #expect(r.availableNutrition != nil && r.completeNutrition == nil && r.trustedProgress != nil)
        #expect(r.components[0].trustedPoint != nil && r.components[1].nutrition == nil)
    }
    @Test func partialFallbackSuccessStillCannotBecomeCompleteMeal() {
        let r = AINutritionFallbackPrototype.evaluate(proposal([component("fish", id: "a"), component("salad", id: "b")]), context: context(), permissions: ["a": .noApprovedRepresentativeBasis, "b": .noApprovedRepresentativeBasis], grounding: unresolved, fallback: { $0.componentID == "a" ? response($0) : nil })
        #expect(r.availableNutrition != nil && r.completeNutrition == nil && !r.loggable && r.evidence == .estimate)
    }
    @Test func allExactTrustedUserAmountsRemainSourcedAndSkipAI() {
        let e = ExplicitFoodQuantity(id: "q", originalText: "100 g", value: 100, unit: .grams, scope: .componentAmount, componentName: "fish")
        let q = FoodQuantityProposal(evidenceID: "q", originalText: "100 g", value: 100, unit: .grams, scope: .componentAmount)
        var calls = 0
        let r = AINutritionFallbackPrototype.evaluate(proposal([component(user: q)]), context: context([e]), permissions: ["c": .noApprovedRepresentativeBasis], grounding: { v in
            let c = v.proposal.components[0]
            return EstimateGroundedMealEngine.evaluate([EstimateGroundedComponent(exactInput: GroundedComponentInput(description: c.name, sourceID: .ausnut("fixture"), amount: GroundedAmount(value: 100, unit: .grams, provenance: .user), estimatedNutrition: nil, assumptions: []), scopedEstimateQuery: nil)], resolver: { id,_ in
                GroundedSourceResolution(sourceID: id, sourceName: "fixture exact", sourceType: .ausnut, sourceVersion: "synthetic", sourceURL: nil, nutrition: NutritionFacts(calories: 60, proteinGrams: 3, carbohydrateGrams: 5, fatGrams: 3))
            })
        }, fallback: { _ in calls += 1; return nil })
        #expect(r.loggable && r.evidence == .sourced && calls == 0)
    }
    @Test func sourceIdentityAndQuantityMismatchCannotBeMaskedByFallback() {
        let r = AINutritionFallbackPrototype.evaluate(proposal([component()]), context: context(), permissions: ["c": .noApprovedRepresentativeBasis], grounding: { _ in EstimateGroundedMealEngine.evaluate([]) }, fallback: { response($0) })
        #expect(!r.loggable && r.requests.isEmpty)
    }
    @Test func semanticFailurePreservesIndependentPriorProgressOnly() {
        let priorValid = FoodAmountSemanticFirewall.assess(proposal([component("banana", preparation: .raw)]), context: context()).accepted!
        let prior = GroundedPointEstimatePolicy.evaluate(priorValid) { EstimateGroundedMealEngine.evaluate(GroundedPointEstimatePolicy.components(from: $0)) }
        let r = AINutritionFallbackPrototype.evaluate(proposal([component(grams: -1)]), context: context(), permissions: ["c": .noApprovedRepresentativeBasis], priorProgress: prior)
        #expect(r.trustedProgress == nil && r.preservedPriorProgress?.completeNutrition == prior.completeNutrition && r.completeNutrition == nil)
    }
    @Test func requestBindingIsStableForReplayButChangesWithContext() throws {
        let first = try request(), second = try request()
        #expect(first.requestID == second.requestID)
        let changed = AINutritionFallbackPrototype.evaluate(proposal([component()]), context: FoodSemanticContext(description: "different meal", userQuantities: [], preparationConstraints: []), permissions: ["c": .noApprovedRepresentativeBasis], grounding: unresolved)
        #expect(changed.requests.first?.requestID != first.requestID)
    }
}
