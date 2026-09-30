import Foundation

struct FoodQueryIntent: Equatable, Sendable {
    struct Item: Equatable, Sendable {
        let rawSpan: String
        let interpretedName: String
        let restaurantID: String?
        let category: String?
        let confidence: Double
        let wordRange: Range<Int>
    }

    let rawText: String
    let interpretedText: String
    let items: [Item]
    let restaurantID: String?
    let confidence: Double
    let unresolvedTerms: [String]

    var hasMultipleItems: Bool { items.count > 1 }
}

enum FoodIntentRouteState: String, Equatable, Sendable {
    case resolvedFood
    case brandDiscovery
    case unverifiedProductEstimate
    case ordinaryFoodFallback
    case needsClarification
}

struct FoodIntentRoute: Equatable, Sendable {
    let state: FoodIntentRouteState
    let foodIdentity: String
    let brandID: String?
    let locationContext: String?
    let matchedMenuItems: [String]
}

/// Routing evidence, not nutrition calculation. A future search surface can
/// supply product identity evidence without teaching this layer brand names.
enum FoodIntentRouter {
    static func route(_ query: String, analysis: GeminiService.FoodAnalysis? = nil,
                      productIdentityIsKnown: Bool = false,
                      store: RestaurantDatasetStore? = nil) -> FoodIntentRoute {
        let dataset = store ?? RestaurantDatasetStore.bundled()
        let normalized = FoodQueryInterpreter.lexicalCleanup(query)
        let identity = foodIdentity(in: normalized)
        let location = identity == normalized ? nil : String(normalized.dropFirst(identity.count + " from ".count))
        var brandID: String?
        var brandAlias: String?
        if let dataset {
            for restaurant in dataset.dataset.restaurants {
                for alias in restaurant.aliases + [restaurant.name] {
                    let candidate = RestaurantQueryNormalizer.normalize(alias)
                    guard !candidate.isEmpty,
                          (" " + normalized + " ").contains(" " + candidate + " "),
                          candidate.count > (brandAlias?.count ?? 0) else { continue }
                    brandID = restaurant.id
                    brandAlias = candidate
                }
            }
        }
        let intent = FoodQueryInterpreter.interpret(identity, store: dataset)
        let items = intent.items.map(\.interpretedName)
        let state: FoodIntentRouteState
        if identity.isEmpty {
            state = .needsClarification
        } else if identity == brandAlias {
            state = .brandDiscovery
        } else if !items.isEmpty && intent.unresolvedTerms.isEmpty {
            state = .resolvedFood
        } else if let analysis, analysis.foodIdentityConfirmed == false {
            state = .needsClarification
        } else if let analysis {
            let requested = identityWords(identity)
            let estimated = Set(identityWords(analysis.name))
            if requested.isEmpty || !requested.allSatisfy(estimated.contains) {
                state = .needsClarification
            } else if brandID != nil || productIdentityIsKnown {
                state = .unverifiedProductEstimate
            } else {
                state = .ordinaryFoodFallback
            }
        } else {
            state = .ordinaryFoodFallback
        }
        return FoodIntentRoute(state: state, foodIdentity: identity, brandID: brandID,
                               locationContext: location, matchedMenuItems: items)
    }

    static func foodIdentity(in query: String) -> String {
        let normalized = FoodQueryInterpreter.lexicalCleanup(query)
        guard let range = normalized.range(of: " from "),
              !normalized[range.upperBound...].contains(" and "),
              !normalized[range.upperBound...].contains(" plus ")
        else { return normalized }
        return String(normalized[..<range.lowerBound])
    }

    private static func identityWords(_ value: String) -> [String] {
        FoodQueryInterpreter.lexicalCleanup(value).split(separator: " ").map(String.init)
            .filter { !["a", "an", "the", "of", "with", "and"].contains($0) && Int($0) == nil }
    }
}

enum FoodResolutionState: String, Equatable, Sendable {
    case verifiedRestaurant
    case partiallyVerifiedRestaurant
    case ausnut
    case structuredEstimate
    case aiEstimate
    case unresolved
}

struct FoodResolutionComponent: Equatable, Sendable {
    let query: String
    let name: String
    let state: FoodResolutionState
    let quantity: Double
    let calories: Int?
    let protein: Double?
    let carbs: Double?
    let fat: Double?
    let sourceDetail: String?
    let sourceItemID: String?

    var isResolved: Bool { state != .unresolved && calories != nil }
}

struct FoodQueryResolution {
    let analysis: GeminiService.FoodAnalysis?
    let restaurantMatch: RestaurantMatch?
    let components: [FoodResolutionComponent]
    let candidateAnalysis: GeminiService.FoodAnalysis?
    let route: FoodIntentRoute?
    let restaurantSelection: RestaurantFoodSelection?
    let ausnutSelection: AUSNUTFoodSelection?

