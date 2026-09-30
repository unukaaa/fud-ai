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
    /// Source identity and context remain attached to the containing Survey ID.
    let measureID: Int?
    let descriptors: [String?]?
    let volume: Double?

    nonisolated init(
        name: String, quantity: Double, grams: Double, measureID: Int? = nil,
        descriptors: [String?]? = nil, volume: Double? = nil
    ) {
        self.name = name
        self.quantity = quantity
        self.grams = grams
        self.measureID = measureID
        self.descriptors = descriptors
        self.volume = volume
    }

    private enum CodingKeys: String, CodingKey {
        case name = "n", quantity = "q", grams = "g"
        case measureID = "mid", descriptors = "d", volume = "v"
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

/// Presentation metadata only. The original measure index remains the selection key.
struct AUSNUTPresentedMeasure: Identifiable, Equatable {
    let index: Int
    let measureID: Int?
    let title: String
    let sourceQuantity: Double
    let sourceGrams: Double
    let sourceVolume: Double?

    var id: Int { index }
    var gramsPerUnit: Double { sourceGrams / sourceQuantity }
    var portion: AUSNUTPortion { .measure(index: index, quantity: 1) }
}

/// Keeps the complete source set while exposing a small, diverse first group.
struct AUSNUTPortionPresentation {
    let primary: [AUSNUTPresentedMeasure]
    let more: [AUSNUTPresentedMeasure]

    /// Four short choices fit the existing mobile sheet without treating source order as priority.
    static let primaryLimit = 4

    static func make(for food: AUSNUTFoodIdentity) -> Self {
        let valid = food.measures.enumerated().filter { _, measure in
            !measure.name.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty
                && measure.quantity.isFinite && measure.quantity > 0
                && measure.grams.isFinite && measure.grams > 0
        }
        let baseTitles = valid.map { _, measure in contextualTitle(for: measure, foodName: food.name) }
        let baseCounts = Dictionary(grouping: baseTitles.map { $0.lowercased() }, by: { $0 })
            .mapValues(\.count)
        var options = valid.enumerated().map { position, indexed -> AUSNUTPresentedMeasure in
            let (index, measure) = indexed
            var title = baseTitles[position]
            if baseCounts[title.lowercased(), default: 0] > 1 {
                let volume = (measure.volume ?? 0) / measure.quantity
                let amount = volume > 0 ? "\(formatted(volume)) mL" : "\(formatted(measure.grams / measure.quantity)) g"
                title += " · \(amount)"
            }
            return AUSNUTPresentedMeasure(
                index: index, measureID: measure.measureID, title: title,
                sourceQuantity: measure.quantity, sourceGrams: measure.grams,
                sourceVolume: measure.volume
            )
        }
        // If distinct source measures still have the same visible size, use the
        // upstream Measure ID, not a guessed product or serving distinction.
        let titleCounts = Dictionary(grouping: options.map { $0.title.lowercased() }, by: { $0 })
            .mapValues(\.count)
        options = options.map { option in
            guard titleCounts[option.title.lowercased(), default: 0] > 1 else { return option }
            let suffix = option.measureID.map { "AUSNUT measure \($0)" } ?? "option \(option.index + 1)"
            return AUSNUTPresentedMeasure(
                index: option.index, measureID: option.measureID,
                title: "\(option.title) · \(suffix)", sourceQuantity: option.sourceQuantity,
                sourceGrams: option.sourceGrams, sourceVolume: option.sourceVolume
            )
        }

        let ranked = options.sorted { left, right in
            let leftScore = score(food.measures[left.index], foodName: food.name)
            let rightScore = score(food.measures[right.index], foodName: food.name)
            return leftScore == rightScore ? left.index < right.index : leftScore > rightScore
        }
        var primary: [AUSNUTPresentedMeasure] = []
        var forms: Set<String> = []
        for option in ranked {
            let form = firstDescriptor(food.measures[option.index])
            guard forms.insert(form).inserted else { continue }
            primary.append(option)
            if primary.count == primaryLimit { break }
        }
        if primary.count < primaryLimit {
            let chosen = Set(primary.map(\.index))
            primary += ranked.filter { !chosen.contains($0.index) }.prefix(primaryLimit - primary.count)
        }
        let chosen = Set(primary.map(\.index))
        return Self(primary: primary, more: ranked.filter { !chosen.contains($0.index) })
    }

    private static let commonForms: Set<String> = [
        "bar", "block", "bottle", "bowl", "can", "container", "cup", "glass",
        "handful", "mug", "packet", "piece", "roll", "row", "slice", "square",
        "tablespoon", "teaspoon"
    ]

    private static func firstDescriptor(_ measure: AUSNUTFoodMeasure) -> String {
        let first = measure.descriptors?.compactMap { $0 }.first
            ?? measure.name.split(separator: " ").first.map(String.init) ?? ""
        return first.lowercased()
    }

    private static func contextualTitle(for measure: AUSNUTFoodMeasure, foodName: String) -> String {
        let form = firstDescriptor(measure)
        let foodWords = Set(foodName.lowercased()
            .replacingOccurrences(of: "[^a-z0-9]+", with: " ", options: .regularExpression)
            .split(separator: " ").map(String.init))
        let formWords = form.replacingOccurrences(of: "[^a-z0-9]+", with: " ", options: .regularExpression)
            .split(separator: " ").map(String.init)
        if commonForms.contains(form) || formWords.allSatisfy(foodWords.contains) {
            return measure.name
        }
        return "\(foodName) · \(measure.name)"
    }

    private static func score(_ measure: AUSNUTFoodMeasure, foodName: String) -> Int {
        let parts = measure.descriptors?.compactMap { $0?.lowercased() }
            ?? measure.name.split(separator: " ").map { $0.lowercased() }
        let form = firstDescriptor(measure)
        let qualifiers = parts.dropFirst()
        var result = commonForms.contains(form) ? 8 : 0
        let foodWords = Set(foodName.lowercased()
            .replacingOccurrences(of: "[^a-z0-9]+", with: " ", options: .regularExpression)
            .split(separator: " ").map(String.init))
        let formWords = form.replacingOccurrences(of: "[^a-z0-9]+", with: " ", options: .regularExpression)
            .split(separator: " ").map(String.init)
        if !formWords.isEmpty && formWords.allSatisfy(foodWords.contains) { result += 4 }
        if qualifiers.contains("regular") || qualifiers.contains("medium") { result += 6 }
        if parts.count == 1 { result += 2 }
        result -= max(0, parts.count - 1)
        if measure.descriptors?.last.flatMap({ $0 }) != nil { result -= 2 }
        if commonForms.contains(form), (measure.volume ?? 0) > 0 { result += 1 }
        if measure.grams / measure.quantity < 1 || measure.grams / measure.quantity > 1_000 { result -= 1 }
        return result
    }

    private static func formatted(_ value: Double) -> String {
        value.formatted(.number.precision(.fractionLength(0...6)))
    }
}
