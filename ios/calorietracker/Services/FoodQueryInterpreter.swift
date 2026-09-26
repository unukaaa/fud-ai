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
    let unresolvedTerms: [String]

    var hasMultipleItems: Bool { items.count > 1 }
}

/// Converts noisy typed or dictated food language into conservative canonical
/// food terms. Nutrition remains the responsibility of the existing resolvers.
enum FoodQueryInterpreter {
    private static let bundledStore = RestaurantDatasetStore.bundled()
    private static let bundledCandidates = menuCandidates(from: bundledStore)
    private static let bundledContextTerms = recognizedContextTerms(from: bundledStore)
    private struct Candidate {
        let name: String
        let compactAliases: [String]
        let restaurantID: String?
        let category: String?
    }

    private struct Match {
        let range: Range<Int>
        let candidate: Candidate
        let score: Double
    }

    static func interpret(_ rawText: String, store: RestaurantDatasetStore? = nil) -> FoodQueryIntent {
        let cleaned = lexicalCleanup(rawText)
        let words = cleaned.split(separator: " ").map(String.init)
        guard !words.isEmpty else {
            return FoodQueryIntent(rawText: rawText, interpretedText: rawText, items: [], restaurantID: nil, confidence: 0, unresolvedTerms: [])
        }

        let candidates = store == nil ? bundledCandidates : menuCandidates(from: store)
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
            .replacingOccurrences(of: #"\b([0-9]+) and "#, with: "$1 ", options: .regularExpression)

        let occupied = Set(matches.flatMap { $0.range })
        let contextTerms = store == nil ? bundledContextTerms : recognizedContextTerms(from: store)
        let unresolvedTerms = words.indices.compactMap { index -> String? in
            guard !occupied.contains(index) else { return nil }
            let word = words[index]
            guard !isStructuralTerm(word), !contextTerms.contains(word) else { return nil }
            return word
        }

        let confidence = items.map(\.confidence).min() ?? (cleaned == RestaurantQueryNormalizer.normalize(rawText) ? 1 : 0.75)
        return FoodQueryIntent(
            rawText: rawText,
            interpretedText: interpreted.isEmpty ? cleaned : interpreted,
            items: items,
            restaurantID: restaurantID,
            confidence: confidence,
            unresolvedTerms: unresolvedTerms
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
            "latay": "latte", "toasty": "toastie", "nana": "banana",
            "aple": "apple", "stake": "steak", "veg": "vegetables",
            "ry": "rye"
        ]
        for index in words.indices {
            if let replacement = replacements[words[index]] { words[index] = replacement }
            if words[index] == "one", index + 1 < words.count, isCountableFood(words[index + 1]) { words[index] = "1" }
            if words[index] == "two", index + 1 < words.count, isCountableFood(words[index + 1]) { words[index] = "2" }
            if words[index] == "too", index + 1 < words.count, isCountableFood(words[index + 1]) { words[index] = "2" }
            if words[index] == "four", index + 1 < words.count, isCountableFood(words[index + 1]) { words[index] = "4" }
            if words[index] == "six", index + 1 < words.count, isCountableFood(words[index + 1]) { words[index] = "6" }
            if words[index] == "for", hasFollowingCountableFood(words, after: index) { words[index] = "4" }
            if words[index] == "ten", index + 1 < words.count, isCountableFood(words[index + 1]) { words[index] = "10" }
        }
        return words.joined(separator: " ")
    }

    private static func isCountableFood(_ word: String) -> Bool {
        ["egg", "eggs", "wing", "wings", "nugget", "nuggets", "nuggies", "slice", "slices"].contains(word)
    }

    private static func hasFollowingCountableFood(_ words: [String], after index: Int) -> Bool {
        let next = index + 1
        if next < words.count, isCountableFood(words[next]) { return true }
        let afterNext = index + 2
        return afterNext < words.count && isCountableFood(words[afterNext])
    }

    static func isClearlyUnmatchedFood(_ word: String) -> Bool {
        ["apple", "banana", "potato", "salad", "rice", "broccoli", "yoghurt", "avocado", "coffee"].contains(word)
    }

    private static func isStructuralTerm(_ word: String) -> Bool {
        if Int(word) != nil { return true }
        return [
            "a", "an", "and", "ate", "for", "had", "i", "just", "lunch", "of", "on", "the", "with",
            "large", "medium", "original", "regular", "small", "only", "no", "without", "meal", "box",
            "piece", "pieces", "serving", "servings", "slice", "slices"
        ].contains(word)
    }

    private static func recognizedContextTerms(from store: RestaurantDatasetStore?) -> Set<String> {
        guard let dataset = store?.dataset else { return [] }
        var terms = Set<String>()
        func add(_ value: String) {
            let normalized = RestaurantQueryNormalizer.normalize(value)
            for term in normalized.split(separator: " ") {
                terms.insert(String(term))
            }
        }
        for restaurant in dataset.restaurants {
            add(restaurant.name)
            for alias in restaurant.aliases { add(alias) }
        }
        for item in dataset.menuItems {
            for modifier in item.modifiers {
                add(modifier.name)
                for alias in modifier.aliases { add(alias) }
            }
            for variant in item.variants {
                add(variant.name)
                for alias in variant.aliases { add(alias) }
            }
        }
        return terms
    }

    private static func menuCandidates(from store: RestaurantDatasetStore?) -> [Candidate] {
        guard let dataset = store?.dataset else { return [] }
        return dataset.menuItems.map { item in
            var compactAliases: [String] = []
            for alias in item.aliases + [item.name] {
                compactAliases.append(compact(alias))
            }
            return Candidate(
                name: item.name,
                compactAliases: compactAliases,
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
                let compactPhrase = compact(phrase)
                for candidate in candidates {
                    guard let score = candidate.compactAliases.map({ similarity(compactPhrase, $0) }).max(),
                          score >= threshold(for: phrase, tokenCount: length)
                    else { continue }
                    possible.append(Match(range: range, candidate: candidate, score: score))
                }
            }
        }

        let unambiguous = Dictionary(grouping: possible, by: \.range).compactMap { _, matches -> Match? in
            let ordered = matches.sorted {
                if $0.score != $1.score { return $0.score > $1.score }
                if $0.range.count != $1.range.count { return $0.range.count > $1.range.count }
                return $0.candidate.name < $1.candidate.name
            }
            guard let best = ordered.first else { return nil }
            if let second = ordered.dropFirst().first, best.score < 0.9, best.score - second.score < 0.08 {
                return nil
            }
            return best
        }
        let ranked = unambiguous.sorted {
            if $0.score != $1.score { return $0.score > $1.score }
            if $0.range.count != $1.range.count { return $0.range.count > $1.range.count }
            if $0.range.lowerBound != $1.range.lowerBound { return $0.range.lowerBound < $1.range.lowerBound }
            return $0.candidate.name < $1.candidate.name
        }
        var occupied = Set<Int>()
        var selected: [Match] = []
        for match in ranked {
            guard match.range.allSatisfy({ !occupied.contains($0) }) else { continue }
            // A one-token generic category is not enough to choose a branded item.
            if match.range.count == 1, ["burger", "chicken", "coke", "wonder", "chips"].contains(words[match.range.lowerBound]) { continue }
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
        guard !lhs.isEmpty, !rhs.isEmpty else { return 0 }
        if lhs == rhs { return 1 }
        let distance = levenshtein(lhs, rhs)
        return 1 - (Double(distance) / Double(max(lhs.count, rhs.count)))
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