    init(analysis: GeminiService.FoodAnalysis?, restaurantMatch: RestaurantMatch?,
         components: [FoodResolutionComponent], candidateAnalysis: GeminiService.FoodAnalysis? = nil,
         route: FoodIntentRoute? = nil, restaurantSelection: RestaurantFoodSelection? = nil,
         ausnutSelection: AUSNUTFoodSelection? = nil) {
        self.analysis = analysis
        self.restaurantMatch = restaurantMatch
        self.components = components
        self.candidateAnalysis = candidateAnalysis
        self.route = route
        self.restaurantSelection = restaurantSelection
        self.ausnutSelection = ausnutSelection
    }

    var unresolvedComponents: [FoodResolutionComponent] {
        components.filter { !$0.isResolved }
    }

    var isComplete: Bool { !components.isEmpty && unresolvedComponents.isEmpty }

    #if DEBUG
    var debugAttempts: [FoodResolutionDiagnostics.Attempt] = []

    func debugDiagnostics(for originalQuery: String) -> FoodResolutionDiagnostics {
        let intent = FoodQueryInterpreter.interpret(originalQuery)
        let currentRoute = route ?? FoodIntentRouter.route(originalQuery, analysis: analysis ?? candidateAnalysis)
        return FoodResolutionDiagnostics(
            originalQuery: originalQuery,
            interpretedQuery: intent.interpretedText,
            routeState: currentRoute.state,
            foodIdentity: currentRoute.foodIdentity,
            brandID: currentRoute.brandID,
            locationContext: currentRoute.locationContext,
            detectedComponents: intent.items.map(\.interpretedName),
            attempts: debugAttempts,
            components: components.map { component in
                let attempts = debugAttempts.filter { $0.query == component.query }
                return FoodResolutionDiagnostics.Component(
                    query: component.query,
                    normalizedQuery: FoodQueryInterpreter.lexicalCleanup(component.query),
                    name: component.name,
                    quantity: component.quantity,
                    calories: component.calories,
                    restaurantContext: FoodQueryInterpreter.interpret(component.query).restaurantID ?? currentRoute.brandID,
                    deterministicCandidates: attempts.compactMap(\.candidateItemID) + [component.sourceItemID].compactMap { $0 },
                    attemptedResolvers: attempts.map(\.resolver),
                    selectedResolver: component.state == .unresolved ? nil :
                        (component.state == .ausnut ? "AustralianNutritionService" :
                            (component.sourceItemID != nil ? "RestaurantNutritionProvider" : component.state.rawValue)),
                    modifiers: attempts.flatMap(\.modifiers),
                    state: component.state,
                    source: component.sourceDetail,
                    confidence: (component.state == .verifiedRestaurant || component.state == .partiallyVerifiedRestaurant)
                        ? FoodQueryInterpreter.interpret(component.query).confidence : nil,
                    reason: component.state == .unresolved
                        ? attempts.compactMap(\.reason).last
                            ?? (candidateAnalysis == nil ? "No usable resolver result" : "Estimated identity did not account for this food") : nil
                )
            },
            complete: isComplete
        )
    }
    #endif
}

#if DEBUG
/// On-demand, in-memory developer trace. Never persisted or automatically logged.
struct FoodResolutionDiagnostics {
    struct Attempt {
        let query: String
        let resolver: String
        let outcome: String
        let candidateItemID: String?
        let source: String?
        let modifiers: [String]
        let reason: String?
    }

    struct Component {
        let query: String
        let normalizedQuery: String
        let name: String
        let quantity: Double
        let calories: Int?
        let restaurantContext: String?
        let deterministicCandidates: [String]
        let attemptedResolvers: [String]
        let selectedResolver: String?
        let modifiers: [String]
        let state: FoodResolutionState
        let source: String?
        let confidence: Double?
        let reason: String?
    }

    let originalQuery: String
    let interpretedQuery: String
    let routeState: FoodIntentRouteState
    let foodIdentity: String
    let brandID: String?
    let locationContext: String?
    let detectedComponents: [String]
    let attempts: [Attempt]
    let components: [Component]
    let complete: Bool

    var text: String {
        var lines = ["Food resolution: \(originalQuery)",
                     "Interpreted: \(interpretedQuery)",
                     "Route: \(routeState.rawValue) | food: \(foodIdentity) | brand: \(brandID ?? "none") | context: \(locationContext ?? "none")",
                     "Detected: \(detectedComponents.joined(separator: ", "))"]
        for attempt in attempts {
            lines.append("Attempt \(attempt.query): \(attempt.resolver) → \(attempt.outcome)" +
                         (attempt.candidateItemID.map { " [\($0)]" } ?? "") +
                         (attempt.reason.map { " (\($0))" } ?? ""))
        }
        for component in components {
            lines.append("Component \(component.query): \(component.name), qty \(component.quantity), calories \(component.calories.map(String.init) ?? "unknown"), \(component.state.rawValue), resolver \(component.selectedResolver ?? "none"), source \(component.source ?? "none")" +
                         (component.reason.map { ", reason \($0)" } ?? ""))
        }
        lines.append("Completeness: \(components.filter { $0.state != .unresolved }.count)/\(components.count) terminal — \(complete ? "PASS" : "FAIL")")
        return lines.joined(separator: "\n")
    }
}
#endif

