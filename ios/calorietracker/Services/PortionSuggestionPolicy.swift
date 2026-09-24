import Foundation

struct PortionSuggestionPlan {
    let suggestedFraction: Double
    let maximumFraction: Double
    let suggestedDescription: String
    let maximumDescription: String
}

/// Deterministic, human-readable portion rules shared by the suggestion text
/// and the buttons that apply it. This prevents an AI-generated unit such as
/// "cup" from leaking into obviously countable snack foods.
enum PortionSuggestionPolicy {
    private struct InferredUnit {
        let singular: String
        let plural: String
        let gramsPerUnit: Double
        let comfortableCount: Double
    }

    static func plan(entry: FoodEntry, currentCalories: Int, calorieGoal: Int) -> PortionSuggestionPlan {
        let totalCalories = max(entry.calories, 0)
        let totalGrams = entry.servingSizeGrams ?? 0
        let name = entry.name.lowercased()
        let isMixedMeal = entry.ingredients.count > 1 || name.contains(" & ")
        let inferredUnit = isMixedMeal ? nil : inferredCountableUnit(for: name)
        let groundedUnit = isMixedMeal ? nil : groundedCountableUnit(from: entry)
        let countableUnit: InferredUnit? = {
            if let inferredUnit, let groundedUnit {
                return InferredUnit(
                    singular: inferredUnit.singular,
                    plural: inferredUnit.plural,
                    gramsPerUnit: groundedUnit.gramsPerUnit,
                    comfortableCount: inferredUnit.comfortableCount
                )
            }
            return inferredUnit ?? groundedUnit
        }()

        let caloriesAvailable = max(calorieGoal - currentCalories, 0)
        let rawMaximum = totalCalories > 0
            ? min(max(Double(caloriesAvailable) / Double(totalCalories), 0), 1)
            : 1
        let maximum = snapMaximum(rawMaximum, totalGrams: totalGrams, unit: countableUnit)

        let comfortableFraction: Double = {
            if let unit = countableUnit, totalGrams > 0 {
                return min(max(unit.comfortableCount * unit.gramsPerUnit / totalGrams, 0.01), 1)
            }
            if let grams = comfortableServingGrams(for: name), totalGrams > 0 {
                return min(max(grams / totalGrams, 0.05), 1)
            }
            return 1
        }()
        let minimumUsefulFraction: Double = {
            guard let unit = countableUnit, totalGrams > 0 else { return 0.05 }
            return min(max(unit.gramsPerUnit / totalGrams, 0.01), 1)
        }()
        let rawSuggested = min(max(maximum * 0.9, minimumUsefulFraction), comfortableFraction)
        let suggested = snapSuggested(rawSuggested, totalGrams: totalGrams, unit: countableUnit)

        return PortionSuggestionPlan(
            suggestedFraction: suggested,
            maximumFraction: maximum,
            suggestedDescription: description(
                fraction: suggested,
                isMaximum: false,
                entry: entry,
                inferredUnit: countableUnit,
                isMixedMeal: isMixedMeal
            ),
            maximumDescription: description(
                fraction: maximum,
                isMaximum: true,
                entry: entry,
                inferredUnit: countableUnit,
                isMixedMeal: isMixedMeal
            )
        )
    }

    private static func inferredCountableUnit(for name: String) -> InferredUnit? {
        if name.contains("wafer roll") {
            return InferredUnit(singular: "wafer roll", plural: "wafer rolls", gramsPerUnit: 10, comfortableCount: 3)
        }
        if name.contains("biscuit") {
            return InferredUnit(singular: "biscuit", plural: "biscuits", gramsPerUnit: 15, comfortableCount: 2)
        }
        if name.contains("cookie") {
            return InferredUnit(singular: "cookie", plural: "cookies", gramsPerUnit: 15, comfortableCount: 2)
        }
        if name.contains("cracker") {
            return InferredUnit(singular: "cracker", plural: "crackers", gramsPerUnit: 7, comfortableCount: 4)
        }
        if name.contains("tortilla chip") || name.contains("corn chip") {
            return InferredUnit(singular: "chip", plural: "chips", gramsPerUnit: 3, comfortableCount: 10)
        }
        if name.contains("potato chip") || name.contains("crisps")
            || (name.contains("chips") && !name.contains("hot chips") && !name.contains("fish and chips") && !name.contains("fries")) {
            return InferredUnit(singular: "chip", plural: "chips", gramsPerUnit: 2, comfortableCount: 15)
        }
        if name.contains("wafer") {
            return InferredUnit(singular: "wafer", plural: "wafers", gramsPerUnit: 10, comfortableCount: 2)
        }
        return nil
    }

