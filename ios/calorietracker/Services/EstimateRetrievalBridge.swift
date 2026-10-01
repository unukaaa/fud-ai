import Foundation

/// Estimate evidence only. Never used by exact search, default identity, or UI.
/// Normalisation must find whole source tokens, not a convenient named variant.
enum EstimateRetrievalBridge {
    static let version = "source-token-preparation-bridge-v1"

    struct Assessment: Sendable {
        let candidateIDs: [String]
        let eligibleIDs: [String]
        let reason: String
        let transformations: [String]
    }

    private static let preparationWords: Set<String> = ["raw", "uncooked", "dry", "dried", "cooked",
        "boiled", "baked", "grilled", "roasted", "steamed", "poached", "fried", "drained"]
    private static let cookedWords: Set<String> = ["cooked", "boiled", "baked", "grilled", "roasted", "steamed", "poached"]

    static func assess(_ query: String, identities: [AUSNUTFoodIdentity]) -> Assessment {
        let vocabulary = Set(identities.flatMap { tokens($0.name) })
        func canonical(_ word: String) -> String {
            // Only source-attested inflections; no fuzzy prefix or arbitrary stem.
            if word.hasSuffix("ies") {
                let base = String(word.dropLast(3)) + "y"
                if vocabulary.contains(base) { return base }
            }
            if word.hasSuffix("es") {
                let base = String(word.dropLast(2))
                if vocabulary.contains(base), base.hasSuffix("s") || base.hasSuffix("x")
                    || base.hasSuffix("ch") || base.hasSuffix("sh") { return base }
            }
            if word.hasSuffix("s"), !word.hasSuffix("ss"), !word.hasSuffix("us"), !word.hasSuffix("is") {
                let base = String(word.dropLast())
                if vocabulary.contains(base) { return base }
            }
            return word
        }
        let original = tokens(query)
        let words = Set(original.map(canonical))
        let requestedPreparation = words.intersection(preparationWords)
        let identityWords = words.subtracting(preparationWords)
        let transformations = original == original.map(canonical) ? [] : ["source_attested_inflection"]
        func result(_ all: [AUSNUTFoodIdentity], _ eligible: [AUSNUTFoodIdentity], _ reason: String) -> Assessment {
            Assessment(candidateIDs: all.map(\.id).sorted(), eligibleIDs: eligible.map(\.id).sorted(),
                reason: reason, transformations: transformations + ["whole_token_clause_match", "preparation_compatibility"])
        }
        guard !identityWords.isEmpty else { return result([], [], "empty_identity") }
        let exclusive = requestedPreparation.intersection(["raw", "dry", "dried", "uncooked", "fried", "drained"])
        guard exclusive.count <= 1 || exclusive.isSubset(of: ["dry", "uncooked"]),
              exclusive.isEmpty || requestedPreparation.intersection(cookedWords).isEmpty else {
            return result([], [], "contradictory_preparation_scope")
        }
        // Require all identity qualifiers. Do not erase plain, fat, species, brand,
        // sugar, cocoa comparisons or unrecognised wording to inflate coverage.
        let candidates = identities.filter { record in
            let sourceWords = Set(tokens(record.name).map(canonical))
            guard identityWords.isSubset(of: sourceWords) else { return false }
            let clauses = record.name.split(separator: ",").map { Set(tokens(String($0)).map(canonical)) }
            guard let head = clauses.first else { return false }
            // A family head or a complete source child-clause token establishes
            // discovery. All records still have to share the same source family.
            return !head.intersection(identityWords).isEmpty
                || clauses.dropFirst().contains { !$0.intersection(identityWords).isEmpty }
        }
        let compatible = candidates.filter { record in
            let source = Set(tokens(record.name).map(canonical))
            if requestedPreparation.contains("raw") { return source.contains("raw") && !source.contains("cooked") }
            if !requestedPreparation.intersection(["dry", "dried", "uncooked"]).isEmpty {
                return !source.intersection(["dry", "dried", "uncooked"]).isEmpty
                    && source.intersection(cookedWords.union(["fried"])).isEmpty
            }
            if requestedPreparation.contains("fried") { return source.contains("fried") && !source.contains("raw") }
            if requestedPreparation.contains("drained") { return source.contains("drained") && !source.contains("raw") }
            if !requestedPreparation.intersection(cookedWords).isEmpty {
                guard source.intersection(["raw", "uncooked", "dry", "dried", "fried"]).isEmpty else { return false }
                let specific = requestedPreparation.subtracting(["cooked"])
                if !specific.isEmpty && !specific.isSubset(of: source)
                    && !source.contains("cooked") { return false }
                // Prepared/made-with is explicit source wording, not a food-name
                // rule saying every fruit/food is raw or every dish is cooked.
                return !source.intersection(cookedWords).isEmpty || source.contains("prepared")
                    || record.name.lowercased().contains("made with") || record.name.lowercased().contains("ready to eat")
            }
            // No preparation supplied: only sources without a conflicting stated
            // preparation are usable. Bare rice/banana cannot silently be cooked/raw.
            return source.intersection(preparationWords.union(["frozen", "canned"])).isEmpty
        }
        guard !compatible.isEmpty else { return result(candidates, [], "no_compatible_preparation") }
        let families = Set(compatible.map { canonicalFamily($0.name, canonical: canonical) })
        guard families.count == 1 else { return result(candidates, [], "multiple_source_families") }
        // Preserve material source recipe and storage distinctions. Neither a
        // numeric variance threshold nor source/search order chooses a group.
        guard compatibleSourceEvidence(compatible.map(\.name)) else {
            return result(candidates, [], "incompatible_preparation_or_recipe")
        }
        return result(candidates, compatible, "compatible_source_family")
    }