/// Compiles to a no-op outside DEBUG; no trace is persisted or uploaded.
private final class FoodResolutionTraceRecorder {
    #if DEBUG
    var attempts: [FoodResolutionDiagnostics.Attempt] = []
    #endif

    func record(_ query: String, resolver: String, outcome: String,
                candidateItemID: String? = nil, source: String? = nil,
                modifiers: [String] = [], reason: String? = nil) {
        #if DEBUG
        attempts.append(.init(query: query, resolver: resolver, outcome: outcome,
                              candidateItemID: candidateItemID, source: source,
                              modifiers: modifiers, reason: reason))
        #endif
    }
}

struct IncompleteFoodQueryError: LocalizedError {
    let foods: [String]

    var errorDescription: String? {
        "Could not account for: \(foods.joined(separator: ", ")). Please clarify the food query and try again."
    }
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
                confidence: match.score,
                wordRange: match.range
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

    static func lexicalCleanup(_ value: String) -> String {
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
            if words[index] == "one", hasFollowingCountableFood(words, after: index) { words[index] = "1" }
            if words[index] == "two", hasFollowingCountableFood(words, after: index) { words[index] = "2" }
            if words[index] == "too", hasFollowingCountableFood(words, after: index) { words[index] = "2" }
            if words[index] == "four", hasFollowingCountableFood(words, after: index) { words[index] = "4" }
            if words[index] == "six", hasFollowingCountableFood(words, after: index) { words[index] = "6" }
            if words[index] == "for", hasFollowingCountableFood(words, after: index) { words[index] = "4" }
            if words[index] == "ten", hasFollowingCountableFood(words, after: index) { words[index] = "10" }
        }
        return words.joined(separator: " ").replacingOccurrences(of: "home made", with: "homemade")
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
            "piece", "pieces", "serving", "servings", "slice", "slices", "bit", "little"
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
            let firstContainsName = containsCompleteItemName($0, in: words)
            let secondContainsName = containsCompleteItemName($1, in: words)
            if firstContainsName != secondContainsName { return firstContainsName }
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

