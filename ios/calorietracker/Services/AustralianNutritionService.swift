import Foundation

enum AustralianNutritionService {
    private final class ResourceBundleToken {}

    private struct Database: Decodable {
        let foods: [Food]
    }

    private struct Food: Decodable {
        let id: String
        let key: String?
        let name: String
        let description: String?
        let derivation: String?
        let kcal: Double
        let protein: Double
        let carbs: Double
        let fat: Double
        let sugar: Double?
        let addedSugar: Double?
        let fiber: Double?
        let saturatedFat: Double?
        let monounsaturatedFat: Double?
        let polyunsaturatedFat: Double?
        let transFatMg: Double?
        let cholesterol: Double?
        let caffeine: Double?
        let sodium: Double?
        let potassium: Double?
        let calcium: Double?
        let iron: Double?
        let magnesium: Double?
        let zinc: Double?
        let vitaminA: Double?
        let vitaminC: Double?
        let vitaminD: Double?
        let vitaminB12: Double?
        let vitaminE: Double?
        let folate: Double?
        let omega3Mg: Double?
    }

    private struct Match {
        let food: Food
        let score: Double
    }

    private static let database: Database? = {
        let bundles = [Bundle.main, Bundle(for: ResourceBundleToken.self)]
        guard let url = bundles.compactMap({ $0.url(forResource: "ausnut2023", withExtension: "json") }).first,
              let data = try? Data(contentsOf: url)
        else { return nil }
        return try? JSONDecoder().decode(Database.self, from: data)
    }()

    static func applyingBestAustralianMatch(to analysis: GeminiService.FoodAnalysis) -> GeminiService.FoodAnalysis {
        guard analysis.productMetadata == nil, analysis.servingSizeIsKnown, analysis.servingSizeGrams > 0 else {
            return analysis
        }

        if analysis.ingredients.isEmpty {
            guard let match = bestMatch(for: analysis.name) else { return analysis }
            return applying(match: match, grams: analysis.servingSizeGrams, to: analysis)
        }

        var matchedCount = 0
        var matchedIngredients = analysis.ingredients
        for index in matchedIngredients.indices {
            let ingredient = matchedIngredients[index]
            guard let match = bestMatch(for: ingredient.name) else { continue }
            let scale = ingredient.grams / 100
            matchedIngredients[index].calories = Int((match.food.kcal * scale).rounded())
            matchedIngredients[index].protein = rounded(match.food.protein * scale)
            matchedIngredients[index].carbs = rounded(match.food.carbs * scale)
            matchedIngredients[index].fat = rounded(match.food.fat * scale)
            matchedCount += 1
        }

        guard matchedCount > 0 else { return analysis }
        var result = analysis
        result.ingredients = matchedIngredients
        result = result.withIngredientMacroTotals()
        result.nutritionSource = "AUSNUT Australia"
        result.nutritionSourceDetail = "\(matchedCount) of \(matchedIngredients.count) ingredients matched to AUSNUT 2023"
        result.nutritionConfidence = matchedCount == matchedIngredients.count ? "High" : "Medium"
        return result
    }

    private static func applying(match: Match, grams: Double, to analysis: GeminiService.FoodAnalysis) -> GeminiService.FoodAnalysis {
        let food = match.food
        let scale = grams / 100
        var result = analysis
        result.calories = Int((food.kcal * scale).rounded())
        result.protein = rounded(food.protein * scale)
        result.carbs = rounded(food.carbs * scale)
        result.fat = rounded(food.fat * scale)
        result.sugar = scaled(food.sugar, by: scale)
        result.addedSugar = scaled(food.addedSugar, by: scale)
        result.fiber = scaled(food.fiber, by: scale)
        result.saturatedFat = scaled(food.saturatedFat, by: scale)
        result.monounsaturatedFat = scaled(food.monounsaturatedFat, by: scale)
        result.polyunsaturatedFat = scaled(food.polyunsaturatedFat, by: scale)
        result.transFat = scaled(food.transFatMg, by: scale).map { $0 / 1_000 }
        result.cholesterol = scaled(food.cholesterol, by: scale)
        result.caffeine = scaled(food.caffeine, by: scale)
        result.sodium = scaled(food.sodium, by: scale)
        result.potassium = scaled(food.potassium, by: scale)
        result.calcium = scaled(food.calcium, by: scale)
        result.iron = scaled(food.iron, by: scale)
        result.magnesium = scaled(food.magnesium, by: scale)
        result.zinc = scaled(food.zinc, by: scale)
        result.vitaminA = scaled(food.vitaminA, by: scale)
        result.vitaminC = scaled(food.vitaminC, by: scale)
        result.vitaminD = scaled(food.vitaminD, by: scale)
        result.vitaminB12 = scaled(food.vitaminB12, by: scale)
        result.vitaminE = scaled(food.vitaminE, by: scale)
        result.folate = scaled(food.folate, by: scale)
        result.omega3 = scaled(food.omega3Mg, by: scale).map { $0 / 1_000 }
        result.nutritionSource = "AUSNUT Australia"
        result.nutritionSourceDetail = "Matched: \(food.name)"
        result.nutritionConfidence = confidence(for: match)
        return result
    }

