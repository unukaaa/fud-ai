import Foundation
import Testing
@testable import calorietracker

struct FoodConceptSearchRouteTests {
    private func index() throws -> UnifiedFoodSearchIndex {
        UnifiedFoodSearchIndex(restaurants: try #require(RestaurantFoodSearchIndex.bundled()),
                               ausnut: try #require(AUSNUTFoodSearchIndex.bundled()))
    }

    @Test func scopedAppleUsesItsNFDAndRefinementDoesNotBlock() throws {
        let route = FoodConceptSearchRoute(try index().assessIdentity("raw apple"))
        guard case .sourced(let sourceID, let refinements) = route else {
            Issue.record("Expected a source-backed raw-apple default")
            return
        }
        #expect(sourceID == "ausnut:16101015")
        #expect(refinements.contains("ausnut:16101008"))
        #expect(!refinements.contains("ausnut:16802002"))
    }

    @Test func bananaRemainsUnresolvedUntilVarietyOrExplicitEstimate() throws {
        let route = FoodConceptSearchRoute(try index().assessIdentity("banana"))
        guard case .unknownVariant(let query, let alternatives) = route else {
            Issue.record("Banana must not silently become a named variety")
            return
        }
        #expect(query == "banana")
        #expect(alternatives.contains("ausnut:16502001"))
        #expect(alternatives.contains("ausnut:16502002"))
        var state = FoodConceptChoiceState.discovery
        #expect(state.explicitEstimateQuery == nil)
        state.notSure(about: route)
        #expect(state == .unresolved("banana"))
        #expect(state.explicitEstimateQuery == "banana")
        #expect(route.allowsExplicitEstimate)
    }

    @Test func preparationAndTypeAmbiguityNeverSelectAnUnsupportedDefault() throws {
        let index = try index()
        for query in ["milk", "rice", "chicken", "chocolate", "egg", "pasta"] {
            let route = FoodConceptSearchRoute(index.assessIdentity(query))
            if case .sourced(let sourceID, _) = route {
                Issue.record("Unexpected sourced default for \(query): \(sourceID)")
            }
            #expect(!route.candidateSourceIDs.isEmpty)
        }
        let prepared = FoodConceptSearchRoute(index.assessIdentity("chicken breast"))
        guard case .clarification(let candidates) = prepared else {
            Issue.record("Chicken breast requires a preparation choice")
            return
        }
        #expect(candidates.count > 1)
    }

    @Test func brandedAndRestaurantExactIDsAreNotGenericized() throws {
        let index = try index()
        let bigMac = FoodConceptSearchRoute(index.assessIdentity("Big Mac"))
        #expect(bigMac == .sourced("restaurant:item:mcd-au-big-mac", refinements: []))
        let cokeZero = FoodConceptSearchRoute(index.assessIdentity("Coca-Cola Zero Sugar"))
        #expect(cokeZero == .sourced("restaurant:item:mcd-au-coke-zero-sugar", refinements: []))
        for query in ["Coke", "cola", "Zinger"] {
            let route = FoodConceptSearchRoute(index.assessIdentity(query))
            if case .sourced(let sourceID, _) = route {
                #expect(!sourceID.hasPrefix("ausnut:"))
            }
        }
    }

    @Test func aiOnlyAfterNoTrustedMatchAndErrorsAreConsumerSafe() throws {
        let query = "food that is not in the bundle"
        #expect(FoodConceptSearchRoute(try index().assessIdentity(query)) == .analyse(query))
        let message = try #require(SearchFoodAIUnavailableMessage.message(
            for: GeminiService.AnalysisError.noAPIKey))
        #expect(message.contains("AI estimate is currently unavailable"))
        #expect(!message.localizedCaseInsensitiveContains("API key"))
        #expect(!message.localizedCaseInsensitiveContains("Settings"))
    }

    @Test func weakSourcedResultsAreOfferedBeforeExplicitEstimate() throws {
        let index = try index()
        let query = "Coke"
        let route = FoodConceptSearchRoute(index.assessIdentity(query),
                                           suggestions: index.search(query, limit: 5))
        guard case .weakAlternatives(let original, let sourceIDs) = route else {
            Issue.record("Expected sourced alternatives without a confident Coke identity")
            return
        }
        #expect(original == query)
        #expect(!sourceIDs.isEmpty)
        #expect(sourceIDs.allSatisfy { $0.hasPrefix("restaurant:") })
        #expect(route.isWeakAlternative)
        #expect(!route.allowsExplicitEstimate) // This flag is the unknown-variant Not sure route.
    }

    @Test func representativeRoutingBenchmarkKeepsSourceTruth() throws {
        let index = try index()
        let expected: [(String, String)] = [
            ("raw apple", "ausnut:16101015"),
            ("Banana, cavendish, peeled, raw", "ausnut:16502001"),
            ("Big Mac", "restaurant:item:mcd-au-big-mac"),
            ("Zinger", "restaurant:item:kfc-au-zinger-burger"),
            ("Coca-Cola Zero Sugar", "restaurant:item:mcd-au-coke-zero-sugar")
        ]
        var wrongConfident = 0
        var sourced = 0
        var unresolved = 0
        var aiFallback = 0
        for (query, expectedID) in expected {
            let route = FoodConceptSearchRoute(index.assessIdentity(query),
                                               suggestions: index.search(query, limit: 5))
            if case .sourced(let actualID, _) = route {
                sourced += 1
                if actualID != expectedID { wrongConfident += 1 }
            } else {
                Issue.record("Expected exact sourced route for \(query)")
            }
        }
        for query in ["apple", "banana", "milk", "rice", "chicken", "chocolate", "Coke", "cola"] {
            switch FoodConceptSearchRoute(index.assessIdentity(query),
                                          suggestions: index.search(query, limit: 5)) {
            case .sourced:
                wrongConfident += 1
            case .clarification, .unknownVariant, .weakAlternatives:
                unresolved += 1
            case .analyse:
                aiFallback += 1
            }
        }
        for query in ["chicken with rice", "a meal that is not in the bundle"] {
            #expect(FoodConceptSearchRoute(index.assessIdentity(query),
                                           suggestions: index.search(query, limit: 5)) == .analyse(query))
            aiFallback += 1
        }
        #expect(wrongConfident == 0)
        print("Food Concept routing benchmark: 15 queries, \(sourced) exact sourced, \(unresolved) unresolved, \(aiFallback) AI fallback, \(wrongConfident) wrong confident")
    }
}
