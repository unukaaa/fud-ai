import Foundation

/// A question about source identities, never a nutrition or source-selection result.
struct FoodClarificationPlan: Equatable {
    enum Dimension: String, Hashable {
        case cut, fatType, cookingState, kind
    }

    struct Option: Equatable, Identifiable {
        let id: String
        let key: String
        let label: String
        let sourceIDs: [String]

        // "Other" does not itself tell us which identity the user meant.
        var resolvedSourceID: String? { key != "other" && sourceIDs.count == 1 ? sourceIDs[0] : nil }
    }

    let dimension: Dimension
    let question: String
    let options: [Option]

    /// A small evidence vocabulary is preferable to guessing from arbitrary words.
    /// Unsupported or small families keep the existing individual sourced choices.
    static func make(
        query: String,
        sources: [(id: String, name: String)],
        excluding usedDimensions: Set<Dimension> = []
    ) -> Self? {
        guard sources.count > 5,
              Set(sources.map(\.id)).count == sources.count,
              sources.allSatisfy({ $0.id.hasPrefix("ausnut:") }) else { return nil }

        let family = query.trimmingCharacters(in: .whitespacesAndNewlines)
        let candidates: [Dimension] = [.cut, .fatType, .cookingState, .kind]
        for dimension in candidates where !usedDimensions.contains(dimension) {
            var groups: [String: [String]] = [:]
            for source in sources {
                let key = groupKey(for: source.name, dimension: dimension) ?? "other"
                groups[key, default: []].append(source.id)
            }
            let meaningful = groups.filter { $0.key != "other" }
            let covered = meaningful.values.reduce(0) { $0 + $1.count }
            let minimumGroups = dimension == .cookingState ? 2 : 3
            let minimumCoverage = (dimension == .fatType || dimension == .cut)
                ? sources.count / 3 : sources.count / 2
            guard meaningful.count >= minimumGroups, covered >= minimumCoverage else { continue }
            // A first-step "type" question must actually reduce a crowded family,
            // not merely rename a flat list of one-record technical variants.
            if dimension == .kind && meaningful.values.filter({ $0.count > 1 }).count < 2 {
                continue
            }

            let ordered = groups.keys.sorted { left, right in
                if left == "other" { return false }
                if right == "other" { return true }
                return left < right
            }
            let options = ordered.map { key in
                Option(id: "\(dimension.rawValue):\(key)",
                       key: key,
                       label: optionLabel(key, dimension: dimension, family: family),
                       sourceIDs: groups[key]!.sorted())
            }
            let question: String
            switch dimension {
            case .cut: question = "Which cut of \(family)?"
            case .cookingState: question = "How was the \(family) prepared?"
            case .fatType, .kind: question = "What type of \(family)?"
            }
            return Self(dimension: dimension, question: question, options: options)
        }
        return nil
    }

    private static func groupKey(for name: String, dimension: Dimension) -> String? {
        let parts = name.lowercased().split(separator: ",").map {
            $0.trimmingCharacters(in: .whitespacesAndNewlines)
        }
        guard parts.count > 1 else { return nil }
        switch dimension {
        case .cut:
            let cuts: Set<String> = ["breast", "thigh", "drumstick", "wing", "whole"]
            return cuts.first { parts[1] == $0 }
        case .fatType:
            if parts.contains(where: { $0 == "lactose free" }) { return "lactose-free" }
            if parts.contains(where: { $0.hasPrefix("rich or creamy") }) { return "extra-creamy" }
            if parts.contains(where: { $0.hasPrefix("regular fat") }) { return "full-cream" }
            if parts.contains(where: { $0.hasPrefix("reduced fat") }) { return "light" }
            if parts.contains(where: { $0.hasPrefix("skim") }) { return "skim" }
            return nil
        case .cookingState:
            if parts.contains(where: { $0 == "raw" }) { return "raw" }
            if parts.contains(where: { $0 == "uncooked" || $0 == "instant dry mix" }) { return "dry" }
            let cookingTerms = ["cooked", "baked", "roasted", "fried", "grilled", "boiled",
                                "steamed", "stewed", "poached", "casseroled", "barbecued"]
            if parts.contains(where: { part in
                part == "made from dry mix" || cookingTerms.contains(where: { part == $0 || part.hasPrefix($0 + " ") })
            }) { return "cooked" }
            return nil
        case .kind:
            let value = parts[1]
            guard value.count <= 24, !value.contains("("), !value.contains("%"),
                  !value.contains(where: \.isNumber),
                  !value.contains(" or "), !value.contains(" & ") else { return nil }
            return value
        }
    }

