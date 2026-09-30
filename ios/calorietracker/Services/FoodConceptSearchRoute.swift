import Foundation

/// A routing decision only. Source IDs are resolved by the existing selection paths;
/// an unresolved concept has no nutrition or substitute source identity.
enum FoodConceptSearchRoute: Equatable {
    case sourced(String, refinements: [String])
    case clarification([String])
    case unknownVariant(query: String, alternatives: [String])
    case weakAlternatives(query: String, sourceIDs: [String])
    case analyse(String)

    init(_ assessment: FoodConceptIdentityAssessment, suggestions: [UnifiedFoodSuggestion] = []) {
        switch assessment.state {
        case .defaultable:
            if let sourceID = assessment.defaultSourceID {
                self = .sourced(sourceID, refinements: assessment.optionalRefinementAvailable
                    ? assessment.candidateSourceIDs.filter { $0 != sourceID } : [])
            } else {
                self = .analyse(assessment.query)
            }
        case .clarificationRequired:
            self = .clarification(assessment.candidateSourceIDs)
        case .unknownVariant:
            self = .unknownVariant(query: assessment.query,
                                   alternatives: assessment.candidateSourceIDs)
        case .noTrustedMatch:
            var seen: Set<String> = []
            let sourceIDs = suggestions.compactMap { suggestion -> String? in
                let sourceID: String
                switch suggestion {
                case .ausnut(let food): sourceID = food.id
                case .restaurant(let food):
                    guard food.restaurantSelection != nil else { return nil }
                    sourceID = "restaurant:\(food.id)"
                }
                return seen.insert(sourceID).inserted ? sourceID : nil
            }
            self = sourceIDs.isEmpty ? .analyse(assessment.query)
                : .weakAlternatives(query: assessment.query, sourceIDs: sourceIDs)
        }
    }

    var candidateSourceIDs: [String] {
        switch self {
        case .sourced(_, let refinements): refinements
        case .clarification(let candidates): candidates
        case .unknownVariant(_, let alternatives): alternatives
        case .weakAlternatives(_, let sourceIDs): sourceIDs
        case .analyse: []
        }
    }

    /// Explicitly choosing to estimate is the only AI route from an unknown variant.
    var allowsExplicitEstimate: Bool {
        if case .unknownVariant = self { return true }
        return false
    }

    var isWeakAlternative: Bool {
        if case .weakAlternatives = self { return true }
        return false
    }
}

enum FoodConceptChoiceState: Equatable {
    case discovery
    case choosing
    case unresolved(String)

    mutating func notSure(about route: FoodConceptSearchRoute) {
        guard case .unknownVariant(let query, _) = route else { return }
        self = .unresolved(query)
    }

    var explicitEstimateQuery: String? {
        if case .unresolved(let query) = self { return query }
        return nil
    }
}

enum SearchFoodAIUnavailableMessage {
    static func message(for error: Error) -> String? {
        if error is GeminiService.AnalysisError || error is AnalysisFallbackError {
            return "AI estimate is currently unavailable. Refine your search or choose a sourced food instead."
        }
        return nil
    }
}
