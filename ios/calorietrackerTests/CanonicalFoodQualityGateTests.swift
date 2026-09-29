import Foundation
import Testing
@testable import calorietracker

@Suite("Canonical food quality gate")
struct CanonicalFoodQualityGateTests {
    private let captured = Date(timeIntervalSince1970: 1_700_000_000)

    @Test func validGenericPerHundredGramsPasses() throws {
        let result = try assess([makeRecord()]).first
        #expect(result?.disposition == .pass)
        #expect(result?.publishableRecord?.displayName == "Synthetic food")
        #expect(result?.candidate.rawEvidence == Data("original input".utf8))
    }

    @Test func validExactRestaurantServingPasses() throws {
        let serving = CanonicalFoodRecord.Serving(
            label: "1 item", quantity: 1, unit: "item", gramsOrMillilitres: nil, pieceCount: nil
        )
        let result = try assess([makeRecord(kind: .restaurant, basis: .exactServing, serving: serving)]).first
        #expect(result?.disposition == .pass)
    }

    @Test func validBrandedGTINServingPasses() throws {
        let serving = CanonicalFoodRecord.Serving(
            label: "1 bar", quantity: 1, unit: "bar", gramsOrMillilitres: 45, pieceCount: 1
        )
        let result = try assess([makeRecord(kind: .branded, gtin: "9300000000001", basis: .exactServing, serving: serving)]).first
        #expect(result?.disposition == .pass)
    }

    @Test func energyMismatchQuarantinesWithoutPublishing() throws {
        let result = try assess([makeRecord(kilojoules: 1_000)]).first
        #expect(result?.disposition == .quarantine)
        #expect(result?.reasons.contains(.energyMismatch) == true)
        #expect(result?.publishableRecord == nil)
        #expect(result?.candidate.rawEvidence == Data("original input".utf8))
    }

    @Test func ambiguousServingBasisQuarantines() throws {
        let result = try assess([makeRecord(basis: .exactServing)]).first
        #expect(result?.disposition == .quarantine)
        #expect(result?.reasons.contains(.ambiguousServingBasis) == true)
    }

    @Test func conflictingGTINQuarantinesBoth() throws {
        let results = try assess([
            makeRecord(id: "first", name: "First bar", kind: .branded, gtin: "9300000000001"),
            makeRecord(id: "second", name: "Second bar", kind: .branded, gtin: "9300000000001")
        ])
        #expect(results.count == 2)
        #expect(results.allSatisfy { $0.disposition == .quarantine && $0.reasons.contains(.conflictingGTIN) })
    }

    @Test func sameGTINAndNameWithDifferentNutritionQuarantinesBoth() throws {
        let results = try assess([
            makeRecord(id: "first", name: "Same bar", kind: .branded, gtin: "9300000000001"),
            makeRecord(id: "second", name: "Same bar", kind: .branded, gtin: "9300000000001", kcal: 120)
        ])
        #expect(results.allSatisfy { $0.disposition == .quarantine && $0.reasons.contains(.conflictingGTIN) })
    }

    @Test func staleVersionAndSourceMismatchQuarantine() throws {
        let results = try assess([
            makeRecord(id: "stale", version: "v2"),
            makeRecord(id: "wrong-market", market: "US")
        ])
        #expect(results[0].disposition == .quarantine)
        #expect(results[0].reasons.contains(.staleSourceVersion))
        #expect(results[1].disposition == .quarantine)
        #expect(results[1].reasons.contains(.sourceConflict))
    }

    @Test func negativeAndNonfiniteNutritionReject() throws {
        let results = try assess([
            makeRecord(id: "negative", protein: -1),
            makeRecord(id: "infinite", kcal: .infinity)
        ])
        #expect(results.allSatisfy { $0.disposition == .reject && $0.reasons.contains(.invalidNutrition) })
    }

    @Test func zeroConversionAndInvalidUnitReject() throws {
        let results = try assess([
            makeRecord(id: "zero", serving: .init(label: "item", quantity: 1, unit: "item", gramsOrMillilitres: 0, pieceCount: nil)),
            makeRecord(id: "unit", serving: .init(label: "item", quantity: 1, unit: "", gramsOrMillilitres: 10, pieceCount: nil))
        ])
        #expect(results.allSatisfy { $0.disposition == .reject && $0.reasons.contains(.invalidServing) })
    }

