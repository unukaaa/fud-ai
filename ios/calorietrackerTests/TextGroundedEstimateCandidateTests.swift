import Foundation
import Testing
@testable import calorietracker

struct TextGroundedEstimateCandidateTests {
    private func context(_ text: String = "fish and salad", quantities: [ExplicitFoodQuantity] = []) -> FoodSemanticContext {
        FoodSemanticContext(description: text, userQuantities: quantities, preparationConstraints: [])
    }

    private func component(_ id: String, _ name: String, grams: Double = 100,
                           user: FoodQuantityProposal? = nil) -> FoodComponentProposal {
        FoodComponentProposal(id: id, name: name, preparation: .cooked, preparationText: nil,
            userAmount: user, estimatedAmount: user?.unit == .grams ? nil : FoodQuantityProposal(
                evidenceID: nil, originalText: nil, value: grams, unit: .grams, scope: .componentAmount),
            assumptions: ["Controlled fixture amount"])
    }

    private func proposal(_ components: [FoodComponentProposal], question: String? = nil) -> FoodMealProposal {
        FoodMealProposal(components: components, mealTotal: nil, question: question, assumptions: [])
    }

    private func response(_ request: AIComponentNutritionRequest) -> AIComponentNutritionResponse {
        AIComponentNutritionResponse(proposal: AIComponentNutritionProposal(
            requestID: request.requestID, componentID: request.componentID, description: request.description,
            basis: "consumedComponent", preparation: request.preparation, preparationText: request.preparationText,
            consumedGrams: request.consumedGrams, amountProvenance: request.amountProvenance,
            originalUserQuantity: request.originalUserQuantity, calories: 60, protein: 3,
            carbohydrate: 5, fat: 3, calorieLower: 45, calorieUpper: 75,
            assumptions: ["Synthetic fixture"], uncertainty: ["Composition estimated"]),
            metadata: AINutritionProviderMetadata(provider: "fixture", model: "offline",
                timestamp: Date(timeIntervalSince1970: 0), contractVersion: AIComponentNutritionRequest.version))
    }

    @Test func exactSourceAndClarificationNeverCallProvider() async {
        var calls = 0
        let propose: TextGroundedEstimateCandidate.ProposalProvider = { _ in
            calls += 1
            return self.proposal([self.component("c", "fish")])
        }
        let nutrition: TextGroundedEstimateCandidate.NutritionProvider = { _ in calls += 1; return [] }
        let exact = await TextGroundedEstimateCandidate.run(route: .sourced("ausnut:16502001", refinements: []),
            context: context("banana"), propose: propose, estimateNutrition: nutrition)
        if case .selectSource(let id) = exact { #expect(id == "ausnut:16502001") }
        else { Issue.record("Exact source was not retained") }
        let ambiguous = await TextGroundedEstimateCandidate.run(route: .clarification(["restaurant:zinger", "restaurant:zinger-box"]),
            context: context("Zinger"), propose: propose, estimateNutrition: nutrition)
        if case .chooseSource(let ids) = ambiguous { #expect(ids.count == 2) }
        else { Issue.record("Clarification was not preserved") }
        #expect(calls == 0)
    }

    @Test func bananaUnknownVariantRequiresExplicitEstimate() async {
        var calls = 0
        let result = await TextGroundedEstimateCandidate.run(
            route: .unknownVariant(query: "banana", alternatives: ["ausnut:16502001", "ausnut:16502002"]),
            context: context("banana"), propose: { _ in calls += 1; return self.proposal([self.component("c", "banana")]) },
            estimateNutrition: { _ in calls += 1; return [] })
        if case .unresolvedVariant(_, let ids) = result { #expect(ids.count == 2) }
        else { Issue.record("Unknown variety silently advanced") }
        #expect(calls == 0)
    }

    @Test func conflictingUserBindingBlocksGroundingAndBatchFallback() async {
        let q = ExplicitFoodQuantity(id: "q1", originalText: "180 g", value: 180, unit: .grams,
            scope: .componentAmount, componentName: "rice")
        let changed = FoodQuantityProposal(evidenceID: "q1", originalText: "180 g", value: 180,
            unit: .grams, scope: .mealTotalAmount)
        var batchCalls = 0
        let result = await TextGroundedEstimateCandidate.run(route: .analyse("180 g rice with lentils"),
            context: context("180 g rice with lentils", quantities: [q]),
            permissions: ["r": .noApprovedRepresentativeBasis],
            propose: { contract in
                #expect(contract.quantities.first?.scope == .componentAmount)
                return self.proposal([self.component("r", "rice", grams: 180, user: changed)])
            }, estimateNutrition: { _ in batchCalls += 1; return [] })
        if case .blocked(let assessment) = result {
            #expect(assessment.outcome == .invalidProviderOutput && assessment.accepted == nil)
        } else { Issue.record("Invalid binding advanced") }
        #expect(batchCalls == 0)
    }

    @Test func eligibleComponentsUseOneBatchAndRemainEstimate() async {
        var batches = 0
        let result = await TextGroundedEstimateCandidate.run(route: .analyse("fish and salad"), context: context(),
            permissions: ["f": .noApprovedRepresentativeBasis, "s": .noApprovedRepresentativeBasis],
            propose: { _ in self.proposal([self.component("f", "generic cooked fish"),
                                          self.component("s", "garden salad", grams: 150)]) },
            estimateNutrition: { requests in batches += 1; return requests.map(self.response) })
        #expect(batches == 1)
        if case .complete(let meal) = result {
            #expect(meal.evidence == .estimate && meal.completeNutrition != nil)
            #expect(meal.components.allSatisfy { $0.nutrition != nil })
        } else { Issue.record("Complete bounded fallback did not produce a meal") }
    }

    @Test func providerFailurePreservesTrustedProgressWithoutPublishingPartialTotal() async {
        let result = await TextGroundedEstimateCandidate.run(route: .analyse("banana and fish"),
            context: context("banana and fish"), permissions: ["f": .noApprovedRepresentativeBasis],
            propose: { _ in self.proposal([self.component("b", "banana"), self.component("f", "fish")]) },
            estimateNutrition: { _ in throw NSError(domain: "fixture", code: 1) })
        if case .providerUnavailable(let partial) = result {
            #expect(partial?.trustedProgress != nil)
            #expect(partial?.completeNutrition == nil)
        } else { Issue.record("Provider failure discarded progress or published a meal") }
    }

    @Test func pendingMaterialQuestionNeverRequestsNutritionFallback() async {
        var batches = 0
        let result = await TextGroundedEstimateCandidate.run(route: .analyse("a can of cola"),
            context: context("a can of cola"), permissions: ["c": .noApprovedRepresentativeBasis],
            propose: { _ in self.proposal([self.component("c", "cola")], question: "Regular or no sugar?") },
            estimateNutrition: { _ in batches += 1; return [] })
        #expect(batches == 0)
        if case .incomplete(let meal) = result { #expect(meal.completeNutrition == nil) }
        else { Issue.record("Pending clarification advanced to complete result") }
    }
}
