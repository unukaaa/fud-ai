import Foundation

/// Estimate-only interpretation. Role/preparation/context are proposals retained
/// as assumptions, never exact identity evidence or source nutrition.
struct EstimateCandidateContext: Sendable {
    enum Role: String, Sendable { case ingredient, completeDish, carrier, condiment, spread, preparedDish }
    let component: String
    let role: Role
    let mealDescription: String
    let preparation: FoodPreparationBasis
    let preparationText: String?
    var asEaten: AsEatenPreparationEvidence? = nil

    static func component(_ proposal: FoodComponentProposal, in meal: String) -> Self {
        var words = EstimateCandidatePartition.words(proposal.name)
        let forms: Set<String> = ["bread", "wrap", "flatbread", "roll", "crispbread", "sauce", "dressing", "spread", "sandwich"]
        for form in forms where words.contains(form + "s") { words.insert(form) }
        // Small food-FORM vocabulary, not identity defaults or food aliases.
        let role: Role
        if !words.intersection(["bread", "wrap", "flatbread", "roll", "crispbread"]).isEmpty { role = .carrier }
        else if !words.intersection(["sauce", "ketchup", "dressing"]).isEmpty { role = .condiment }
        else if !words.intersection(["butter", "spread", "jam", "paste", "dip", "hummus", "hommus"]).isEmpty { role = .spread }
        else if !words.intersection(["pizza", "porridge", "soup", "curry", "salad", "sandwich"]).isEmpty { role = .preparedDish }
        else { role = .ingredient }
        return Self(component: proposal.name, role: role, mealDescription: meal,
                    preparation: proposal.preparation, preparationText: proposal.preparationText)
    }
}

struct EstimateSourceFacets: Hashable, Sendable {
    enum Basis: String, Sendable { case raw, cookedPrepared, dryUncooked, readyToEat, friedCoated, unknown }
    enum Fat: String, Sendable { case added, none, unspecified }
    enum Sugar: String, Sendable { case regular, reduced, none, unspecified }
    enum Recipe: String, Sendable { case ordinary, modified, composite }
    enum Formulation: String, Sendable {
        case unspecified, ordinary, lowCarbohydrate, highProtein, glutenFree
        case reducedEnergy, reducedFat, fatFree, skimmed, otherModified
    }
    enum Base: String, Sendable { case unspecified, standard, thin, thickDeepPan, stuffed, otherModified, notApplicable }
    let family: String
    let role: EstimateCandidateContext.Role
    let basis: Basis
    let methods: Set<String>
    let drained: Bool
    let fat: Fat
    let sugar: Sugar
    let storage: Set<String>
    let recipe: Recipe
    let recipeModifiers: [String]
    let formulation: Set<Formulation>
    let base: Set<Base>
    /// Uninterpreted explicit modifications cannot collapse to one "other" group.
    let otherFormulationClauses: [String]
    /// Labels remain evidence, not a guarantee of dietary suitability.
    let dietaryLabels: Set<String>
    let clauses: [String]

    /// Cooking method alternatives are evidence, not simultaneous states.
    var partitionKey: String {
        [family, role.rawValue, basis.rawValue, methods.sorted().joined(separator: ":"), String(drained), fat.rawValue, sugar.rawValue,
         storage.sorted().joined(separator: ":"), recipe.rawValue,
         recipeModifiers.joined(separator: ":"), formulation.map(\.rawValue).sorted().joined(separator: ":"),
         base.map(\.rawValue).sorted().joined(separator: ":"),
         otherFormulationClauses.joined(separator: ":")].joined(separator: "|")
    }
}

struct EstimateCandidatePartitionResult: Sendable {
    struct Candidate: Sendable { let sourceID: String; let name: String; let facets: EstimateSourceFacets }
    struct Partition: Sendable {
        let key: String
        let candidates: [Candidate]
        let eligible: Bool
        let rejectionReasons: [String]
    }
    let context: EstimateCandidateContext
    let partitions: [Partition]
    let evidenceIDs: [String]
    let reasons: [String]
    let assumptions: [String]
    let uncertainty: [String]
}

enum EstimateCandidatePartition {
    static let version = "source-scope-partitions-v2.1"
    private static let methods: Set<String> = ["boiled", "baked", "grilled", "roasted", "steamed", "poached", "fried", "microwaved", "bbq", "toasted"]
    private static let prepWords = methods.union(["raw", "uncooked", "dry", "dried", "cooked", "prepared", "drained"])

    static func words(_ text: String) -> Set<String> {
        Set(text.lowercased().folding(options: .diacriticInsensitive, locale: Locale(identifier: "en_AU"))
            .replacingOccurrences(of: "[^a-z0-9><=]+", with: " ", options: .regularExpression)
            .split(separator: " ").map(String.init))
    }

