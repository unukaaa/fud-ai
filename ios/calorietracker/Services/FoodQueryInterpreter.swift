import Foundation

struct FoodQueryIntent: Equatable, Sendable {
    struct Item: Equatable, Sendable {
        let rawSpan: String
        let interpretedName: String
        let restaurantID: String?
        let category: String?
        let confidence: Double
    }

    let rawText: String
    let interpretedText: String
    let items: [Item]
    let restaurantID: String?
    let confidence: Double

    var hasMultipleItems: Bool { items.count > 1 }
}

/// Converts noisy typed or dictated food language into conservative canonical
/// food terms. Nutrition remains the responsibility of the existing resolvers.
enum FoodQueryInterpreter {
    private struct Candidate {
        let name: String
        let aliases: [String]
        let restaurantID: String?
        let category: String?
    }

    private struct Match {
        let range: Range<Int>
        let candidate: Candidate
        let score: Double
    }

    static func interpret(_ rawText: String, store: RestaurantDatasetStore? = RestaurantDatasetStore.bundled()) -> FoodQueryIntent {
        let cleaned = lexicalCleanup(rawText)
        let words = cleaned.split(separator: " ").map(String.init)
        guard !words.isEmpty else {
            return FoodQueryIntent(rawText: rawText, interpretedText: rawText, items: [], restaurantID: nil, confidence: 0)
        }

        let candidates = menuCandidates(from: store)
        let matches = nonOverlappingMatches(in: words, candidates: candidates)
        let matchedRestaurantIDs = Set(matches.compactMap { $0.candidate.restaurantID })
        let restaurantID = matchedRestaurantIDs.count == 1 ? matchedRestaurantIDs.first : nil

        var rendered: [String] = []
        var items: [FoodQueryIntent.Item] = []
        var cursor = 0
        for match in matches.sorted(by: { $0.range.lowerBound < $1.range.lowerBound }) {
            if cursor < match.range.lowerBound {
                rendered.append(words[cursor..<match.range.lowerBound].joined(separator: " "))
            }
            let rawSpan = words[match.range].joined(separator: " ")
            rendered.append(match.candidate.name)
            items.append(.init(
                rawSpan: rawSpan,
                interpretedName: match.candidate.name,
                restaurantID: match.candidate.restaurantID,
                category: match.candidate.category,
                confidence: match.score
            ))
            cursor = match.range.upperBound
        }
        if cursor < words.count { rendered.append(words[cursor...].joined(separator: " ")) }

        let interpreted = rendered
            .filter { !$0.isEmpty }
            .joined(separator: " and ")
            .replacingOccurrences(of: " and no ", with: " no ")
            .replacingOccurrences(of: " and without ", with: " without ")

        let confidence = items.map(\.confidence).min() ?? (cleaned == RestaurantQueryNormalizer.normalize(rawText) ? 1 : 0.75)
        return FoodQueryIntent(
            rawText: rawText,
            interpretedText: interpreted.isEmpty ? cleaned : interpreted,
            items: items,
            restaurantID: restaurantID,
            confidence: confidence
        )
    }

    static func applyingPlausibilityGuard(
        to analysis: GeminiService.FoodAnalysis,
        intent: FoodQueryIntent
    ) -> GeminiService.FoodAnalysis {
        let expectsSubstantialFood = intent.items.contains { item in
            guard let category = item.category else { return false }
            return ["burger", "meal", "chicken", "smoothie"].contains(category)
        }
        guard expectsSubstantialFood, analysis.calories <= 20 else { return analysis }
        var guarded = analysis
        guarded.nutritionConfidence = "Low"
        let warning = "Interpretation and nutrition result conflict; check this estimate"
        guarded.nutritionSourceDetail = [analysis.nutritionSourceDetail, warning]
            .compactMap { $0 }
            .joined(separator: " · ")
        return guarded
    }

