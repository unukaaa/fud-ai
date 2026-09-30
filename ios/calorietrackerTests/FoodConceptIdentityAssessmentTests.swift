import Foundation
import Testing
@testable import calorietracker

struct FoodConceptIdentityAssessmentTests {
    private func ausnut() throws -> AUSNUTFoodSearchIndex {
        try #require(AUSNUTFoodSearchIndex.bundled())
    }

    @Test func scopedAppleNFDCanDefaultRawAppleButNotBareApple() throws {
        let index = try ausnut()
        let raw = index.assessIdentity("raw apple")
        #expect(raw.state == .defaultable)
        #expect(raw.defaultSourceID == "ausnut:16101015")
        #expect(raw.nfdSourceID == "ausnut:16101015")
        #expect(raw.reason == .scopedNFD)
        #expect(raw.optionalRefinementAvailable)
        #expect(raw.candidateSourceIDs.contains("ausnut:16101008")) // Pink Lady, raw
        #expect(!raw.candidateSourceIDs.contains("ausnut:16802002")) // dried
        #expect(!raw.candidateSourceIDs.contains("ausnut:16101017")) // stewed

        let bare = index.assessIdentity("apple")
        #expect(bare.defaultSourceID == nil)
        #expect(bare.state == .unknownVariant)
    }

    @Test func directDarkChocolateKeepsBothSourceBackedCocoaIdentities() throws {
        let index = try ausnut()
        let dark = index.assessIdentity("dark chocolate")
        #expect(dark.defaultSourceID == nil)
        #expect(dark.state != .noTrustedMatch)
        #expect(dark.candidateSourceIDs.contains("ausnut:28101001"))
        #expect(dark.candidateSourceIDs.contains("ausnut:28101002"))
        #expect(!dark.candidateSourceIDs.contains("ausnut:28101004"))
        #expect(Set(dark.candidateSourceIDs).isSubset(of: Set(index.assessIdentity("chocolate").candidateSourceIDs)))
    }

    @Test func bananaCannotInheritCavendishNutritionFromSearchOrder() throws {
        let assessment = try ausnut().assessIdentity("banana")
        #expect(assessment.state == .unknownVariant)
        #expect(assessment.defaultSourceID == nil)
        #expect(assessment.nfdSourceID == nil)
        #expect(assessment.candidateSourceIDs.contains("ausnut:16502001"))
        #expect(assessment.candidateSourceIDs.contains("ausnut:16502002"))
        #expect(!assessment.optionalRefinementAvailable)
    }

    @Test func nfdWordingNeverEscapesItsSourceScope() throws {
        let index = try ausnut()
        for bare in ["milk", "bread", "cheese", "tuna"] {
            #expect(index.assessIdentity(bare).defaultSourceID == nil)
        }
        #expect(index.assessIdentity("milk cow fluid unflavoured").defaultSourceID == "ausnut:19108003")
        #expect(index.assessIdentity("bread commercial").defaultSourceID == "ausnut:12201032")
        #expect(index.assessIdentity("cheese soft white mould coated").defaultSourceID == "ausnut:19405004")
        #expect(index.assessIdentity("tuna canned").defaultSourceID == "ausnut:15401020")
    }

    @Test func preparationAndVariantFamiliesRemainUnresolved() throws {
        let index = try ausnut()
        for query in ["egg chicken whole", "rice white", "chicken breast", "pasta white"] {
            let result = index.assessIdentity(query)
            #expect(result.state == .clarificationRequired)
            #expect(result.defaultSourceID == nil)
            #expect(result.unresolvedDimensions.contains(.preparation))
            #expect(result.candidateSourceIDs.count > 1)
        }
        for query in ["milk", "chicken", "chocolate", "rice", "egg"] {
            let result = index.assessIdentity(query)
            #expect(result.defaultSourceID == nil)
            #expect(result.state == .unknownVariant)
        }
        let chocolate = index.assessIdentity("chocolate")
        #expect(chocolate.candidateSourceIDs.contains("ausnut:28101004")) // milk
        #expect(chocolate.candidateSourceIDs.contains("ausnut:28101001")) // dark
    }

    @Test func exactSourceNameIsItsOwnIdentityNotAConceptGuess() throws {
        let index = try ausnut()
        let cavendish = index.assessIdentity("Banana, cavendish, peeled, raw")
        #expect(cavendish.state == .defaultable)
        #expect(cavendish.defaultSourceID == "ausnut:16502001")
        #expect(cavendish.reason == .exactSourceName)
        #expect(!cavendish.optionalRefinementAvailable)
        #expect(index.assessIdentity("food that is not in the bundle").state == .noTrustedMatch)
    }

    @Test func aSingleNamedVariantIsNotEvidenceOfAnUnspecifiedDefault() {
        let onlyVariant = AUSNUTFoodIdentity(id: "one", name: "Examplefruit, red cultivar", measures: [])
        let index = AUSNUTFoodSearchIndex(identities: [onlyVariant])
        let result = index.assessIdentity("examplefruit")
        #expect(result.defaultSourceID == nil)
        #expect(result.state == .noTrustedMatch)
    }