    private static func optionLabel(_ key: String, dimension: Dimension, family: String) -> String {
        if key == "other" { return "Other \(family.lowercased())" }
        switch dimension {
        case .cut: return key.capitalized
        case .fatType:
            switch key {
            case "lactose-free": return "Lactose-free"
            case "extra-creamy": return "Extra creamy"
            case "full-cream": return "Full cream"
            case "light": return "Light"
            default: return "Skim"
            }
        case .cookingState:
            switch key {
            case "dry": return "Dry / uncooked"
            case "raw": return "Raw"
            default: return "Cooked"
            }
        case .kind:
            if key.contains(family.lowercased()) { return key.capitalized }
            return "\(key.capitalized) \(family.lowercased())"
        }
    }
}

/// Stops only on an exact chosen identity or an explicit source-backed scope.
/// No search rank, nutrient similarity, or inferred popularity is evidence here.
enum FoodClarificationStopPolicy {
    struct Selection: Equatable {
        let dimension: FoodClarificationPlan.Dimension
        let key: String
    }

    enum Decision: Equatable {
        case required
        case optionalRefinement(defaultSourceID: String, refinementIDs: [String])
        case stop(sourceID: String)
    }

    private struct NamedSource {
        let id: String
        let parts: [String]
    }

    static func decide(
        sources: [(id: String, name: String)], selections: [Selection]
    ) -> Decision {
        guard !selections.isEmpty,
              !selections.contains(where: { $0.key == "other" }),
              !sources.isEmpty,
              Set(sources.map(\.id)).count == sources.count,
              sources.allSatisfy({ $0.id.hasPrefix("ausnut:") }) else { return .required }

        let named = sources.map { source in
            NamedSource(id: source.id, parts: source.name.lowercased()
                .split(separator: ",").map { $0.trimmingCharacters(in: .whitespacesAndNewlines) })
        }
        guard named.allSatisfy({ !$0.parts.isEmpty && $0.parts[0] == named[0].parts[0] }) else {
            return .required
        }
        if named.count == 1 { return .stop(sourceID: named[0].id) }

        // NFD is the source's own assertion that the narrower scope is unspecified.
        // Its positive scope descriptors must apply to every remaining candidate.
        let fittingNFD = named.filter { source in
            guard source.parts.last == "not further defined", source.parts.count > 2 else { return false }
            let scope = source.parts.dropFirst().dropLast()
            return named.allSatisfy { other in scope.allSatisfy(other.parts.contains) }
        }
        if fittingNFD.count == 1, let generic = fittingNFD.first {
            return .optionalRefinement(defaultSourceID: generic.id,
                                       refinementIDs: named.map(\.id).filter { $0 != generic.id }.sorted())
        }

        // An unqualified source record can be the ordinary form of the chosen
        // scope only when its complete descriptors are the family's shared prefix.
        let prefix = named.dropFirst().reduce(named[0].parts) { shared, source in
            Array(zip(shared, source.parts).prefix(while: { $0.0 == $0.1 }).map(\.0))
        }
        var scopes = [prefix]
        // Cooked methods (for example fried) are still cooked, but a plain
        // "..., cooked" record is a valid broader source identity if present.
        if selections.contains(where: { $0.dimension == .cookingState && $0.key == "cooked" }),
           prefix.last != "cooked" {
            scopes.append(prefix + ["cooked"])
        }
        let generic = named.filter { candidate in
            scopes.contains(candidate.parts) && candidate.parts.count > 1
        }
        guard generic.count == 1, let source = generic.first else { return .required }
        return .optionalRefinement(defaultSourceID: source.id,
                                   refinementIDs: named.map(\.id).filter { $0 != source.id }.sorted())
    }
}
