import Foundation
import Testing
@testable import calorietracker

struct FoodClarificationStopPolicyTests {
    private func candidates(_ query: String) throws -> [(id: String, name: String)] {
        let index = try #require(AUSNUTFoodSearchIndex.bundled())
        return try index.assessIdentity(query).candidateSourceIDs.map { id in
            let foodID = String(id.dropFirst("ausnut:".count))
            return (id, try #require(AustralianNutritionService.identity(forID: foodID)).name)
        }
    }

    private func narrowed(
        _ option: FoodClarificationPlan.Option,
        from sources: [(id: String, name: String)]
    ) -> [(id: String, name: String)] {
        sources.filter { option.sourceIDs.contains($0.id) }
    }

    private func questionDepths(
        _ sources: [(id: String, name: String)],
        query: String,
        used: Set<FoodClarificationPlan.Dimension> = [],
        path: [FoodClarificationStopPolicy.Selection] = [],
        applyStopPolicy: Bool
    ) -> [Int] {
        guard let plan = FoodClarificationPlan.make(query: query, sources: sources, excluding: used) else {
            return [1] // One exact sourced-choice step remains; no implicit identity is attached.
        }
        return plan.options.flatMap { option -> [Int] in
            if option.resolvedSourceID != nil { return [1] }
            let selectedSources = narrowed(option, from: sources)
            let nextPath = path + [.init(dimension: plan.dimension, key: option.key)]
            if applyStopPolicy {
                switch FoodClarificationStopPolicy.decide(sources: selectedSources, selections: nextPath) {
                case .stop, .optionalRefinement: return [1]
                case .required: break
                }
            }
            return questionDepths(selectedSources, query: query, used: used.union([plan.dimension]),
                                  path: nextPath, applyStopPolicy: applyStopPolicy).map { 1 + $0 }
        }
    }

    @Test func ordinaryFullCreamMilkStopsAfterCowIdentityIsKnown() throws {
        let sources = try candidates("milk")
        let first = try #require(FoodClarificationPlan.make(query: "milk", sources: sources))
        let choice = try #require(first.options.first { $0.key == "full-cream" })
        let fullCreamSources = narrowed(choice, from: sources)
        let path = [FoodClarificationStopPolicy.Selection(dimension: first.dimension, key: choice.key)]
        // Full cream also includes goat, sheep and powdered milk. Cow is not implicit.
        #expect(FoodClarificationStopPolicy.decide(sources: fullCreamSources, selections: path) == .required)
        let second = try #require(FoodClarificationPlan.make(
            query: "milk", sources: fullCreamSources, excluding: [first.dimension]
        ))
        let cow = try #require(second.options.first { $0.key == "cow" })
        let result = FoodClarificationStopPolicy.decide(
            sources: narrowed(cow, from: fullCreamSources),
            selections: path + [.init(dimension: second.dimension, key: cow.key)]
        )
        guard case .optionalRefinement(let defaultID, let refinements) = result else {
            Issue.record("Ordinary cow full-cream source should make variants optional: \(result)")
            return
        }
        #expect(defaultID == "ausnut:19101002")
        #expect(refinements.contains("ausnut:19101004")) // organic
        #expect(refinements.contains("ausnut:19101005")) // raw
        #expect(refinements.contains("ausnut:19104001")) // increased protein
        #expect(refinements.allSatisfy { cow.sourceIDs.contains($0) })
    }

    @Test func cookedRiceStillRequiresTypeButWhiteCookedCanStop() throws {
        let sources = try candidates("rice")
        let first = try #require(FoodClarificationPlan.make(query: "rice", sources: sources))
        let cooked = try #require(first.options.first { $0.key == "cooked" })
        let cookedSources = narrowed(cooked, from: sources)
        let path = [FoodClarificationStopPolicy.Selection(dimension: first.dimension, key: cooked.key)]
        #expect(FoodClarificationStopPolicy.decide(sources: cookedSources, selections: path) == .required)

        let second = try #require(FoodClarificationPlan.make(
            query: "rice", sources: cookedSources, excluding: [first.dimension]
        ))
        let white = try #require(second.options.first { $0.key == "white" })
        let result = FoodClarificationStopPolicy.decide(
            sources: narrowed(white, from: cookedSources),
            selections: path + [.init(dimension: second.dimension, key: white.key)]
        )
        guard case .optionalRefinement(let defaultID, _) = result else {
            Issue.record("White cooked rice should stop at its plain source identity")
            return
        }
        #expect(defaultID == "ausnut:12102003")
    }

    @Test func milkAndWhiteChocolateStopButDarkDoesNotInventAGeneric() throws {
        let sources = try candidates("chocolate")
        let plan = try #require(FoodClarificationPlan.make(query: "chocolate", sources: sources))
        for (key, expectedID) in [("milk", "ausnut:28101004"), ("white", "ausnut:28101006")] {
            let option = try #require(plan.options.first { $0.key == key })
            let result = FoodClarificationStopPolicy.decide(
                sources: narrowed(option, from: sources),
                selections: [.init(dimension: plan.dimension, key: option.key)]
            )
            guard case .optionalRefinement(let actualID, _) = result else {
                Issue.record("Expected a source-backed plain \(key) chocolate")
                continue
            }
            #expect(actualID == expectedID)
        }
        let dark = try #require(plan.options.first { $0.key == "dark" })
        #expect(FoodClarificationStopPolicy.decide(
            sources: narrowed(dark, from: sources),
            selections: [.init(dimension: plan.dimension, key: dark.key)]
        ) == .required)
    }

    @Test func chickenBreastDoesNotBecomeAnUnsupportedRawOrCookedDefault() throws {
        let sources = try candidates("chicken")
        let plan = try #require(FoodClarificationPlan.make(query: "chicken", sources: sources))
        let breast = try #require(plan.options.first { $0.key == "breast" })
        #expect(FoodClarificationStopPolicy.decide(
            sources: narrowed(breast, from: sources),
            selections: [.init(dimension: plan.dimension, key: breast.key)]
        ) == .required)
    }

    @Test func otherAndMultiIDGroupsNeverResolveOpaqueNutrition() throws {
        let sources = try candidates("milk")
        let plan = try #require(FoodClarificationPlan.make(query: "milk", sources: sources))
        let other = try #require(plan.options.first { $0.key == "other" })
        #expect(other.resolvedSourceID == nil)
        #expect(FoodClarificationStopPolicy.decide(
            sources: narrowed(other, from: sources),
            selections: [.init(dimension: plan.dimension, key: other.key)]
        ) == .required)
        #expect(FoodClarificationStopPolicy.decide(
            sources: [("ausnut:1", "Banana, cavendish, raw"),
                      ("ausnut:2", "Banana, lady finger, raw")],
            selections: [.init(dimension: .kind, key: "banana")]
        ) == .required)
    }

    @Test func exactAppleBananaAndRestaurantRoutesRemainSeparate() throws {
        let index = UnifiedFoodSearchIndex(restaurants: RestaurantFoodSearchIndex.bundled(),
                                           ausnut: AUSNUTFoodSearchIndex.bundled())
        guard case .sourced(let appleID, _) = FoodConceptSearchRoute(index.assessIdentity("raw apple")) else {
            Issue.record("Raw apple should resolve to its NFD source")
            return
        }
        #expect(appleID == "ausnut:16101015")
        guard case .unknownVariant = FoodConceptSearchRoute(index.assessIdentity("banana")) else {
            Issue.record("Banana must remain unresolved")
            return
        }
        #expect(FoodConceptSearchRoute(index.assessIdentity("Big Mac"))
            == .sourced("restaurant:item:mcd-au-big-mac", refinements: []))
        #expect(FoodConceptSearchRoute(index.assessIdentity("Zinger"))
            == .sourced("restaurant:item:kfc-au-zinger-burger", refinements: []))
    }

    @Test func representativeDepthAuditKeepsUnresolvedCasesUnresolved() throws {
        let index = UnifiedFoodSearchIndex(restaurants: RestaurantFoodSearchIndex.bundled(),
                                           ausnut: AUSNUTFoodSearchIndex.bundled())
        let queries = ["raw apple", "apple", "banana", "milk", "rice", "chicken",
                       "chicken breast", "chocolate", "egg", "tuna", "pasta", "Coke",
                       "cola", "Big Mac", "Zinger"]
        var exact = 0
        var unresolved = 0
        var ai = 0
        var improved = 0
        for query in queries {
            let route = FoodConceptSearchRoute(index.assessIdentity(query),
                                               suggestions: index.search(query, limit: 5))
            switch route {
            case .sourced: exact += 1
            case .clarification, .unknownVariant, .weakAlternatives: unresolved += 1
            case .analyse: ai += 1
            }
            let sourceIDs = route.candidateSourceIDs
            let sources = sourceIDs.map { id -> (id: String, name: String) in
                guard id.hasPrefix("ausnut:"),
                      let identity = AustralianNutritionService.identity(
                        forID: String(id.dropFirst("ausnut:".count))) else {
                    return (id, id)
                }
                return (id, identity.name)
            }
            let before: [Int]
            let after: [Int]
            if case .sourced = route { before = [0]; after = [0] }
            else if case .analyse = route { before = [0]; after = [0] }
            else {
                before = questionDepths(sources, query: query, applyStopPolicy: false)
                after = questionDepths(sources, query: query, applyStopPolicy: true)
            }
            let beforeRange = (before.min() ?? 0, before.max() ?? 0)
            let afterRange = (after.min() ?? 0, after.max() ?? 0)
            #expect(afterRange.0 <= beforeRange.0)
            #expect(afterRange.1 <= beforeRange.1)
            if afterRange.1 < beforeRange.1 { improved += 1 }
            print("CLARIFICATION_DEPTH query=\(query) before=\(beforeRange.0)...\(beforeRange.1) after=\(afterRange.0)...\(afterRange.1)")
        }
        #expect(exact + unresolved + ai == queries.count)
        #expect(FoodConceptSearchRoute(index.assessIdentity("banana")).candidateSourceIDs.count > 1)
        #expect(improved > 0)
        print("CLARIFICATION_DEPTH_SUMMARY queries=\(queries.count) direct=\(exact) unresolved=\(unresolved) ai=\(ai) reducedMaximumDepth=\(improved)")
    }
}
