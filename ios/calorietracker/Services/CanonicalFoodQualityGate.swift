import Foundation

/// A small ingestion boundary; this is not a diary entry or a search result.
nonisolated struct CanonicalFoodRecord: Sendable {
    nonisolated enum Kind: Equatable, Sendable { case generic, branded, restaurant }
    nonisolated enum NutritionBasis: Equatable, Sendable { case per100g, per100mL, exactServing }

    nonisolated struct Nutrition: Sendable {
        let basis: NutritionBasis
        let kcal: Double?
        let kilojoules: Double?
        let protein: Double?
        let carbs: Double?
        let fat: Double?
        let fibre: Double?
        let sugars: Double?
        let sodium: Double?

        var values: [Double] {
            [kcal, kilojoules, protein, carbs, fat, fibre, sugars, sodium].compactMap { $0 }
        }
    }

    nonisolated struct Serving: Sendable {
        let label: String
        let quantity: Double
        let unit: String
        let gramsOrMillilitres: Double?
        let pieceCount: Int?
    }

    nonisolated struct Provenance: Sendable {
        let sourceID: String
        let sourceVersion: String
        let upstreamRecordID: String
        let retrievedAt: Date?
        let effectiveDate: Date?
        let parserVersion: String
        let sourceChecksum: String
        let nutritionAuthority: FoodSourceRegistry.Authority
    }

    let sourceID: String
    let upstreamRecordID: String
    let sourceVersion: String
    let market: String
    let kind: Kind
    let displayName: String
    let brandOrChain: String?
    let variant: String?
    let gtin: String?
    let category: String?
    let nutrition: Nutrition
    let serving: Serving?
    let provenance: Provenance

    var namespacedKey: String { "\(sourceID):\(upstreamRecordID):\(sourceVersion)" }
}

nonisolated struct CanonicalFoodCandidate: Sendable {
    let record: CanonicalFoodRecord
    /// Original input is retained for quarantine review, never silently rewritten by AI.
    let rawEvidence: Data
}

nonisolated struct CanonicalFoodQualityGate {
    nonisolated enum Disposition: Equatable { case pass, quarantine, reject }

    nonisolated enum Reason: Hashable {
        case missingProvenance
        case unapprovedSource
        case malformedIdentity
        case invalidNutrition
        case invalidServing
        case ambiguousServingBasis
        case energyMismatch
        case macroEnergyMismatch
        case staleSourceVersion
        case sourceConflict
        case duplicateIdentity
        case conflictingGTIN
    }

    nonisolated struct Assessment {
        let disposition: Disposition
        let reasons: Set<Reason>
        let candidate: CanonicalFoodCandidate

        /// Only PASS records may be published to a future search index.
        var publishableRecord: CanonicalFoodRecord? {
            disposition == .pass ? candidate.record : nil
        }
    }

    func assess(
        _ candidates: [CanonicalFoodCandidate],
        registry: FoodSourceRegistry
    ) -> [Assessment] {
        let indexed = Dictionary(grouping: candidates.indices, by: { candidates[$0].record.namespacedKey })
        let gtins = Dictionary(grouping: candidates.indices.compactMap { index -> (String, Int)? in
            guard let gtin = candidates[index].record.gtin, !gtin.isEmpty else { return nil }
            return (gtin, index)
        }, by: { $0.0 })

        return candidates.indices.map { index in
            let candidate = candidates[index]
            let record = candidate.record
            var rejected = Set<Reason>()
            var quarantined = Set<Reason>()

            let source = registry.source(id: record.sourceID)
            if source?.hasPublicationApproval != true
                || (source?.canBundle != true && source?.canQueryRemotely != true) {
                rejected.insert(.unapprovedSource)
            }
            if record.sourceID.isEmpty || record.upstreamRecordID.isEmpty || record.sourceVersion.isEmpty
                || record.market.isEmpty || record.displayName.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty
                || candidate.rawEvidence.isEmpty {
                rejected.insert(.malformedIdentity)
            }
            let provenance = record.provenance
            if provenance.sourceID != record.sourceID || provenance.upstreamRecordID != record.upstreamRecordID
                || provenance.sourceVersion != record.sourceVersion || provenance.retrievedAt == nil
                || provenance.parserVersion.isEmpty || provenance.sourceChecksum.isEmpty {
                rejected.insert(.missingProvenance)
            }
            if let source {
                if record.market != source.market || provenance.nutritionAuthority != source.nutritionAuthority {
                    quarantined.insert(.sourceConflict)
                }
                if record.sourceVersion != source.datasetVersion || provenance.parserVersion != source.parserVersion
                    || provenance.sourceChecksum != source.sourceChecksum {
                    quarantined.insert(.staleSourceVersion)
                }
            }

            let nutrition = record.nutrition
            if nutrition.values.contains(where: { !$0.isFinite || $0 < 0 })
                || (nutrition.kcal == nil && nutrition.kilojoules == nil) {
                rejected.insert(.invalidNutrition)
            }
            if let serving = record.serving {
                if serving.label.isEmpty || serving.unit.isEmpty || !serving.quantity.isFinite
                    || serving.quantity <= 0 || serving.gramsOrMillilitres.map({ !$0.isFinite || $0 <= 0 }) == true
                    || serving.pieceCount.map({ $0 <= 0 }) == true {
                    rejected.insert(.invalidServing)
                }
            } else if nutrition.basis == .exactServing {
                quarantined.insert(.ambiguousServingBasis)
            }

            if let kcal = nutrition.kcal, let kilojoules = nutrition.kilojoules,
               kcal.isFinite, kilojoules.isFinite, kcal >= 0, kilojoules >= 0,
               abs(kilojoules - kcal * 4.184) > max(20, kilojoules * 0.12) {
                quarantined.insert(.energyMismatch)
            }
            if let kcal = nutrition.kcal, let protein = nutrition.protein,
               let carbs = nutrition.carbs, let fat = nutrition.fat,
               [kcal, protein, carbs, fat].allSatisfy({ $0.isFinite && $0 >= 0 }),
               abs(kcal - (protein * 4 + carbs * 4 + fat * 9)) > max(35, kcal * 0.35) {
                quarantined.insert(.macroEnergyMismatch)
            }

            if let peers = indexed[record.namespacedKey], peers.count > 1,
               peers.contains(where: { other in
                   let peer = candidates[other].record
                   return peer.displayName != record.displayName || peer.kind != record.kind || peer.gtin != record.gtin
               }) {
                rejected.insert(.duplicateIdentity)
            }
            if let gtin = record.gtin, let peers = gtins[gtin], peers.count > 1,
               peers.contains(where: { pair in
                   let peer = candidates[pair.1].record
                   return peer.namespacedKey != record.namespacedKey
                       && (peer.displayName != record.displayName || peer.brandOrChain != record.brandOrChain
                           || peer.nutrition.kcal != record.nutrition.kcal
                           || peer.nutrition.kilojoules != record.nutrition.kilojoules
                           || peer.nutrition.protein != record.nutrition.protein
                           || peer.nutrition.carbs != record.nutrition.carbs
                           || peer.nutrition.fat != record.nutrition.fat)
               }) {
                quarantined.insert(.conflictingGTIN)
            }

            let disposition: Disposition = !rejected.isEmpty ? .reject : (!quarantined.isEmpty ? .quarantine : .pass)
            return Assessment(
                disposition: disposition,
                reasons: rejected.union(quarantined),
                candidate: candidate
            )
        }
    }
}