    private static func containsCompleteItemName(_ match: Match, in words: [String]) -> Bool {
        let name = RestaurantQueryNormalizer.normalize(match.candidate.name)
        let span = words[match.range].joined(separator: " ")
        return !name.isEmpty && (" " + span + " ").contains(" " + name + " ")
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

/// Coordinates existing nutrition sources while retaining an explicit outcome
/// for every part of a text query. A configured meal is one parent component;
/// its published child components stay inside the restaurant match.
enum FoodQueryResolutionService {
    typealias RestaurantResolver = (String) async -> RestaurantMatch?
    typealias Estimator = (String) async throws -> GeminiService.FoodAnalysis

    /// Search identity is authoritative. Without a valid selected amount the
    /// food remains unresolved; neither 100 g nor an AI estimate is assumed.
    static func resolve(
        selection: AUSNUTFoodSelection, portion: AUSNUTPortion?
    ) -> FoodQueryResolution {
        let identity = AustralianNutritionService.identity(forID: selection.foodID)
        let name = identity?.name ?? selection.foodID
        let analysis = portion.flatMap { AustralianNutritionService.analysis(for: selection, portion: $0) }
        let component = FoodResolutionComponent(
            query: name, name: name, state: analysis == nil ? .unresolved : .ausnut,
            quantity: analysis?.selectedServingQuantity ?? 1,
            calories: analysis?.calories, protein: analysis?.protein,
            carbs: analysis?.carbs, fat: analysis?.fat,
            sourceDetail: analysis?.nutritionSourceDetail,
            sourceItemID: identity == nil ? nil : selection.foodID
        )
        var tracked = analysis
        tracked?.foodResolutionComponents = [component]
        return FoodQueryResolution(
            analysis: tracked, restaurantMatch: nil, components: [component],
            route: FoodIntentRoute(
                state: analysis == nil ? .needsClarification : .resolvedFood,
                foodIdentity: name, brandID: nil, locationContext: nil, matchedMenuItems: []
            ), ausnutSelection: selection
        )
    }

    /// A search selection never falls back to text matching or AI if its IDs
    /// are stale. Carry the resolved source selection into each continuation.
    static func resolve(
        selection: RestaurantFoodSelection,
        clarificationAnswer: String? = nil,
        store: RestaurantDatasetStore? = nil
    ) async -> FoodQueryResolution {
        guard let match = await RestaurantNutritionAnalysisService.match(
            selection: selection, clarificationAnswer: clarificationAnswer, store: store
        ) else {
            let missing = unresolved(selection.itemID)
            return FoodQueryResolution(
                analysis: nil, restaurantMatch: nil, components: [missing],
                route: FoodIntentRoute(state: .needsClarification, foodIdentity: selection.itemID,
                                       brandID: selection.restaurantID, locationContext: nil,
                                       matchedMenuItems: []),
                restaurantSelection: selection
            )
        }
        let analysis = match.foodAnalysis
        let component = restaurantComponent(query: match.menuItem.name, match: match, analysis: analysis)
        // A meal choice can change the menu item itself. Carry that exact item
        // into subsequent answers, while preserving the existing parent
        // selection contract for a size/variant of the same item.
        let continuationSelection = match.menuItem.id == selection.itemID ? selection
            : RestaurantFoodSelection(
                restaurantID: match.restaurant.id,
                itemID: match.menuItem.id,
                variantID: match.selectedVariant?.id
            )
        var tracked = analysis
        tracked?.foodResolutionComponents = [component]
        return FoodQueryResolution(
            analysis: tracked, restaurantMatch: match, components: [component],
            route: FoodIntentRoute(state: .resolvedFood, foodIdentity: match.menuItem.name,
                                   brandID: match.restaurant.id, locationContext: nil,
                                   matchedMenuItems: [match.menuItem.name]),
            restaurantSelection: continuationSelection
        )
    }

    #if DEBUG
    /// Opt-in only: set FOOD_AI_RESOLUTION_TRACE=1 in the Xcode Run scheme.
    static func emitDebugTraceIfEnabled(_ resolution: FoodQueryResolution, query: String) {
        guard ProcessInfo.processInfo.environment["FOOD_AI_RESOLUTION_TRACE"] == "1" else { return }
        print(resolution.debugDiagnostics(for: query).text)
    }
    #endif

    static func resolve(
        description: String,
        restaurantResolver: @escaping RestaurantResolver = { await RestaurantNutritionAnalysisService.match(description: $0) },
        estimate: @escaping Estimator = { try await GeminiService.analyzeTextInput(description: $0) }
    ) async throws -> FoodQueryResolution {
        let parent = description.components(separatedBy: "Clarification:").first ?? description
        let initialRoute = FoodIntentRouter.route(parent)
        let trace = FoodResolutionTraceRecorder()
        if initialRoute.state == .brandDiscovery {
            trace.record(parent, resolver: "FoodIntentRouter", outcome: "brandDiscovery",
                         reason: "Brand-only intent; no nutrition resolver attempted")
            var result = FoodQueryResolution(analysis: nil, restaurantMatch: nil,
                                             components: [unresolved(parent)], route: initialRoute)
            #if DEBUG
            result.debugAttempts = trace.attempts
            #endif
            return result
        }
        let result = try await resolveFood(description: description,
                                           restaurantResolver: restaurantResolver, estimate: estimate, trace: trace)
        let route = FoodIntentRouter.route(parent, analysis: result.analysis ?? result.candidateAnalysis)
        var routed = FoodQueryResolution(analysis: result.analysis, restaurantMatch: result.restaurantMatch,
                                         components: result.components, candidateAnalysis: result.candidateAnalysis,
                                         route: route)
        #if DEBUG
        routed.debugAttempts = trace.attempts
        #endif
        return routed
    }

    private static func resolveFood(
        description: String,
        restaurantResolver: @escaping RestaurantResolver,
        estimate: @escaping Estimator,
        trace: FoodResolutionTraceRecorder
    ) async throws -> FoodQueryResolution {
        let parent = description.components(separatedBy: "Clarification:").first ?? description
        let intent = FoodQueryInterpreter.interpret(parent)
        let isClarification = description.contains("Clarification:")
        let isConfiguredParent = parent.range(of: #"\b(meal|box)\b"#, options: [.regularExpression, .caseInsensitive]) != nil
        let modifierWords: Set<String> = ["sauce", "mayo", "mayonnaise", "cheese", "pickle", "pickles", "onion", "onions", "skin"]
        let residualFoods = intent.unresolvedTerms.filter { !modifierWords.contains($0) }
        let hasResidualFood = !residualFoods.isEmpty
        let needsComponents = !isClarification && !isConfiguredParent
            && (intent.items.count > 1 || (!intent.items.isEmpty && hasResidualFood))

        if !needsComponents {
            let directMatch = await restaurantResolver(description)
            trace.record(parent, resolver: "RestaurantNutritionProvider",
                         outcome: directMatch == nil ? "noMatch" : "selected",
                         candidateItemID: directMatch?.menuItem.id,
                         source: directMatch?.foodAnalysis?.nutritionSourceDetail,
                         modifiers: directMatch?.matchedModifiers.map(\.name) ?? [])
            if let match = directMatch {
                let analysis = match.foodAnalysis
                let component = restaurantComponent(query: parent, match: match, analysis: analysis)
                let coveredParentTerms = Set(meaningfulTokens(
                    ([match.menuItem.name, match.selectedVariant?.name ?? ""]
                        + match.resolvedComponents.map(\.name)
                        + match.additionalComponents.map { $0.menuItem.name }).joined(separator: " ")
                ))
                let uncoveredFoods = residualFoods.filter {
                    !coveredParentTerms.contains(meaningfulTokens($0).first ?? $0)
                }
                if isConfiguredParent && !uncoveredFoods.isEmpty {
                    if let split = try await resolveConfiguredParentAndExtra(
                        parent, residualFoods: uncoveredFoods,
                        restaurantResolver: restaurantResolver, estimate: estimate, trace: trace
                    ) { return split }
                    return FoodQueryResolution(analysis: nil, restaurantMatch: nil,
                                               components: [component] + uncoveredFoods.map(unresolved))
                }
                var tracked = analysis
                tracked?.foodResolutionComponents = [component]
                return FoodQueryResolution(analysis: tracked, restaurantMatch: match, components: [component])
            }
            if isConfiguredParent && hasResidualFood {
                if let split = try await resolveConfiguredParentAndExtra(
                    parent, residualFoods: residualFoods,
                    restaurantResolver: restaurantResolver, estimate: estimate, trace: trace
                ) { return split }
                return FoodQueryResolution(analysis: nil, restaurantMatch: nil,
                                           components: [unresolved(parent)])
            }
            let analysis = try await estimate(description)
            let tracked = trackEstimate(analysis, query: parent)
            trace.record(parent, resolver: "Text nutrition fallback", outcome: tracked.isComplete ? "selected" : "identityRejected",
                         source: analysis.nutritionSource,
                         reason: tracked.isComplete ? nil : "Estimated identity did not account for this food")
            return tracked
        }

        let segments = split(parent, intent: intent)
        var records: [FoodResolutionComponent] = []
        var analyses: [GeminiService.FoodAnalysis] = []
        for segment in segments {
            try Task.checkCancellation()
            let restaurantMatch: RestaurantMatch?
            if segment.isRestaurant {
                if let rawMatch = await restaurantResolver(segment.query) {
                    restaurantMatch = rawMatch
                } else if let canonical = segment.canonicalQuery {
                    restaurantMatch = await restaurantResolver(canonical)
                } else {
                    restaurantMatch = nil
                }
                trace.record(segment.query, resolver: "RestaurantNutritionProvider",
                             outcome: restaurantMatch == nil ? "noMatch" : "selected",
                             candidateItemID: restaurantMatch?.menuItem.id,
                             source: restaurantMatch?.foodAnalysis?.nutritionSourceDetail,
                             modifiers: restaurantMatch?.matchedModifiers.map(\.name) ?? [])
            } else {
                restaurantMatch = nil
            }
            if let match = restaurantMatch,
               match.clarificationPlan.isEmpty,
               let analysis = match.foodAnalysis {
                records.append(restaurantComponent(query: segment.query, match: match, analysis: analysis))
                analyses.append(analysis)
                continue
            }
            do {
                let estimateQuery = segment.canonicalQuery ?? segment.query
                let estimated = try await estimate(estimateQuery)
                let tracked = trackEstimate(estimated, query: estimateQuery, singleFoodIntent: true)
                trace.record(segment.query, resolver: "Text nutrition fallback",
                             outcome: tracked.isComplete ? "selected" : "identityRejected",
                             source: estimated.nutritionSource,
                             reason: tracked.isComplete ? nil : "Estimated identity did not account for this food")
                records.append(contentsOf: tracked.components)
                if tracked.isComplete, let analysis = tracked.analysis { analyses.append(analysis) }
            } catch is CancellationError {
                throw CancellationError()
            } catch let quota as HostedAIQuotaError {
                throw quota
            } catch {
                trace.record(segment.query, resolver: "Text nutrition fallback", outcome: "failed",
                             reason: "Resolver threw \(type(of: error))")
                records.append(unresolved(segment.query))
            }
        }
        guard records.allSatisfy(\.isResolved), analyses.count == segments.count else {
            return FoodQueryResolution(analysis: nil, restaurantMatch: nil, components: records)
        }
        return FoodQueryResolution(
            analysis: aggregate(analyses, components: records),
            restaurantMatch: nil,
            components: records
        )
    }

    private struct Segment {
        let query: String
        let isRestaurant: Bool
        let canonicalQuery: String?
    }

    private static func resolveConfiguredParentAndExtra(
        _ description: String,
        residualFoods: [String],
        restaurantResolver: @escaping RestaurantResolver,
        estimate: @escaping Estimator,
        trace: FoodResolutionTraceRecorder
    ) async throws -> FoodQueryResolution? {
        let words = FoodQueryInterpreter.lexicalCleanup(description).split(separator: " ").map(String.init)
        guard words.count > 2 else { return nil }
        let extras = Set(residualFoods)
        for cut in stride(from: words.count - 1, through: 1, by: -1) {
            var prefix = Array(words[..<cut])
            var suffix = Array(words[cut...])
            while let last = prefix.last, ["and", "with", "plus"].contains(last) { prefix.removeLast() }
            while let first = suffix.first, ["and", "with", "plus"].contains(first) { suffix.removeFirst() }
            guard !prefix.isEmpty, !suffix.isEmpty, suffix.contains(where: extras.contains) else { continue }
            let parentQuery = prefix.joined(separator: " ")
            let candidate = await restaurantResolver(parentQuery)
            trace.record(parentQuery, resolver: "RestaurantNutritionProvider",
                         outcome: candidate == nil ? "noMatch" : "candidate",
                         candidateItemID: candidate?.menuItem.id,
                         source: candidate?.foodAnalysis?.nutritionSourceDetail)
            guard let match = candidate,
                  match.clarificationPlan.isEmpty,
                  let parentAnalysis = match.foodAnalysis else { continue }
            let parentComponent = restaurantComponent(query: parentQuery, match: match, analysis: parentAnalysis)
            let extraQuery = suffix.joined(separator: " ")
            do {
                let extraAnalysis = try await estimate(extraQuery)
                let tracked = trackEstimate(extraAnalysis, query: extraQuery, singleFoodIntent: true)
                trace.record(extraQuery, resolver: "Text nutrition fallback",
                             outcome: tracked.isComplete ? "selected" : "identityRejected",
                             source: extraAnalysis.nutritionSource,
                             reason: tracked.isComplete ? nil : "Estimated identity did not account for this food")
                let records = [parentComponent] + tracked.components
                guard tracked.isComplete, let resolvedExtra = tracked.analysis else {
                    return FoodQueryResolution(analysis: nil, restaurantMatch: nil, components: records)
                }
                return FoodQueryResolution(
                    analysis: aggregate([parentAnalysis, resolvedExtra], components: records),
                    restaurantMatch: nil, components: records
                )
            } catch is CancellationError {
                throw CancellationError()
            } catch let quota as HostedAIQuotaError {
                throw quota
            } catch {
                trace.record(extraQuery, resolver: "Text nutrition fallback", outcome: "failed",
                             reason: "Resolver threw \(type(of: error))")
                return FoodQueryResolution(analysis: nil, restaurantMatch: nil,
                                           components: [parentComponent, unresolved(extraQuery)])
            }
        }
        return nil
    }

    private static func split(_ description: String, intent: FoodQueryIntent) -> [Segment] {
        let words = FoodQueryInterpreter.lexicalCleanup(description).split(separator: " ").map(String.init)
        var used = Set(intent.items.flatMap { $0.wordRange })
        var segments: [(Int, Segment)] = []
        for item in intent.items {
            var prefix: [String] = []
            var index = item.wordRange.lowerBound - 1
            while index >= 0, !used.contains(index),
                  (Int(words[index]) != nil || ["small", "medium", "large", "regular", "original"].contains(words[index])) {
                prefix.insert(words[index], at: 0)
                used.insert(index)
                index -= 1
            }
            var query = (prefix + [item.rawSpan]).joined(separator: " ")
            var canonical = (prefix + [item.interpretedName]).joined(separator: " ")
            if item.category == "burger" { query += " only"; canonical += " only" }
            segments.append((item.wordRange.lowerBound, Segment(query: query, isRestaurant: true,
                                                                  canonicalQuery: canonical == query ? nil : canonical)))
        }
        let unresolved = Set(intent.unresolvedTerms)
        var gapStart: Int?
        for index in 0...words.count {
            let isGap = index < words.count && !used.contains(index)
            if isGap, gapStart == nil { gapStart = index }
            if !isGap, let start = gapStart {
                let range = start..<index
                if range.contains(where: { unresolved.contains(words[$0]) }) {
                    let gap = words[range].joined(separator: " ")
                        .replacingOccurrences(of: #"^(and|with|plus)\s+"#, with: "", options: .regularExpression)
                        .replacingOccurrences(of: #"\s+(and|with|plus)$"#, with: "", options: .regularExpression)
                    if !gap.isEmpty { segments.append((start, Segment(query: gap, isRestaurant: false, canonicalQuery: nil))) }
                }
                gapStart = nil
            }
        }
        return segments.sorted { $0.0 < $1.0 }.map(\.1)
    }

    private static func restaurantComponent(
        query: String,
        match: RestaurantMatch,
        analysis: GeminiService.FoodAnalysis?
    ) -> FoodResolutionComponent {
        FoodResolutionComponent(
            query: query, name: analysis?.name ?? match.menuItem.name,
            state: analysis == nil ? .unresolved : (analysis?.nutritionConfidence == "High" ? .verifiedRestaurant : .partiallyVerifiedRestaurant),
            quantity: Double(match.quantity), calories: analysis?.calories,
            protein: analysis?.proteinIsKnown == true ? analysis?.protein : nil,
            carbs: analysis?.carbsAreKnown == true ? analysis?.carbs : nil,
            fat: analysis?.fatIsKnown == true ? analysis?.fat : nil,
            sourceDetail: analysis?.nutritionSourceDetail,
            sourceItemID: match.menuItem.id
        )
    }

    static func trackEstimate(_ analysis: GeminiService.FoodAnalysis, query: String,
                              singleFoodIntent: Bool = false) -> FoodQueryResolution {
        // A single queried dish can still contain ingredients resolved from
        // different sources. Keep those source boundaries, while retaining one
        // dish component for homogeneous ingredient breakdowns.
        let ingredientSources = Set(analysis.ingredients.map { $0.nutritionSource ?? "AI estimate" })
        let preserveIngredients = !analysis.ingredients.isEmpty && (!singleFoodIntent || ingredientSources.count > 1)
        let missing = analysis.foodIdentityConfirmed == false ? [query]
            : missingFoodIdentity(in: query, analysis: analysis,
                                  preserveIngredients: preserveIngredients)
        var records: [FoodResolutionComponent] = []
        if !preserveIngredients {
            records.append(estimateComponent(query: query, analysis: analysis))
        } else {
            for ingredient in analysis.ingredients {
                let source = ingredient.nutritionSource ?? "AI estimate"
                records.append(FoodResolutionComponent(
                    query: ingredient.name, name: ingredient.name, state: state(for: source),
                    quantity: 1, calories: ingredient.calories, protein: ingredient.protein,
                    carbs: ingredient.carbs, fat: ingredient.fat,
                    sourceDetail: ingredient.nutritionSourceDetail, sourceItemID: nil
                ))
            }
        }
        // A residual query is a food phrase, not a bag of independent words.
        // Retain it intact when the estimate omits any meaningful part.
        if !missing.isEmpty { records.append(unresolved(query)) }
        var tracked = analysis
        tracked.foodResolutionComponents = records
        return FoodQueryResolution(analysis: missing.isEmpty ? tracked : nil, restaurantMatch: nil,
                                   components: records, candidateAnalysis: tracked)
    }

    private static func estimateComponent(query: String, analysis: GeminiService.FoodAnalysis) -> FoodResolutionComponent {
        FoodResolutionComponent(
            query: query, name: analysis.name, state: state(for: analysis.nutritionSource),
            quantity: analysis.selectedServingQuantity ?? 1, calories: analysis.calories,
            protein: analysis.proteinIsKnown ? analysis.protein : nil,
            carbs: analysis.carbsAreKnown ? analysis.carbs : nil,
            fat: analysis.fatIsKnown ? analysis.fat : nil,
            sourceDetail: analysis.nutritionSourceDetail, sourceItemID: nil
        )
    }

    private static func state(for source: String) -> FoodResolutionState {
        if source == "AUSNUT Australia" { return .ausnut }
        if source == "Structured estimate" { return .structuredEstimate }
        return .aiEstimate
    }

    private static func unresolved(_ query: String) -> FoodResolutionComponent {
        FoodResolutionComponent(query: query, name: query, state: .unresolved, quantity: 1,
                                calories: nil, protein: nil, carbs: nil, fat: nil,
                                sourceDetail: nil, sourceItemID: nil)
    }

    private static func meaningfulTokens(_ value: String) -> [String] {
        let ignored: Set<String> = ["a", "an", "and", "with", "of", "the", "on", "in", "for", "had", "i", "homemade", "bit", "little", "small", "medium", "large", "regular", "only", "plus"]
        return FoodQueryInterpreter.lexicalCleanup(value).split(separator: " ").map(String.init)
            .filter { Int($0) == nil && !ignored.contains($0) }
            .map {
                if $0.hasSuffix("oes"), $0.count > 4 { return String($0.dropLast(2)) }
                return $0.hasSuffix("s") && $0.count > 3 ? String($0.dropLast()) : $0
            }
            .map { $0 == "coke" ? "cola" : $0 }
    }

    private static func missingFoodIdentity(
        in query: String, analysis: GeminiService.FoodAnalysis, preserveIngredients: Bool
    ) -> [String] {
        let identity = FoodIntentRouter.foodIdentity(in: query)
        let context: Set<String> = [
            "plate", "bowl", "cup", "piece", "serving", "that", "it",
            "one", "two", "three", "four", "five", "six", "seven", "eight", "nine", "ten",
            "eleven", "twelve"
        ]
        func foodTokens(_ text: String) -> [String] {
            meaningfulTokens(text).filter { !context.contains($0) }
        }
        let requested = foodTokens(identity)
        let ingredientTokens = Set(analysis.ingredients.flatMap { foodTokens($0.name) })
        let parentTokens = Set(foodTokens(analysis.name))
        if !preserveIngredients {
            return requested.filter { !parentTokens.contains($0) }
        }

        let missingFromIngredients = requested.filter { !ingredientTokens.contains($0) }
        guard !missingFromIngredients.isEmpty else { return [] }

        // A dish title can explain its form (or an introductory collective
        // description), but cannot stand in for an omitted listed food.
        let rawIdentity: String
        if identity != FoodQueryInterpreter.lexicalCleanup(query),
           let location = query.range(of: " from ", options: .caseInsensitive) {
            rawIdentity = String(query[..<location.lowerBound])
        } else {
            rawIdentity = query
        }
        let commaClauses = rawIdentity.split(separator: ",").map(String.init)
        if commaClauses.count > 1 {
            let listed = commaClauses.dropFirst().flatMap(foodTokens)
            let omitted = listed.filter { !ingredientTokens.contains($0) }
            let first = commaClauses[0]
            let isServingIntroduction = !Set(meaningfulTokens(first)).isDisjoint(
                with: ["plate", "bowl", "cup", "serving"])
            let introductionMissing = foodTokens(first).filter {
                !ingredientTokens.contains($0) && !(isServingIntroduction && parentTokens.contains($0))
            }
            return introductionMissing + omitted
        }

        let clauses = rawIdentity.replacingOccurrences(
            of: #"\b(and|with|plus)\b"#, with: ",", options: .regularExpression
        ).split(separator: ",").map(String.init)
        let everyClauseHasIngredient = clauses.allSatisfy { clause in
            !Set(foodTokens(clause)).isDisjoint(with: ingredientTokens)
        }
        let isSingleDish = clauses.count == 1 && requested.count <= 2
            && !Set(requested).isDisjoint(with: ingredientTokens)
        // A longer, unpunctuated dish may end in its prepared form rather than
        // another ingredient. Require every preceding requested identity in the
        // breakdown, plus a separately named ingredient supporting a composed
        // dish. The parent title alone never supplies that evidence.
        let missingForm = requested.last
        let hasComposedDishEvidence = clauses.count == 1
            && missingFromIngredients.count == 1
            && missingFromIngredients.first == missingForm
            && requested.dropLast().allSatisfy(ingredientTokens.contains)
            && !ingredientTokens.subtracting(Set(requested)).isEmpty
        guard everyClauseHasIngredient && (clauses.count > 1 || isSingleDish || hasComposedDishEvidence) else {
            return missingFromIngredients
        }
        return missingFromIngredients.filter { !parentTokens.contains($0) }
    }

    private static func aggregate(
        _ analyses: [GeminiService.FoodAnalysis], components: [FoodResolutionComponent]
    ) -> GeminiService.FoodAnalysis {
        let sources = Set(analyses.map(\.nutritionSource))
        var result = GeminiService.FoodAnalysis(
            name: analyses.map(\.name).joined(separator: " + "),
            calories: analyses.reduce(0) { $0 + $1.calories },
            protein: analyses.reduce(0) { $0 + $1.protein },
            carbs: analyses.reduce(0) { $0 + $1.carbs },
            fat: analyses.reduce(0) { $0 + $1.fat },
            servingSizeGrams: analyses.allSatisfy(\.servingSizeIsKnown)
                ? analyses.reduce(0) { $0 + $1.servingSizeGrams } : 0
        )
        result.servingSizeIsKnown = analyses.allSatisfy(\.servingSizeIsKnown)
        result.selectedServingQuantity = 1
        result.selectedServingUnit = "meal"
        result.proteinIsKnown = analyses.allSatisfy(\.proteinIsKnown)
        result.carbsAreKnown = analyses.allSatisfy(\.carbsAreKnown)
        result.fatIsKnown = analyses.allSatisfy(\.fatIsKnown)
        func sum(_ field: KeyPath<GeminiService.FoodAnalysis, Double?>) -> Double? {
            guard analyses.allSatisfy({ $0[keyPath: field] != nil }) else { return nil }
            return analyses.reduce(0) { $0 + ($1[keyPath: field] ?? 0) }
        }
        result.sugar = sum(\.sugar)
        result.addedSugar = sum(\.addedSugar)
        result.fiber = sum(\.fiber)
        result.saturatedFat = sum(\.saturatedFat)
        result.monounsaturatedFat = sum(\.monounsaturatedFat)
        result.polyunsaturatedFat = sum(\.polyunsaturatedFat)
        result.cholesterol = sum(\.cholesterol)
        result.caffeine = sum(\.caffeine)
        result.sodium = sum(\.sodium)
        result.potassium = sum(\.potassium)
        result.transFat = sum(\.transFat)
        result.calcium = sum(\.calcium)
        result.iron = sum(\.iron)
        result.magnesium = sum(\.magnesium)
        result.zinc = sum(\.zinc)
        result.vitaminA = sum(\.vitaminA)
        result.vitaminC = sum(\.vitaminC)
        result.vitaminD = sum(\.vitaminD)
        result.vitaminB12 = sum(\.vitaminB12)
        result.vitaminE = sum(\.vitaminE)
        result.vitaminK = sum(\.vitaminK)
        result.folate = sum(\.folate)
        result.omega3 = sum(\.omega3)
        result.ingredients = analyses.flatMap { analysis -> [MealIngredient] in
            if !analysis.ingredients.isEmpty,
               analysis.ingredients.ingredientTotals.calories == analysis.calories {
                return analysis.ingredients.map { ingredient in
                    var tracked = ingredient
                    if tracked.nutritionSource == nil {
                        tracked.nutritionSource = analysis.nutritionSource == "AUSNUT Australia"
                            ? "AI estimate" : analysis.nutritionSource
                    }
                    return tracked
                }
            }
            return [MealIngredient(name: analysis.name, grams: analysis.servingSizeGrams,
                                   calories: analysis.calories, protein: analysis.protein,
                                   carbs: analysis.carbs, fat: analysis.fat, emoji: analysis.emoji,
                                   nutritionSource: analysis.nutritionSource,
                                   nutritionSourceDetail: analysis.nutritionSourceDetail)]
        }
        result.resolvedComponents = analyses.flatMap(\.resolvedComponents)
        result.foodResolutionComponents = components
        result.nutritionSource = sources.count == 1 ? (sources.first ?? "AI estimate") : "Mixed nutrition sources"
        result.nutritionSourceDetail = components.compactMap(\.sourceDetail).joined(separator: " · ")
        result.nutritionConfidence = analyses.allSatisfy { $0.nutritionConfidence == "High" } ? "High" : "Medium"
        return result
    }
}
