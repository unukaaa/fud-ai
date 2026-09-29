import Foundation
import Testing
@testable import calorietracker

@Suite("Food source registry")
struct FoodSourceRegistryTests {
    private let captured = Date(timeIntervalSince1970: 1_700_000_000)

    @Test func approvedGovernmentSourceCanBundle() throws {
        let source = makeSource()
        let registry = try FoodSourceRegistry(sources: [source])

        #expect(registry.source(id: "synthetic.gov") == source)
        #expect(source.hasPublicationApproval)
        #expect(source.canBundle)
        #expect(!source.canQueryRemotely)
    }

    @Test func blockedRestaurantSourceCannotPublish() {
        let source = makeSource(
            sourceType: .firstPartyRestaurant,
            authority: .firstParty,
            approval: .blocked
        )

        #expect(!source.hasPublicationApproval)
        #expect(!source.canBundle)
        #expect(!source.canQueryRemotely)
    }

    @Test func legalReviewCommunitySourceCannotPublish() {
        let source = makeSource(
            sourceType: .communityProduct,
            authority: .community,
            approval: .legalReviewRequired
        )

        #expect(!source.hasPublicationApproval)
        #expect(!source.canBundle)
    }

    @Test func missingLegalOrProvenanceFieldFailsClosed() {
        let noLegalBasis = makeSource(legalBasis: nil)
        let noAttributionDecision = makeSource(attribution: nil)
        let noChecksum = makeSource(checksum: nil)

        #expect(!noLegalBasis.hasPublicationApproval)
        #expect(!noAttributionDecision.canBundle)
        #expect(!noChecksum.canBundle)
    }

    @Test func remoteOnlyCommercialSourceCannotBundle() {
        let source = makeSource(
            sourceType: .commercialProduct,
            authority: .contractual,
            redistribution: .prohibited,
            bundling: .prohibited,
            remoteQuery: .permitted
        )

        #expect(source.hasPublicationApproval)
        #expect(source.canQueryRemotely)
        #expect(!source.canBundle)
    }

    @Test func versionAndChecksumBothBindSourceIdentity() {
        let original = makeSource()
        let changedVersion = makeSource(version: "v2")
        let changedChecksum = makeSource(checksum: "sha256:changed")

        #expect(original.versionedIdentity != changedVersion.versionedIdentity)
        #expect(original.versionedIdentity != changedChecksum.versionedIdentity)
        #expect(makeSource(checksum: nil).versionedIdentity == nil)
    }

    @Test func duplicateSourceIDIsRejected() {
        #expect(throws: FoodSourceRegistry.RegistryError.self) {
            _ = try FoodSourceRegistry(sources: [makeSource(), makeSource(version: "v2")])
        }
    }

    private func makeSource(
        sourceType: FoodSourceRegistry.SourceType = .governmentComposition,
        authority: FoodSourceRegistry.Authority = .authoritative,
        approval: FoodSourceRegistry.Approval = .approved,
        legalBasis: String? = "Synthetic licence reference",
        attribution: String? = "Synthetic attribution requirement",
        redistribution: FoodSourceRegistry.Permission = .permitted,
        bundling: FoodSourceRegistry.Permission = .permitted,
        remoteQuery: FoodSourceRegistry.Permission = .prohibited,
        version: String? = "v1",
        checksum: String? = "sha256:synthetic"
    ) -> FoodSourceRegistry.Source {
        FoodSourceRegistry.Source(
            sourceID: "synthetic.gov",
            sourceName: "Synthetic source",
            sourceOwner: "Synthetic owner",
            market: "AU",
            sourceType: sourceType,
            identityAuthority: authority,
            nutritionAuthority: authority,
            officialURL: URL(string: "https://example.invalid/source"),
            legalBasisReference: legalBasis,
            attributionRequirement: attribution,
            redistribution: redistribution,
            bundling: bundling,
            remoteQuery: remoteQuery,
            retrievedAt: captured,
            datasetVersion: version,
            effectiveDate: captured,
            parserVersion: "parser-1",
            sourceChecksum: checksum,
            updateCadence: "Annual",
            upstreamIdentityType: "synthetic-id",
            restrictions: "Test fixture only",
            approval: approval,
            approvalOwner: "Test approver",
            approvedAt: captured
        )
    }
}