    private static func bestMatch(for query: String) -> Match? {
        guard let foods = database?.foods else { return nil }
        let queryTokens = tokens(query)
        guard queryTokens.count >= 2 else { return nil }

        let ranked = foods.compactMap { food -> Match? in
            let candidateTokens = tokens(food.name)
            let shared = queryTokens.intersection(candidateTokens)
            guard shared.count >= 2,
                  !hasPreparationConflict(queryTokens, candidateTokens),
                  !hasCoreFoodConflict(queryTokens, candidateTokens),
                  !hasDishFormConflict(queryTokens, candidateTokens)
            else { return nil }
            let coverage = Double(shared.count) / Double(queryTokens.count)
            let precision = Double(shared.count) / Double(max(candidateTokens.count, 1))
            let exactBonus = normalize(food.name).contains(normalize(query)) ? 0.04 : 0
            let addedFatAdjustment: Double = {
                let userSpecifiedAddedFat = !queryTokens.isDisjoint(with: ["oil", "butter", "fat"])
                let candidateSaysNoAddedFat = candidateTokens.isSuperset(of: ["no", "added", "fat"])
                let candidateSaysAddedFat = candidateTokens.isSuperset(of: ["added", "fat"]) && !candidateSaysNoAddedFat
                if !userSpecifiedAddedFat && candidateSaysNoAddedFat { return 0.05 }
                if !userSpecifiedAddedFat && candidateSaysAddedFat { return -0.05 }
                return 0
            }()
            return Match(food: food, score: min(coverage * 0.78 + precision * 0.22 + exactBonus + addedFatAdjustment, 1))
        }
        .sorted { $0.score > $1.score }

        guard let best = ranked.first, best.score >= 0.72 else { return nil }
        if let second = ranked.dropFirst().first,
           best.score - second.score < 0.035 {
            // Short descriptions such as "cooked rice" can fit several
            // materially different AUSNUT foods. Keep the AI estimate until
            // the user supplies a useful qualifier such as white or brown.
            if queryTokens.count <= 2 || best.score < 0.88 { return nil }
        }
        return best
    }

    private static func confidence(for match: Match) -> String {
        let derivation = match.food.derivation?.lowercased() ?? ""
        if match.score >= 0.88 && derivation.contains("analysed") { return "High" }
        return "Medium"
    }

    private static func tokens(_ value: String) -> Set<String> {
        let stopwords: Set<String> = ["and", "with", "the", "a", "an", "of", "style", "food", "meal", "plain"]
        return Set(normalize(value)
            .split(separator: " ")
            .map(String.init)
            .map(singularized)
            .filter { $0.count > 1 && !stopwords.contains($0) })
    }

    private static func normalize(_ value: String) -> String {
        value.folding(options: [.diacriticInsensitive, .caseInsensitive], locale: .current)
            .lowercased()
            .replacingOccurrences(of: "bbq", with: "barbecued")
            .replacingOccurrences(of: "chips", with: "crisps")
            .replacingOccurrences(of: "yogurt", with: "yoghurt")
            .replacingOccurrences(of: "[^a-z0-9]+", with: " ", options: .regularExpression)
            .trimmingCharacters(in: .whitespacesAndNewlines)
    }

    nonisolated private static func singularized(_ token: String) -> String {
        if token == "jasmine" { return "white" }
        if token == "toast" { return "toasted" }
        if token.hasSuffix("ies"), token.count > 4 { return String(token.dropLast(3)) + "y" }
        if token.hasSuffix("s"), token.count > 3, !token.hasSuffix("ss") { return String(token.dropLast()) }
        return token
    }

    private static func hasPreparationConflict(_ query: Set<String>, _ candidate: Set<String>) -> Bool {
        let raw = "raw"
        let cooked: Set<String> = ["cooked", "baked", "roasted", "fried", "grilled", "barbecued", "boiled", "steamed", "poached"]
        if query.contains(raw) && !candidate.contains(raw) { return true }
        if !query.isDisjoint(with: cooked) && candidate.contains(raw) { return true }
        return false
    }

    private static func hasCoreFoodConflict(_ query: Set<String>, _ candidate: Set<String>) -> Bool {
        let coreFoods: Set<String> = [
            "chicken", "beef", "pork", "lamb", "turkey", "venison", "duck",
            "salmon", "tuna", "prawn", "shrimp", "fish", "cauliflower", "broccoli",
            "potato", "banana", "apple", "rice", "pasta", "egg"
        ]
        let queryCore = query.intersection(coreFoods)
        let candidateCore = candidate.intersection(coreFoods)
        return !candidateCore.subtracting(queryCore).isEmpty
    }

    private static func hasDishFormConflict(_ query: Set<String>, _ candidate: Set<String>) -> Bool {
        let distinctDishes: Set<String> = ["omelette", "meatball", "rissole", "nugget", "schnitzel", "pie", "pizza", "burger"]
        return !candidate.intersection(distinctDishes).subtracting(query).isEmpty
    }

    private static func scaled(_ value: Double?, by scale: Double) -> Double? {
        value.map { rounded($0 * scale) }
    }

    private static func rounded(_ value: Double) -> Double {
        (value * 10).rounded() / 10
    }
}