    private static func lexicalCleanup(_ value: String) -> String {
        var words = RestaurantQueryNormalizer.normalize(value).split(separator: " ").map(String.init)
        let replacements = [
            "nuggies": "nuggets", "avo": "avocado", "brocoli": "broccoli",
            "chiken": "chicken", "coffy": "coffee", "yog": "yoghurt",
            "latay": "latte", "toasty": "toastie", "maccas": "maccas"
        ]
        for index in words.indices {
            if let replacement = replacements[words[index]] { words[index] = replacement }
            if words[index] == "too", index + 1 < words.count, isCountableFood(words[index + 1]) { words[index] = "2" }
            if words[index] == "six", index + 1 < words.count, isCountableFood(words[index + 1]) { words[index] = "6" }
            if words[index] == "for", index + 1 < words.count, isCountableFood(words[index + 1]) { words[index] = "4" }
        }
        return words.joined(separator: " ")
    }

    private static func isCountableFood(_ word: String) -> Bool {
        ["egg", "eggs", "wing", "wings", "nugget", "nuggets", "nuggies", "slice", "slices"].contains(word)
    }

    private static func menuCandidates(from store: RestaurantDatasetStore?) -> [Candidate] {
        guard let dataset = store?.dataset else { return [] }
        return dataset.menuItems.map { item in
            Candidate(
                name: item.name,
                aliases: item.aliases + [item.name],
                restaurantID: item.provenance?.restaurantID,
                category: item.category
            )
        }
    }

    private static func nonOverlappingMatches(in words: [String], candidates: [Candidate]) -> [Match] {
        var possible: [Match] = []
        for start in words.indices {
            for length in 1...min(5, words.count - start) {
                let range = start..<(start + length)
                let phrase = words[range].joined(separator: " ")
                for candidate in candidates {
                    guard let score = candidate.aliases.map({ similarity(phrase, $0) }).max(),
                          score >= threshold(for: phrase, tokenCount: length)
                    else { continue }
                    possible.append(Match(range: range, candidate: candidate, score: score))
                }
            }
        }

        let unambiguous = Dictionary(grouping: possible, by: \.range).compactMap { _, matches -> Match? in
            let ordered = matches.sorted { $0.score > $1.score }
            guard let best = ordered.first else { return nil }
            if let second = ordered.dropFirst().first, best.score < 0.9, best.score - second.score < 0.08 {
                return nil
            }
            return best
        }
        let ranked = unambiguous.sorted {
            if $0.score != $1.score { return $0.score > $1.score }
            return $0.range.count > $1.range.count
        }
        var occupied = Set<Int>()
        var selected: [Match] = []
        for match in ranked {
            guard match.range.allSatisfy({ !occupied.contains($0) }) else { continue }
            // A one-token generic category is not enough to choose a branded item.
            if match.range.count == 1, ["burger", "chicken", "coke", "wonder"].contains(words[match.range.lowerBound]) { continue }
            selected.append(match)
            occupied.formUnion(match.range)
        }
        return selected
    }

    private static func threshold(for phrase: String, tokenCount: Int) -> Double {
        let compactCount = compact(phrase).count
        if tokenCount == 1 { return compactCount <= 4 ? 0.84 : 0.76 }
        return compactCount < 8 ? 0.74 : 0.58
    }

    private static func similarity(_ lhs: String, _ rhs: String) -> Double {
        let left = compact(lhs)
        let right = compact(rhs)
        guard !left.isEmpty, !right.isEmpty else { return 0 }
        if left == right { return 1 }
        let distance = levenshtein(left, right)
        return 1 - (Double(distance) / Double(max(left.count, right.count)))
    }

    private static func compact(_ value: String) -> String {
        RestaurantQueryNormalizer.normalize(value).replacingOccurrences(of: " ", with: "")
    }

    private static func levenshtein(_ lhs: String, _ rhs: String) -> Int {
        let a = Array(lhs), b = Array(rhs)
        var previous = Array(0...b.count)
        for (i, left) in a.enumerated() {
            var current = [i + 1]
            for (j, right) in b.enumerated() {
                current.append(min(current[j] + 1, previous[j + 1] + 1, previous[j] + (left == right ? 0 : 1)))
            }
            previous = current
        }
        return previous[b.count]
    }
}