    static func basis(scopedQuery: String, amount: GroundedAmount,
                      identities: [AUSNUTFoodIdentity]? = AustralianNutritionService.searchableIdentities,
                      resolver: GroundedEstimateEngine.Resolver = { ExistingFoodGrounder.resolve($0, amount: $1) }) -> GroundedEstimateBasis? {
        guard amount.isValid, amount.unit == .grams, let identities else { return nil }
        let assessment = assess(scopedQuery, identities: identities)
        guard !assessment.eligibleIDs.isEmpty else { return nil }
        var sources: [GroundedSourceResolution] = []
        for id in assessment.eligibleIDs {
            guard let source = resolver(.ausnut(id), amount), source.sourceID == .ausnut(id),
                  source.sourceType == .ausnut, source.sourceVersion?.isEmpty == false else { return nil }
            sources.append(source)
        }
        guard Set(sources.map(\.sourceID)).count == sources.count,
              Set(sources.map(\.sourceVersion)).count == 1,
              let envelope = GroundedNutritionEnvelope.enclosing(sources.map(\.nutrition)) else { return nil }
        return GroundedEstimateBasis(scopedQuery: scopedQuery, method: .scopedSourceEnvelope,
            candidates: sources, envelope: envelope,
            assumptions: ["Estimate retrieval: \(version)", "Interpreted scope: \(scopedQuery)",
                "Amount: \(amount.value) g (\(amount.provenance))"] + assessment.transformations,
            uncertainty: ["Source records are estimate evidence, not an exact identity.",
                "Only compatible retrieved source records are represented; population prevalence is unknown.",
                "Recipe/portion uncertainty remains outside this fixed-amount envelope."])
    }

    private static func tokens(_ value: String) -> [String] {
        value.lowercased().folding(options: .diacriticInsensitive, locale: Locale(identifier: "en_AU"))
            .replacingOccurrences(of: "[^a-z0-9><=]+", with: " ", options: .regularExpression)
            .split(separator: " ").map(String.init)
    }