    @Test func restaurantAndBrandIdentitiesDoNotCollapseIntoGenericFoods() throws {
        let index = UnifiedFoodSearchIndex(
            restaurants: try #require(RestaurantFoodSearchIndex.bundled()),
            ausnut: try ausnut()
        )
        #expect(index.assessIdentity("Big Mac").defaultSourceID == "restaurant:item:mcd-au-big-mac")
        #expect(index.assessIdentity("Zinger").defaultSourceID == "restaurant:item:kfc-au-zinger-burger")
        #expect(index.assessIdentity("Coca-Cola Zero Sugar").defaultSourceID
                == "restaurant:item:mcd-au-coke-zero-sugar")
        #expect(index.assessIdentity("KFC").defaultSourceID == nil)
        #expect(index.assessIdentity("Coke").defaultSourceID == nil)
        #expect(index.assessIdentity("cola").defaultSourceID == nil)
    }

    @Test func fullBundledIdentityAuditHasNoUnsupportedNamedVariantDefaults() throws {
        let identities = try #require(AustralianNutritionService.searchableIdentities)
        let index = try ausnut()
        #expect(identities.count == 3_741)
        let nfdCount = identities.filter { $0.name.localizedCaseInsensitiveContains("not further defined") }.count
        var states: [FoodConceptIdentityAssessment.State: Int] = [:]
        var unsupportedDefaults = 0
        var errors = 0
        for identity in identities {
            let result = index.assessIdentity(identity.name)
            states[result.state, default: 0] += 1
            if let defaultID = result.defaultSourceID {
                if result.reason != .exactSourceName || defaultID != "ausnut:\(identity.id)" {
                    unsupportedDefaults += 1
                }
            } else if result.candidateSourceIDs.contains("ausnut:\(identity.id)") == false {
                errors += 1
            }
        }
        #expect(nfdCount == 52)
        #expect(unsupportedDefaults == 0)
        #expect(errors == 0)
        print("FOOD_CONCEPT_FULL_AUDIT records=\(identities.count) nfd=\(nfdCount) states=\(states) unsupportedDefaults=\(unsupportedDefaults) errors=\(errors)")

        let familyHeads = Set(identities.map {
            String($0.name.split(separator: ",", maxSplits: 1).first ?? Substring($0.name))
        })
        var familyStates: [FoodConceptIdentityAssessment.State: Int] = [:]
        var unsupportedFamilyDefaults = 0
        for head in familyHeads {
            let result = index.assessIdentity(head)
            familyStates[result.state, default: 0] += 1
            if let defaultID = result.defaultSourceID {
                let source = identities.first { "ausnut:\($0.id)" == defaultID }
                if source == nil || (result.reason != .exactSourceName && result.reason != .scopedNFD) {
                    unsupportedFamilyDefaults += 1
                }
            }
        }
        #expect(unsupportedFamilyDefaults == 0)
        print("FOOD_CONCEPT_FAMILY_AUDIT heads=\(familyHeads.count) states=\(familyStates) unsupportedDefaults=\(unsupportedFamilyDefaults)")
    }

    @Test func representativeQueriesNeverProduceWrongConfidentIdentity() throws {
        let index = UnifiedFoodSearchIndex(
            restaurants: try #require(RestaurantFoodSearchIndex.bundled()),
            ausnut: try ausnut()
        )
        let cases: [(String, FoodConceptIdentityAssessment.State)] = [
            ("Apple, raw, not further defined", .defaultable),
            ("raw apple", .defaultable),
            ("apple", .unknownVariant), ("banana", .unknownVariant),
            ("egg", .unknownVariant), ("milk", .unknownVariant),
            ("rice", .unknownVariant), ("chicken", .unknownVariant),
            ("chicken breast", .clarificationRequired),
            ("bread", .unknownVariant), ("cheese", .unknownVariant),
            ("tuna", .unknownVariant), ("pasta white", .clarificationRequired),
            ("chocolate", .unknownVariant), ("Big Mac", .defaultable),
            ("Coca-Cola Zero Sugar", .defaultable),
            ("food that is not in the bundle", .noTrustedMatch)
        ]
        var stateCounts: [FoodConceptIdentityAssessment.State: Int] = [:]
        var wrongConfident = 0
        for (query, expected) in cases {
            let result = index.assessIdentity(query)
            #expect(result.state == expected, "\(query): \(result)")
            stateCounts[result.state, default: 0] += 1
            if result.state == .defaultable && result.defaultSourceID == nil { wrongConfident += 1 }
        }
        #expect(wrongConfident == 0)
        print("FOOD_CONCEPT_BENCHMARK queries=\(cases.count) states=\(stateCounts) wrongConfident=\(wrongConfident)")
    }

    @Test func bundledRestaurantNamesDoNotSilentlyBecomeOtherSourceIdentities() throws {
        let store = try #require(RestaurantDatasetStore.bundled())
        let index = UnifiedFoodSearchIndex(
            restaurants: RestaurantFoodSearchIndex(store: store), ausnut: try ausnut()
        )
        var crossSourceCollisions = 0
        var wrongDefaults = 0
        for item in store.dataset.menuItems {
            let result = index.assessIdentity(item.name)
            if result.reason == .crossSourceCollision { crossSourceCollisions += 1 }
            if let defaultID = result.defaultSourceID,
               defaultID != "restaurant:item:\(item.id)" { wrongDefaults += 1 }
        }
        #expect(wrongDefaults == 0)
        print("FOOD_CONCEPT_RESTAURANT_AUDIT items=\(store.dataset.menuItems.count) crossSourceCollisions=\(crossSourceCollisions) wrongDefaults=\(wrongDefaults)")
    }
}
