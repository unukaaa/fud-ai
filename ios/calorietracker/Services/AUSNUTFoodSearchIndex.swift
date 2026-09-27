import Foundation

/// Identity and portion metadata only; nutrient values remain in AustralianNutritionService.
struct AUSNUTFoodIdentity: Equatable, Sendable {
    let id: String
    let name: String
    let measures: [AUSNUTFoodMeasure]

    nonisolated init(id: String, name: String, measures: [AUSNUTFoodMeasure]) {
        self.id = id
        self.name = name
        self.measures = measures
    }

    var source: String { "AUSNUT 2023 · Food Standards Australia New Zealand" }
}

struct AUSNUTFoodMeasure: Decodable, Equatable, Sendable {
    let name: String
    let quantity: Double
    let grams: Double

    private enum CodingKeys: String, CodingKey {
        case name = "n", quantity = "q", grams = "g"
    }
}

struct AUSNUTFoodSuggestion: Equatable, Identifiable, Sendable {
    enum MatchReason: Int, Equatable, Sendable {
        case exact = 0
        case fullNamePrefix = 1
        case orderedTokenPrefix = 2
        case allTokens = 3
    }

    let foodID: String
    let title: String
    let matchReason: MatchReason

    var id: String { "ausnut:\(foodID)" }
    var selection: AUSNUTFoodSelection { AUSNUTFoodSelection(foodID: foodID) }
}

struct AUSNUTFoodSelection: Equatable, Sendable {
    let foodID: String
}

/// An explicit amount, never an inferred default serving.
enum AUSNUTPortion: Equatable, Sendable {
    case grams(Double)
    case measure(index: Int, quantity: Double)
}

struct AUSNUTFoodSearchIndex: Sendable {
    private struct Entry: Sendable {
        let identity: AUSNUTFoodIdentity
        let normalizedName: String
        let tokens: [String]
        let order: Int
    }

    private let entries: [Entry]

    nonisolated init(identities: [AUSNUTFoodIdentity]) {
        entries = identities.enumerated().map { order, identity in
            let normalizedName = Self.normalize(identity.name)
            return Entry(identity: identity, normalizedName: normalizedName,
                         tokens: normalizedName.split(separator: " ").map(String.init), order: order)
        }
    }

    private static let bundledIndex: AUSNUTFoodSearchIndex? = {
        AustralianNutritionService.searchableIdentities.map(AUSNUTFoodSearchIndex.init(identities:))
    }()

    static func bundled() -> AUSNUTFoodSearchIndex? { bundledIndex }

    func search(_ text: String, limit: Int = 5) -> [AUSNUTFoodSuggestion] {
        let query = Self.normalize(text)
        guard !query.isEmpty, limit > 0 else { return [] }
        let queryTokens = query.split(separator: " ").map(String.init)

        let ranked = entries.compactMap { entry -> (Entry, AUSNUTFoodSuggestion.MatchReason)? in
            guard let reason = Self.match(query: query, queryTokens: queryTokens, entry: entry) else { return nil }
            return (entry, reason)
        }
        .sorted { left, right in
            if left.1.rawValue != right.1.rawValue { return left.1.rawValue < right.1.rawValue }
            return left.0.order < right.0.order
        }
        let selected: [(Entry, AUSNUTFoodSuggestion.MatchReason)]
        if queryTokens.count == 1 {
            // Broad food names have many near-identical database forms. Keep
            // distinct preparations visible without changing ranking tiers.
            var familyCounts: [String: Int] = [:]
            var diverse: [(Entry, AUSNUTFoodSuggestion.MatchReason)] = []
            for candidate in ranked {
                let family = candidate.0.tokens.prefix(2).joined(separator: " ")
                guard familyCounts[family, default: 0] < 2 else { continue }
                familyCounts[family, default: 0] += 1
                diverse.append(candidate)
                if diverse.count == limit { break }
            }
            if diverse.count < limit {
                let chosen = Set(diverse.map { $0.0.identity.id })
                diverse += ranked.filter { !chosen.contains($0.0.identity.id) }.prefix(limit - diverse.count)
            }
            selected = diverse
        } else {
            selected = Array(ranked.prefix(limit))
        }
        return selected.map { candidate in
            AUSNUTFoodSuggestion(foodID: candidate.0.identity.id, title: candidate.0.identity.name,
                                 matchReason: candidate.1)
        }
    }