    private static func canonicalFamily(_ name: String, canonical: (String) -> String) -> String {
        tokens(String(name.split(separator: ",").first ?? "")).map(canonical).joined(separator: " ")
    }

    /// Shared by both estimate discovery paths. Legacy identity candidates are
    /// not exempt from recipe/preparation safety merely because search found them.
    static func compatibleSourceEvidence(_ names: [String]) -> Bool {
        !names.isEmpty && Set(names.map { compatibilitySignature($0) }).count == 1
    }

    private static func compatibilitySignature(_ name: String) -> String {
        let words = Set(tokens(name))
        let preparation = words.intersection(preparationWords.union(["frozen", "canned", "toasted"]))
        let consequential = name.split(separator: ",").map { String($0).lowercased().trimmingCharacters(in: .whitespaces) }
            .filter { clause in
                let t = Set(tokens(clause))
                return !t.intersection(["added", "with", "filled", "reduced", "low", "skim", "syrup", "flavoured",
                    "marinated", "increased"]).isEmpty
            }.sorted()
        return preparation.sorted().joined(separator: "|") + ":" + consequential.joined(separator: "|")
    }
}

/// Amount adapter for validated evidence; exact conversions require independently
/// selected source/Measure ID. Provider edible grams remain estimated, never sourced.
enum GroundedAmountAdapter {
    struct Resolution: Sendable {
        let amount: GroundedAmount
        let original: FoodQuantityProposal?
        let measureID: Int?
        let assumptions: [String]
    }

    static func resolve(user: FoodQuantityProposal?, estimate: FoodQuantityProposal?,
                        exactIdentity: AUSNUTFoodIdentity? = nil, measureID: Int? = nil,
                        naturalUnit: String? = nil) -> Resolution? {
        func grams(_ value: Double, _ provenance: GroundedAmountProvenance, _ id: Int? = nil,
                   _ assumptions: [String] = []) -> Resolution? {
            guard value.isFinite, value > 0 else { return nil }
            return Resolution(amount: GroundedAmount(value: value, unit: .grams, provenance: provenance),
                original: user, measureID: id, assumptions: assumptions)
        }
        if let user {
            guard user.value.isFinite, user.value > 0 else { return nil }
            if user.unit == .grams, user.scope == .componentAmount { return grams(user.value, .user) }
            if user.unit == .millilitres, user.scope == .componentAmount {
                guard let exactIdentity, let basis = AUSNUTVolumeBasis.make(for: AUSNUTPortionPresentation.make(for: exactIdentity)),
                      let volume = basis.measure.sourceVolume else { return nil }
                return grams(user.value * basis.measure.sourceGrams / volume, .user, basis.measure.measureID,
                    ["Explicit mL converted only using agreeing measures of the exact source identity."])
            }
            if user.unit == .count, [.servingCount, .naturalPortion].contains(user.scope),
               let exactIdentity, let measureID, let naturalUnit {
                let matches = exactIdentity.measures.filter { $0.measureID == measureID }
                guard matches.count == 1, let m = matches.first, m.quantity > 0, m.quantity.isFinite else { return nil }
                let form = (m.descriptors?.first.flatMap { $0 } ?? m.name).lowercased()
                let unit = naturalUnit.lowercased()
                guard form == unit || form == unit + "s" || unit == form + "s" else { return nil }
                return grams(user.value * m.grams / m.quantity, .user, measureID,
                    ["User count scaled using explicitly selected source Measure ID."])
            }
            // Fraction/container/count can use a separate estimated edible amount;
            // total/unknown scope cannot. No guessed packet/container conversion.
            guard [.servingCount, .naturalPortion, .packageFraction].contains(user.scope) else { return nil }
        }
        guard let estimate, estimate.evidenceID == nil, estimate.originalText == nil,
              estimate.scope == .componentAmount, estimate.unit == .grams else { return nil }
        return grams(estimate.value, .estimated, nil, ["Edible grams are provider-estimated; original count/fraction retained."])
    }
}
