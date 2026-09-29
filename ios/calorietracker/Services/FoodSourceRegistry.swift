import Foundation

/// Source governance metadata only. A registry entry contains no food or nutrition records.
nonisolated struct FoodSourceRegistry: Sendable {
    nonisolated enum SourceType: String, Codable, Sendable {
        case governmentComposition
        case firstPartyRestaurant
        case commercialProduct
        case communityProduct
    }

    nonisolated enum Authority: String, Codable, Sendable {
        case authoritative
        case firstParty
        case contractual
        case community
    }

    nonisolated enum Approval: String, Codable, Sendable {
        case approved
        case pilotOnly
        case blocked
        case legalReviewRequired
        case partnerRequired
    }

    nonisolated enum Permission: String, Codable, Sendable {
        case permitted
        case prohibited
        case unresolved
    }

    nonisolated struct Source: Codable, Hashable, Sendable {
        let sourceID: String
        let sourceName: String
        let sourceOwner: String
        let market: String
        let sourceType: SourceType
        let identityAuthority: Authority
        let nutritionAuthority: Authority
        let officialURL: URL?
        let legalBasisReference: String?
        let attributionRequirement: String?
        let redistribution: Permission
        let bundling: Permission
        let remoteQuery: Permission
        let retrievedAt: Date?
        let datasetVersion: String?
        let effectiveDate: Date?
        let parserVersion: String?
        let sourceChecksum: String?
        let updateCadence: String?
        let upstreamIdentityType: String?
        let restrictions: String?
        let approval: Approval
        let approvalOwner: String?
        let approvedAt: Date?

        var versionedIdentity: String? {
            guard let version = nonempty(datasetVersion), let checksum = nonempty(sourceChecksum) else {
                return nil
            }
            return "\(sourceID):\(version):\(checksum)"
        }

        /// Missing metadata is not permission. Pilot and review states cannot publish.
        var hasPublicationApproval: Bool {
            approval == .approved
                && nonempty(sourceID) != nil
                && nonempty(sourceName) != nil
                && nonempty(sourceOwner) != nil
                && nonempty(market) != nil
                && officialURL?.scheme?.lowercased() == "https"
                && nonempty(legalBasisReference) != nil
                && nonempty(attributionRequirement) != nil
                && retrievedAt != nil
                && versionedIdentity != nil
                && nonempty(parserVersion) != nil
                && nonempty(upstreamIdentityType) != nil
                && nonempty(approvalOwner) != nil
                && approvedAt != nil
        }

        var canBundle: Bool {
            hasPublicationApproval && redistribution == .permitted && bundling == .permitted
        }

        var canQueryRemotely: Bool {
            hasPublicationApproval && remoteQuery == .permitted
        }

        private func nonempty(_ value: String?) -> String? {
            guard let trimmed = value?.trimmingCharacters(in: .whitespacesAndNewlines), !trimmed.isEmpty else {
                return nil
            }
            return trimmed
        }
    }

    private let sourcesByID: [String: Source]

    init(sources: [Source]) throws {
        var indexed: [String: Source] = [:]
        for source in sources {
            guard !source.sourceID.isEmpty, indexed[source.sourceID] == nil else {
                throw RegistryError.duplicateOrMissingSourceID
            }
            indexed[source.sourceID] = source
        }
        sourcesByID = indexed
    }

    func source(id: String) -> Source? { sourcesByID[id] }

    nonisolated enum RegistryError: Error {
        case duplicateOrMissingSourceID
    }
}