    @Test func missingProvenanceAndMalformedRecordReject() throws {
        let results = try assess([
            makeRecord(id: "missing-provenance", provenanceSourceID: "wrong.source"),
            makeRecord(id: "malformed", name: "  ")
        ])
        #expect(results[0].disposition == .reject)
        #expect(results[0].reasons.contains(.missingProvenance))
        #expect(results[1].disposition == .reject)
        #expect(results[1].reasons.contains(.malformedIdentity))
    }

    @Test func incompatibleDuplicateNamespacedIdentityRejectsBoth() throws {
        let results = try assess([
            makeRecord(id: "duplicate", name: "First identity"),
            makeRecord(id: "duplicate", name: "Incompatible identity")
        ])
        #expect(results.allSatisfy { $0.disposition == .reject && $0.reasons.contains(.duplicateIdentity) })
    }

    @Test func sourceWithoutPublicationRightsRejects() throws {
        let result = try assess([makeRecord()], bundling: .prohibited, remoteQuery: .prohibited).first
        #expect(result?.disposition == .reject)
        #expect(result?.reasons.contains(.unapprovedSource) == true)
        #expect(result?.publishableRecord == nil)
    }

    private func assess(
        _ records: [CanonicalFoodRecord],
        bundling: FoodSourceRegistry.Permission = .permitted,
        remoteQuery: FoodSourceRegistry.Permission = .prohibited
    ) throws -> [CanonicalFoodQualityGate.Assessment] {
        let source = FoodSourceRegistry.Source(
            sourceID: "synthetic.source", sourceName: "Synthetic source", sourceOwner: "Synthetic owner",
            market: "AU", sourceType: .governmentComposition, identityAuthority: .authoritative,
            nutritionAuthority: .authoritative, officialURL: URL(string: "https://example.invalid/source"),
            legalBasisReference: "Synthetic licence", attributionRequirement: "Synthetic attribution",
            redistribution: .permitted, bundling: bundling, remoteQuery: remoteQuery,
            retrievedAt: captured, datasetVersion: "v1", effectiveDate: captured,
            parserVersion: "parser-1", sourceChecksum: "sha256:synthetic", updateCadence: "Annual",
            upstreamIdentityType: "synthetic-id", restrictions: "Test only",
            approval: .approved, approvalOwner: "Test approver", approvedAt: captured
        )
        let registry = try FoodSourceRegistry(sources: [source])
        return CanonicalFoodQualityGate().assess(
            records.map { CanonicalFoodCandidate(record: $0, rawEvidence: Data("original input".utf8)) },
            registry: registry
        )
    }

    private func makeRecord(
        id: String = "synthetic-1",
        name: String = "Synthetic food",
        kind: CanonicalFoodRecord.Kind = .generic,
        gtin: String? = nil,
        basis: CanonicalFoodRecord.NutritionBasis = .per100g,
        serving: CanonicalFoodRecord.Serving? = nil,
        kcal: Double = 100,
        kilojoules: Double? = 418,
        protein: Double = 5,
        market: String = "AU",
        version: String = "v1",
        provenanceSourceID: String = "synthetic.source"
    ) -> CanonicalFoodRecord {
        CanonicalFoodRecord(
            sourceID: "synthetic.source", upstreamRecordID: id, sourceVersion: version,
            market: market, kind: kind, displayName: name, brandOrChain: kind == .generic ? nil : "Synthetic brand",
            variant: nil, gtin: gtin, category: nil,
            nutrition: .init(
                basis: basis, kcal: kcal, kilojoules: kilojoules, protein: protein,
                carbs: 10, fat: 4, fibre: nil, sugars: nil, sodium: nil
            ),
            serving: serving,
            provenance: .init(
                sourceID: provenanceSourceID, sourceVersion: version, upstreamRecordID: id,
                retrievedAt: captured, effectiveDate: nil, parserVersion: "parser-1",
                sourceChecksum: "sha256:synthetic", nutritionAuthority: .authoritative
            )
        )
    }
}
