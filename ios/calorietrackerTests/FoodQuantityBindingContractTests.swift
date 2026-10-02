import Foundation
import Testing
@testable import calorietracker

struct FoodQuantityBindingContractTests {
    private func assessment(_ name: String, scope: FoodAmountScope = .componentAmount,
                            target: String = "rice", text: String = "180 g",
                            value: Double = 180, unit: FoodSemanticUnit = .grams,
                            returnedScope: FoodAmountScope? = nil, total: Bool = false) -> FoodSemanticAssessment {
        let q = ExplicitFoodQuantity(id: "q", originalText: text, value: value, unit: unit, scope: scope, componentName: total ? nil : target)
        let echo = FoodQuantityProposal(evidenceID: "q", originalText: text, value: value, unit: unit, scope: returnedScope ?? scope)
        let c = FoodComponentProposal(id: "c", name: name, preparation: .cooked, preparationText: nil,
            userAmount: total ? nil : echo,
            estimatedAmount: total || unit != .grams ? FoodQuantityProposal(evidenceID: nil, originalText: nil, value: total ? value : 100, unit: .grams, scope: .componentAmount) : nil, assumptions: [])
        return FoodAmountSemanticFirewall.assess(FoodMealProposal(components: [c], mealTotal: total ? echo : nil, question: nil, assumptions: []),
            context: FoodSemanticContext(description: text + " " + name, userQuantities: [q], preparationConstraints: []))
    }
    @Test func riceComponentCannotBecomeContainingMixtureEvenWithCorrectScope() {
        #expect(assessment("rice with lentils and spinach").accepted == nil)
        #expect(assessment("cooked rice").accepted != nil)
    }
    @Test func riceQuantityCannotBecomeMealTotal() {
        #expect(assessment("rice", returnedScope: .mealTotalAmount).accepted == nil)
    }
    @Test func explicitWholeMealTotalStillWorks() {
        #expect(assessment("rice with lentils", scope: .mealTotalAmount, total: true).accepted != nil)
    }
    @Test func eggsRetainServingCountAndSeparateEstimatedGrams() {
        #expect(assessment("eggs", scope: .servingCount, target: "eggs", text: "2 eggs", value: 2, unit: .count).accepted != nil)
        #expect(assessment("eggs", scope: .servingCount, target: "eggs", text: "2 eggs", value: 2, unit: .count, returnedScope: .naturalPortion).accepted == nil)
    }
    @Test func breadSlicesRetainServingCount() {
        #expect(assessment("bread", scope: .servingCount, target: "bread", text: "2 slices", value: 2, unit: .count).accepted != nil)
    }
    @Test func naturalBananaCountIsNotReclassifiedAsServingCount() {
        #expect(assessment("banana", scope: .naturalPortion, target: "banana", text: "one banana", value: 1, unit: .count).accepted != nil)
        #expect(assessment("banana", scope: .naturalPortion, target: "banana", text: "one banana", value: 1, unit: .count, returnedScope: .servingCount).accepted == nil)
    }
    @Test func packageFractionRetainsOriginalBasis() {
        #expect(assessment("crackers", scope: .packageFraction, target: "crackers", text: "half packet", value: 0.5, unit: .fraction).accepted != nil)
    }
    @Test func checkedCompoundFoodIsNotRejectedByConjunction() {
        #expect(assessment("macaroni and cheese", target: "macaroni and cheese").accepted != nil)
    }
    @Test func contractSerializesCheckedScopeAndIndependentNoun() throws {
        let context = FoodSemanticContext(description: "180 g rice with lentils", userQuantities: [ExplicitFoodQuantity(id: "q", originalText: "180 g", value: 180, unit: .grams, scope: .componentAmount, componentName: "rice")], preparationConstraints: [])
        let data = try JSONEncoder().encode(FoodQuantityInterpretationContract(context: context))
        let json = try #require(JSONSerialization.jsonObject(with: data) as? [String: Any])
        let q = try #require((json["quantities"] as? [[String: Any]])?.first)
        #expect(q["scope"] as? String == "componentAmount" && q["componentName"] as? String == "rice")
        #expect(q["provenance"] as? String == "userSupplied")
        #expect(q["evidenceID"] as? String == "q" && q["value"] as? Double == 180)
    }
    @Test func multipleBindingsMustEachRemainOnTheirOwnComponent() {
        let rice = ExplicitFoodQuantity(id: "rice-q", originalText: "180 g", value: 180, unit: .grams,
            scope: .componentAmount, componentName: "rice")
        let eggs = ExplicitFoodQuantity(id: "egg-q", originalText: "2 eggs", value: 2, unit: .count,
            scope: .servingCount, componentName: "eggs")
        let proposal = FoodMealProposal(components: [
            FoodComponentProposal(id: "rice", name: "cooked rice", preparation: .cooked, preparationText: nil,
                userAmount: FoodQuantityProposal(evidenceID: "rice-q", originalText: "180 g", value: 180,
                    unit: .grams, scope: .componentAmount), estimatedAmount: nil, assumptions: []),
            FoodComponentProposal(id: "eggs", name: "eggs", preparation: .cooked, preparationText: nil,
                userAmount: FoodQuantityProposal(evidenceID: "egg-q", originalText: "2 eggs", value: 2,
                    unit: .count, scope: .servingCount), estimatedAmount: nil, assumptions: [])
        ], mealTotal: nil, question: nil, assumptions: [])
        let context = FoodSemanticContext(description: "180 g rice and 2 eggs", userQuantities: [rice, eggs], preparationConstraints: [])
        #expect(FoodAmountSemanticFirewall.assess(proposal, context: context).accepted != nil)
        let swapped = FoodMealProposal(components: [
            FoodComponentProposal(id: "rice", name: "rice", preparation: .cooked, preparationText: nil,
                userAmount: proposal.components[1].userAmount, estimatedAmount: nil, assumptions: []),
            FoodComponentProposal(id: "eggs", name: "eggs", preparation: .cooked, preparationText: nil,
                userAmount: proposal.components[0].userAmount, estimatedAmount: nil, assumptions: [])
        ], mealTotal: nil, question: nil, assumptions: [])
        #expect(FoodAmountSemanticFirewall.assess(swapped, context: context).accepted == nil)
    }
    @Test func invalidQuantityCannotReachGroundingOrFallbackSeam() {
        let q = ExplicitFoodQuantity(id: "q", originalText: "2 eggs", value: 2, unit: .count, scope: .servingCount, componentName: "eggs")
        let p = FoodMealProposal(components: [FoodComponentProposal(id: "c", name: "eggs", preparation: .cooked, preparationText: nil,
            userAmount: FoodQuantityProposal(evidenceID: "q", originalText: "2 eggs", value: 2, unit: .count, scope: .naturalPortion), estimatedAmount: nil, assumptions: [])], mealTotal: nil, question: nil, assumptions: [])
        var grounding = 0, fallback = 0
        let r = SemanticGroundingGateway.evaluate(p, context: FoodSemanticContext(description: "2 eggs", userQuantities: [q], preparationConstraints: [])) { _ in
            grounding += 1; fallback += 1
            return EstimateGroundedMealEngine.evaluate([])
        }
        #expect(grounding == 0 && fallback == 0 && r.newResult == nil)
    }
    @Test func validQuantityReachesGrounding() {
        #expect(assessment("rice").accepted != nil)
    }
}
