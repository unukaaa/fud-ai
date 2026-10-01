import Testing
@testable import calorietracker

struct FoodQuantityAttachmentTests {
    @Test func riceAttachmentRetainsCheckedScopeAndNounRatherThanForcingProviderToGuess() {
        let e = ExplicitFoodQuantity(id: "q1", originalText: "180 g", value: 180, unit: .grams,
            scope: .componentAmount, componentName: "rice")
        let a = FoodQuantityAttachment(e)
        #expect(a.scope == .componentAmount && a.componentName == "rice" && a.value == 180)
        let echoed = FoodQuantityProposal(evidenceID: a.evidenceID, originalText: a.originalText, value: a.value, unit: a.unit, scope: a.scope)
        let c = FoodComponentProposal(id: "c1", name: "rice", preparation: .cooked, preparationText: nil,
            userAmount: echoed, estimatedAmount: nil, assumptions: [])
        let p = FoodMealProposal(components: [c], mealTotal: nil, question: nil, assumptions: [])
        let context = FoodSemanticContext(description: "180 g rice with lentils and spinach", userQuantities: [e], preparationConstraints: [])
        #expect(FoodAmountSemanticFirewall.assess(p, context: context).accepted != nil)
        let wrong = FoodQuantityProposal(evidenceID: a.evidenceID, originalText: a.originalText, value: a.value, unit: a.unit, scope: .mealTotalAmount)
        #expect(FoodAmountSemanticFirewall.assess(FoodMealProposal(components: [c], mealTotal: wrong, question: nil, assumptions: []), context: context).accepted == nil)
    }
    @Test(arguments: ["eggs", "bread slices"])
    func independentlyCheckedServingCountIsNotDowngradedToNaturalPortion(food: String) {
        let e = ExplicitFoodQuantity(id: "q1", originalText: "2 \(food)", value: 2, unit: .count, scope: .servingCount, componentName: food)
        let a = FoodQuantityAttachment(e)
        #expect(a.scope == .servingCount && a.componentName == food && a.value == 2)
        let echo = FoodQuantityProposal(evidenceID: "q1", originalText: e.originalText, value: 2, unit: .count, scope: .naturalPortion)
        let p = FoodMealProposal(components: [FoodComponentProposal(id: "c1", name: food, preparation: .other,
            preparationText: nil, userAmount: echo, estimatedAmount: nil, assumptions: [])], mealTotal: nil, question: nil, assumptions: [])
        #expect(FoodAmountSemanticFirewall.assess(p, context: FoodSemanticContext(description: e.originalText,
            userQuantities: [e], preparationConstraints: [])).accepted == nil)
    }
    @Test func unknownAttachmentCannotManufactureScopeOrSource() {
        let a = FoodQuantityAttachment(ExplicitFoodQuantity(id: "q1", originalText: "one portion", value: 1, unit: .count, scope: .unknownScope, componentName: nil))
        #expect(a.scope == .unknownScope && a.componentName == nil)
    }
}
