import Testing
@testable import calorietracker

struct PortionSuggestionPolicyTests {
    @Test func zeroRemainingBudgetSuggestsNoPortion() {
        let plan = PortionSuggestionPolicy.plan(
            entry: entry(name: "Oatmeal"),
            currentCalories: 2_000,
            calorieGoal: 2_000
        )

        #expect(plan.maximumFraction == 0)
        #expect(plan.suggestedFraction == 0)
        #expect(plan.suggestedFraction <= plan.maximumFraction)
    }

    @Test func tinyBudgetDoesNotSuggestMoreThanTheMaximumCountablePortion() {
        let plan = PortionSuggestionPolicy.plan(
            entry: entry(name: "Biscuits", grams: 150),
            currentCalories: 1_990,
            calorieGoal: 2_000
        )

        #expect(plan.maximumFraction == 0)
        #expect(plan.suggestedFraction == 0)
        #expect(plan.suggestedFraction <= plan.maximumFraction)
    }

    @Test func normalBudgetPreservesTheExistingSuggestion() {
        let plan = PortionSuggestionPolicy.plan(
            entry: entry(name: "Oatmeal"),
            currentCalories: 1_850,
            calorieGoal: 2_000
        )

        #expect(plan.maximumFraction == 0.75)
        #expect(plan.suggestedFraction == 0.675)
    }

    @Test func minimumUsefulFractionMayEqualTheMaximum() {
        let plan = PortionSuggestionPolicy.plan(
            entry: entry(name: "Oatmeal"),
            currentCalories: 1_990,
            calorieGoal: 2_000
        )

        #expect(plan.maximumFraction == 0.05)
        #expect(plan.suggestedFraction == plan.maximumFraction)
    }

    private func entry(name: String, grams: Double? = nil) -> FoodEntry {
        FoodEntry(
            name: name,
            calories: 200,
            protein: 5,
            carbs: 30,
            fat: 5,
            source: .manual,
            servingSizeGrams: grams
        )
    }
}