    private static func clauses(_ name: String) -> [String] {
        name.lowercased().split(separator: ",").map { $0.trimmingCharacters(in: .whitespaces) }
    }

    static func facets(_ name: String) -> EstimateSourceFacets {
        let parts = clauses(name), head = parts.first ?? "", w = words(name)
        let headWords = words(head)
        let carrier = !headWords.intersection(["bread", "roll", "biscuit", "crispbread"]).isEmpty
        let prepared = !headWords.intersection(["porridge", "pizza", "soup", "curry", "sandwich", "salad", "cake", "pie", "meal"]).isEmpty
        let role: EstimateCandidateContext.Role = carrier ? .carrier :
            !headWords.intersection(["sauce", "dressing"]).isEmpty ? .condiment :
            !headWords.intersection(["spread", "butter", "jam", "paste", "dip"]).isEmpty ? .spread :
            prepared ? .preparedDish : .ingredient
        let cooking = w.intersection(methods)
        let basis: EstimateSourceFacets.Basis
        if w.contains("raw") { basis = .raw }
        else if w.contains("uncooked") || w.contains("dry") || w.contains("dried") { basis = .dryUncooked }
        else if !w.intersection(["coated", "crumbed", "battered"]).isEmpty || cooking == ["fried"] { basis = .friedCoated }
        else if !cooking.isEmpty || !w.intersection(["cooked", "prepared", "mashed"]).isEmpty || name.lowercased().contains("made with") { basis = .cookedPrepared }
        else if carrier || prepared || name.lowercased().contains("ready to eat") { basis = .readyToEat }
        else { basis = .unknown }
        let negativeFat = parts.contains { $0.contains("no added fat") || $0.contains("without added fat") }
        let fat: EstimateSourceFacets.Fat = negativeFat ? .none : parts.contains { $0.contains("added fat") } ? .added : .unspecified
        let negativeSugar = parts.contains { $0.contains("no added sugar") || $0.contains("no sugar") || $0.contains("without sugar") || $0.contains("zero sugar") }
        let sugar: EstimateSourceFacets.Sugar = negativeSugar ? .none : parts.contains { $0.contains("reduced sugar") || $0.contains("low sugar") } ? .reduced : w.contains("regular") || name.lowercased().contains("added sugar") ? .regular : .unspecified
        let modifierWords: Set<String> = ["filled", "marinated", "flavoured", "flavored", "reduced", "increased", "syrup", "coated", "crumbed", "battered", "topped", "iced", "sweetened"]
        let modifiers = parts.dropFirst().filter { clause in
            !words(clause).intersection(modifierWords).isEmpty || clause.contains("with added") || clause.contains("mixed with")
                || clause.contains("made with") || clause.contains("for use with")
                || clause.contains(" with ")
                || clause.hasPrefix("with ")
        }.sorted()
        let normalized = " " + name.lowercased()
            .replacingOccurrences(of: "[^a-z0-9]+", with: " ", options: .regularExpression)
            .trimmingCharacters(in: .whitespaces) + " "
        func has(_ phrases: [String]) -> Bool { phrases.contains { normalized.contains(" " + $0 + " ") } }
        var formulation: Set<EstimateSourceFacets.Formulation> = []
        if has(["low carbohydrate", "low carbohydrates", "low carb", "low carbs", "reduced carbohydrate", "reduced carbohydrates"]) { formulation.insert(.lowCarbohydrate) }
        if has(["high protein", "protein enriched"]) { formulation.insert(.highProtein) }
        if has(["gluten free", "without gluten", "free from gluten"]) { formulation.insert(.glutenFree) }
        if has(["reduced energy", "low energy", "energy reduced"]) { formulation.insert(.reducedEnergy) }
        if has(["reduced fat", "low fat"]) { formulation.insert(.reducedFat) }
        if has(["fat free", "no fat", "without fat"]) { formulation.insert(.fatFree) }
        if has(["skim", "skimmed"]) { formulation.insert(.skimmed) }
        if has(["ordinary formulation", "standard formulation", "regular formulation"]) { formulation.insert(.ordinary) }
        var base: Set<EstimateSourceFacets.Base> = []
        var otherClauses: [String] = []
        for clause in parts {
            let tokens = words(clause)
            let structural = !tokens.intersection(["base", "crust"]).isEmpty
            if structural && tokens.contains("thin") { base.insert(.thin) }
            if structural && tokens.contains("thick") || clause.contains("deep pan") || clause.contains("deep-pan") { base.insert(.thickDeepPan) }
            if structural && tokens.contains("stuffed") { base.insert(.stuffed) }
            if structural && !tokens.intersection(["standard", "regular"]).isEmpty { base.insert(.standard) }
            if !tokens.intersection(["modified", "reformulated", "alternative"]).isEmpty {
                if structural { base.insert(.otherModified); otherClauses.append(clause) }
                else if tokens.contains("formulation") || tokens.contains("reformulated") {
                    formulation.insert(.otherModified); otherClauses.append(clause)
                }
            }
        }
        if has(["no base", "no crust", "without base", "without crust", "crustless"]) { base = [.notApplicable] }
        // Absence never means standard. Multiple explicit qualifiers survive.
        if formulation.isEmpty { formulation = [.unspecified] }
        if base.isEmpty { base = [.unspecified] }
        let dietaryLabels: Set<String> = has(["lactose free", "without lactose"]) ? ["lactose_free"] : []
        return EstimateSourceFacets(family: head, role: role, basis: basis, methods: cooking,
            drained: w.contains("drained"), fat: fat, sugar: sugar,
            storage: w.intersection(["canned", "frozen", "dehydrated"]),
            recipe: modifiers.contains(where: { !$0.contains("made with") }) ? .modified : .ordinary,
            recipeModifiers: modifiers, formulation: formulation, base: base,
            otherFormulationClauses: otherClauses.sorted(), dietaryLabels: dietaryLabels, clauses: parts)
    }