    private static func groundedCountableUnit(from entry: FoodEntry) -> InferredUnit? {
        let supported: Set<String> = [
            "chip", "chips", "biscuit", "biscuits", "cookie", "cookies", "cracker", "crackers",
            "wafer", "wafers", "roll", "rolls", "slice", "slices", "piece", "pieces", "wing", "wings"
        ]
        guard let option = entry.servingUnitOptions.first(where: {
            let quantity = $0.quantity(for: entry.servingSizeGrams ?? 0)
            return $0.isValid && supported.contains($0.normalizedUnit) && quantity > 0 && quantity <= 200
        }) else { return nil }

        let singular: String
        switch option.normalizedUnit {
        case "chips": singular = "chip"
        case "biscuits": singular = "biscuit"
        case "cookies": singular = "cookie"
        case "crackers": singular = "cracker"
        case "wafers": singular = "wafer"
        case "rolls": singular = "roll"
        case "slices": singular = "slice"
        case "pieces": singular = "piece"
        case "wings": singular = "wing"
        default: singular = option.normalizedUnit
        }
        let plural = option.displayUnit(for: 2)
        let comfortableCount: Double
        switch singular {
        case "chip": comfortableCount = 15
        case "biscuit", "cookie", "wafer": comfortableCount = 2
        case "cracker": comfortableCount = 4
        default: comfortableCount = 2
        }
        return InferredUnit(
            singular: singular,
            plural: plural,
            gramsPerUnit: option.gramsPerUnit,
            comfortableCount: comfortableCount
        )
    }

    private static func comfortableServingGrams(for name: String) -> Double? {
        if name.contains("popcorn") { return 25 }
        if name.contains("nuts") || name.contains("almond") || name.contains("cashew") { return 30 }
        return nil
    }

    private static func snapMaximum(_ fraction: Double, totalGrams: Double, unit: InferredUnit?) -> Double {
        guard let unit, totalGrams > 0 else { return fraction }
        let wholeUnits = floor(totalGrams * fraction / unit.gramsPerUnit)
        return min(max(wholeUnits * unit.gramsPerUnit / totalGrams, 0), 1)
    }

    private static func snapSuggested(_ fraction: Double, totalGrams: Double, unit: InferredUnit?) -> Double {
        guard let unit, totalGrams > 0 else { return fraction }
        let wholeUnits = max((totalGrams * fraction / unit.gramsPerUnit).rounded(), 1)
        return min(wholeUnits * unit.gramsPerUnit / totalGrams, 1)
    }

    private static func description(
        fraction: Double,
        isMaximum: Bool,
        entry: FoodEntry,
        inferredUnit: InferredUnit?,
        isMixedMeal: Bool
    ) -> String {
        if isMaximum && fraction <= 0.0001 {
            return "none fits today's remaining calories"
        }

        if let unit = inferredUnit, let totalGrams = entry.servingSizeGrams, totalGrams > 0 {
            let count = max(Int((totalGrams * fraction / unit.gramsPerUnit).rounded()), 1)
            return "about \(count) \(count == 1 ? unit.singular : unit.plural)"
        }

        if !isMixedMeal, let grounded = groundedDescription(fraction: fraction, entry: entry) {
            return grounded
        }

        if isMaximum && fraction >= 0.995 { return "the full photographed portion" }
        if fraction >= 0.875 { return "nearly all of the photographed portion" }
        if fraction >= 0.70 { return "about three-quarters of the photographed portion" }
        if fraction >= 0.58 { return "about two-thirds of the photographed portion" }
        if fraction >= 0.45 { return "about half of the photographed portion" }
        if fraction >= 0.29 { return "about one-third of the photographed portion" }
        if fraction >= 0.20 { return "about one-quarter of the photographed portion" }
        return "a small taste of the photographed portion"
    }

    private static func groundedDescription(fraction: Double, entry: FoodEntry) -> String? {
        let name = entry.name.lowercased()
        let countable: Set<String> = [
            "chip", "chips", "biscuit", "biscuits", "cookie", "cookies", "slice", "slices",
            "piece", "pieces", "wing", "wings", "cracker", "crackers", "roll", "rolls"
        ]
        let handful: Set<String> = ["handful", "handfuls"]
        let spoon: Set<String> = ["tbsp", "tablespoon", "tablespoons", "tsp", "teaspoon", "teaspoons"]
        let cup: Set<String> = ["cup", "cups"]
        let supportsHandful = name.contains("popcorn") || name.contains("nuts") || name.contains("almond") || name.contains("cashew")
        let supportsSpoon = name.contains("dip") || name.contains("sauce") || name.contains("spread") || name.contains("dressing")
        let supportsCup = ["rice", "pasta", "oats", "cereal", "yogurt", "yoghurt", "soup", "salad", "beans", "lentils", "ice cream"]
            .contains(where: name.contains)

        guard let option = entry.servingUnitOptions.first(where: { option in
            let unit = option.normalizedUnit
            let isSensibleUnit = countable.contains(unit)
                || (handful.contains(unit) && supportsHandful)
                || (spoon.contains(unit) && supportsSpoon)
                || (cup.contains(unit) && supportsCup)
            let quantity = option.quantity(for: entry.servingSizeGrams ?? 0)
            return option.isValid && !option.isGramUnit && isSensibleUnit && quantity > 0 && quantity <= 200
        }) else { return nil }

        let wholeQuantity: Double
        if entry.selectedServingUnit?.lowercased() == option.normalizedUnit,
           let selected = entry.selectedServingQuantity, selected.isFinite, selected > 0 {
            wholeQuantity = selected
        } else {
            wholeQuantity = option.quantity(for: entry.servingSizeGrams ?? 0)
        }
        let quantity = wholeQuantity * fraction
        let displayed = countable.contains(option.normalizedUnit)
            ? String(max(Int(quantity.rounded()), 1))
            : (abs(quantity.rounded() - quantity) < 0.05
                ? String(Int(quantity.rounded()))
                : String(format: "%.1f", quantity))
        return "about \(displayed) \(option.displayUnit(for: quantity))"
    }
}