    private static func match(
        query: String, queryTokens: [String], entry: Entry
    ) -> AUSNUTFoodSuggestion.MatchReason? {
        if entry.normalizedName == query { return .exact }
        if entry.normalizedName.hasPrefix(query) { return .fullNamePrefix }
        if queryTokens.count > 1, queryTokens.count <= entry.tokens.count,
           zip(queryTokens, entry.tokens).allSatisfy({ pair in pair.1.hasPrefix(pair.0) }) {
            return .orderedTokenPrefix
        }
        // Single-word substring results are too broad (e.g. "rice" inside a recipe).
        guard queryTokens.count > 1,
              queryTokens.allSatisfy({ entry.tokens.contains($0) }) else { return nil }
        return .allTokens
    }

    nonisolated private static func normalize(_ value: String) -> String {
        let folded = value.folding(options: [.diacriticInsensitive, .caseInsensitive], locale: Locale(identifier: "en_AU"))
            .lowercased()
            .replacingOccurrences(of: "[^a-z0-9]+", with: " ", options: .regularExpression)
        return folded.split(separator: " ").joined(separator: " ")
    }
}

/// A discovery-only boundary. Each provider keeps its own index and resolver.
enum UnifiedFoodSuggestion: Identifiable, Equatable {
    case restaurant(SearchFoodSuggestion)
    case ausnut(AUSNUTFoodSuggestion)

    var id: String {
        switch self {
        case .restaurant(let suggestion): "restaurant:\(suggestion.id)"
        case .ausnut(let suggestion): suggestion.id
        }
    }
}

struct UnifiedFoodSearchIndex {
    let restaurants: RestaurantFoodSearchIndex?
    let ausnut: AUSNUTFoodSearchIndex?

    func search(_ text: String, limit: Int = 5) -> [UnifiedFoodSuggestion] {
        guard limit > 0 else { return [] }
        let restaurantResults = restaurants?.search(text, limit: limit) ?? []
        if restaurantResults.first?.kind == .brand {
            return restaurantResults.prefix(limit).map(UnifiedFoodSuggestion.restaurant)
        }
        var results = restaurantResults.map(UnifiedFoodSuggestion.restaurant)
        let remaining = limit - results.count
        guard remaining > 0 else { return results }

        // Only whole-query identity matches enter discovery. A component found
        // somewhere inside a composed meal is not the identity of that meal.
        let ordinaryResults = ausnut?.search(text, limit: remaining).filter {
            $0.matchReason != .allTokens
        } ?? []
        results += ordinaryResults.map(UnifiedFoodSuggestion.ausnut)
        return results
    }
}

struct AUSNUTPortionChoice: Identifiable, Equatable {
    let index: Int
    let title: String
    let grams: Double

    var id: Int { index }

    static func choices(for identity: AUSNUTFoodIdentity) -> [Self] {
        let valid = identity.measures.enumerated().filter { _, measure in
            !measure.name.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty
                && measure.quantity.isFinite && measure.quantity > 0
                && measure.grams.isFinite && measure.grams > 0
        }
        var seen: Set<String> = []
        let unique = valid.filter { _, measure in
            let key = "\(measure.name.lowercased())|\(measure.quantity)|\(measure.grams)"
            return seen.insert(key).inserted
        }
        let counts = Dictionary(grouping: unique, by: { $0.element.name.lowercased() })
            .mapValues(\.count)
        return unique.map { index, measure in
            let grams = measure.grams / measure.quantity
            let weight = grams.formatted(.number.precision(.fractionLength(0...1)))
            let duplicate = counts[measure.name.lowercased(), default: 0] > 1
            return Self(index: index,
                        title: duplicate ? "\(measure.name) · \(weight) g each" : measure.name,
                        grams: grams)
        }
    }
}