    static func assess(_ context: EstimateCandidateContext, identities: [AUSNUTFoodIdentity]) -> EstimateCandidatePartitionResult {
        let vocabulary = Set(identities.flatMap { words($0.name) })
        func normal(_ word: String) -> String {
            if word == "flatbread" { return "flatbread" }
            if word.hasSuffix("ies"), vocabulary.contains(String(word.dropLast(3)) + "y") { return String(word.dropLast(3)) + "y" }
            if word.hasSuffix("s"), !word.hasSuffix("ss"), !word.hasSuffix("us"), !word.hasSuffix("is"), vocabulary.contains(String(word.dropLast())) { return String(word.dropLast()) }
            return word
        }
        func normalWords(_ text: String) -> Set<String> {
            var w = Set(words(text).map(normal))
            if w.remove("flatbread") != nil { w.formUnion(["flat", "bread"]) }
            return w
        }
        let query = normalWords(context.component)
        let wantsPlain = query.contains("plain") || query.contains("natural")
        // Plain/natural are recipe qualifiers, not erased identity nouns.
        let identity = query.subtracting(prepWords.union(["plain", "natural", "made", "with"]))
        let explicitMethods = words(context.preparationText ?? "").intersection(methods)
        let request = context.asEaten.map { AsEatenPreparationPolicy.assess($0).basis } ?? context.preparation
        let discovered = identities.filter { !identity.isEmpty && identity.isSubset(of: normalWords($0.name)) }
        let hasHeadAnchor = discovered.contains {
            let head = normalWords(String($0.name.split(separator: ",").first ?? ""))
            return !head.isEmpty && head.isSubset(of: identity)
        }
        var groups: [String: [EstimateCandidatePartitionResult.Candidate]] = [:]
        var rejected: [String: Set<String>] = [:]
        for source in identities {
            let sourceWords = normalWords(source.name)
            guard !identity.isEmpty, identity.isSubset(of: sourceWords) else { continue }
            let f = facets(source.name)
            var why: Set<String> = []
            let head = normalWords(f.family)
            if hasHeadAnchor && !head.isSubset(of: identity) {
                why.insert("source_head_is_other_food_or_composite")
            }
            if f.role == .preparedDish && context.role != .preparedDish && context.role != .completeDish {
                why.insert("component_not_containing_complete_dish")
            }
            if context.role == .carrier && f.role != .carrier { why.insert("not_carrier") }
            if context.role == .condiment && f.role != .condiment { why.insert("not_condiment") }
            if context.role == .spread && f.role != .spread { why.insert("not_spread") }
            // A noun in a subordinate ingredient clause is not the whole food.
            if head.isDisjoint(with: identity) && f.role != context.role && !(context.role == .ingredient && f.role == .ingredient) {
                why.insert("subordinate_ingredient_not_requested_food")
            }
            if wantsPlain && f.recipe != .ordinary { why.insert("plain_scope_excludes_modified_recipe") }
            // Extra source recipes are retained in rejected partitions, not
            // interpreted as ingredients the user implied. Cooking liquid is
            // separately validated below rather than removed as an extra.
            for clause in f.recipeModifiers where !clause.contains("made with") {
                let material = words(clause).subtracting(["with", "added", "for", "use", "or", "and"])
                if !material.isSubset(of: normalWords(context.component + " " + context.mealDescription)) {
                    why.insert("unrequested_source_recipe_modifier")
                }
            }
            if !explicitMethods.isEmpty && f.methods.isDisjoint(with: explicitMethods) { why.insert("explicit_method_not_supported") }
            switch request {
            case .raw: if f.basis != .raw { why.insert("raw_basis_not_supported") }
            case .dry:
                if f.basis != .dryUncooked && !(context.role == .carrier && f.basis == .readyToEat) { why.insert("dry_basis_or_ready_texture_not_supported") }
            case .cooked:
                if ![.cookedPrepared, .readyToEat].contains(f.basis) { why.insert("prepared_basis_not_supported") }
            case .fried: if !f.methods.contains("fried") { why.insert("fried_basis_not_supported") }
            case .drained: if !f.drained { why.insert("drained_basis_not_supported") }
            case .unknown, .none: why.insert("preparation_unknown")
            case .other:
                if [.raw, .dryUncooked, .friedCoated].contains(f.basis) { why.insert("unrequested_preparation") }
            }
            // Preserve complete recipe wording: water-containing != water-only.
            if identity.contains("water") && !identity.contains("milk") && sourceWords.contains("milk") { why.insert("unrequested_recipe_liquid") }
            let contextWords = normalWords(context.mealDescription)
            for storage in ["takeaway", "homemade"] where contextWords.contains(storage) {
                if !sourceWords.contains(storage) && context.role == .preparedDish { why.insert("context_origin_not_supported") }
            }
            let candidate = EstimateCandidatePartitionResult.Candidate(sourceID: source.id, name: source.name, facets: f)
            // Context alignment is itself a scope facet. A rejected candidate
            // cannot poison eligible siblings that share coarse source facets.
            let key = f.partitionKey + "|scope:" + why.sorted().joined(separator: ":")
            groups[key, default: []].append(candidate)
            rejected[key, default: []].formUnion(why)
        }
        let partitions = groups.keys.sorted().map { key in
            EstimateCandidatePartitionResult.Partition(key: key, candidates: groups[key]!.sorted { $0.sourceID < $1.sourceID },
                eligible: rejected[key, default: []].isEmpty, rejectionReasons: rejected[key, default: []].sorted())
        }
        let eligible = partitions.filter(\.eligible)
        // Multiple groups are retained, not merged or ranked by dataset order.
        let selected = eligible.count == 1 ? eligible[0].candidates.map(\.sourceID) : []
        return EstimateCandidatePartitionResult(context: context, partitions: partitions,
            evidenceIDs: selected, reasons: selected.isEmpty ? [eligible.isEmpty ? "no_compatible_partition" : "multiple_compatible_partitions_require_scope"] : ["single_compatible_estimate_partition"],
            assumptions: ["Estimate-only role: \(context.role.rawValue)", "Preparation wording retained: \(context.preparationText ?? context.preparation.rawValue)", "Meal context: \(context.mealDescription)"],
            uncertainty: ["Candidate partition is not an exact identity or population representative.",
                "Unspecified formulation, fat and recipe assumptions are not proven by retrieval.",
                "Retained dietary labels and nutrient bounds do not establish dietary suitability.",
                "Excluded source groups remain available for review, not silently merged."])
    }

    static func basis(context: EstimateCandidateContext, amount: GroundedAmount,
                      identities: [AUSNUTFoodIdentity]? = AustralianNutritionService.searchableIdentities,
                      resolver: GroundedEstimateEngine.Resolver = { ExistingFoodGrounder.resolve($0, amount: $1) }) -> GroundedEstimateBasis? {
        guard amount.isValid, amount.unit == .grams, let identities else { return nil }
        let result = assess(context, identities: identities)
        guard !result.evidenceIDs.isEmpty else { return nil }
        var sources: [GroundedSourceResolution] = []
        for id in result.evidenceIDs {
            guard let s = resolver(.ausnut(id), amount), s.sourceID == .ausnut(id), s.sourceType == .ausnut,
                  s.sourceVersion?.isEmpty == false else { return nil }
            sources.append(s)
        }
        guard Set(sources.map(\.sourceVersion)).count == 1,
              let envelope = GroundedNutritionEnvelope.enclosing(sources.map(\.nutrition)) else { return nil }
        return GroundedEstimateBasis(scopedQuery: context.component, method: .scopedSourceEnvelope,
            candidates: sources, envelope: envelope, assumptions: [version] + result.assumptions,
            uncertainty: result.uncertainty)
    }
}
