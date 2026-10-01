import Foundation
import Testing
@testable import calorietracker

@MainActor
struct EstimateRetrievalBridgeTests {
    private func identity(_ id: String, _ name: String, measures: [AUSNUTFoodMeasure] = []) -> AUSNUTFoodIdentity {
        AUSNUTFoodIdentity(id: id, name: name, measures: measures)
    }
    private let grams = GroundedAmount(value: 100, unit: .grams, provenance: .estimated)
    private func q(_ value: Double = 100, unit: FoodSemanticUnit = .grams,
                   scope: FoodAmountScope = .componentAmount) -> FoodQuantityProposal {
        FoodQuantityProposal(evidenceID: "q1", originalText: "original amount", value: value, unit: unit, scope: scope)
    }
    private func estimated(_ value: Double = 120) -> FoodQuantityProposal {
        FoodQuantityProposal(evidenceID: nil, originalText: nil, value: value, unit: .grams, scope: .componentAmount)
    }
    private func assess(_ query: String, _ records: [AUSNUTFoodIdentity]) -> [String] {
        EstimateRetrievalBridge.assess(query, identities: records).eligibleIDs
    }

    @Test func sourceAttestedPluralFindsSingularWithoutPrefixMatching() {
        let r = [identity("a", "Raspberry, raw"), identity("b", "Raspberry jelly, prepared")]
        #expect(assess("raspberries raw", r) == ["a"])
        #expect(assess("rasp raw", r).isEmpty)
    }
    @Test func berryPluralDoesNotCollapseDifferentFruitFamilies() {
        let r = [identity("a", "Berry, raw"), identity("b", "Strawberry, raw"), identity("c", "Blueberry, raw")]
        #expect(assess("berries raw", r) == ["a"])
        #expect(assess("strawberries raw", r) == ["b"])
        #expect(assess("berry", r).isEmpty)
    }
    @Test func singularGuardDoesNotStemBassOrCouscous() {
        let r = [identity("a", "Bass, raw"), identity("b", "Couscous, cooked")]
        #expect(assess("bass raw", r) == ["a"])
        #expect(assess("couscous cooked", r) == ["b"])
    }
    @Test func tokenOrderPreservesEveryQualifier() {
        let r = [identity("a", "Chocolate, dark, high cocoa"), identity("b", "Chocolate, milk")]
        #expect(assess("dark chocolate", r) == ["a"])
        #expect(assess("dark chocolate no sugar", r).isEmpty)
    }
    @Test func consumerTermCanMatchSourceChildClauseWithoutExactIdentityClaim() throws {
        let r = [identity("a", "Dip, hummus (hommus), commercial"), identity("b", "Dip, hummus (hommus), homemade")]
        #expect(assess("hummus", r) == ["a", "b"])
        #expect(assess("hommus", r) == ["a", "b"])
        let b = try #require(EstimateRetrievalBridge.basis(scopedQuery: "hummus", amount: grams,
            identities: r, resolver: { id, _ in
                GroundedSourceResolution(sourceID: id, sourceName: "fixture", sourceType: .ausnut,
                    sourceVersion: "synthetic", sourceURL: nil,
                    nutrition: NutritionFacts(calories: 100, proteinGrams: 4, carbohydrateGrams: 10, fatGrams: 5))
            }))
        #expect(b.candidateSourceIDs.count == 2 && b.method == .scopedSourceEnvelope)
        #expect(!b.uncertainty.isEmpty && b.assumptions.contains("Estimate retrieval: \(EstimateRetrievalBridge.version)"))
    }
    @Test func cookedAndExplicitDryRiceRemainSeparate() {
        let r = [identity("a", "Rice, white, cooked"), identity("b", "Rice, white, uncooked")]
        #expect(assess("rice cooked", r) == ["a"])
        #expect(assess("rice dry", r) == ["b"])
        #expect(assess("rice", r).isEmpty)
    }
    @Test func grilledAndRawChickenDoNotMix() {
        let r = [identity("a", "Chicken, breast, cooked"), identity("b", "Chicken, breast, raw")]
        #expect(assess("grilled chicken breast cooked", r) == ["a"])
        #expect(assess("raw chicken breast", r) == ["b"])
    }
    @Test func incompatiblePreparationAndAddedFatCannotFormEnvelope() {
        let r = [identity("a", "Vegetable, boiled, no added fat"), identity("b", "Vegetable, baked, added fat")]
        #expect(assess("vegetable cooked", r).isEmpty)
        #expect(assess("vegetable raw", r).isEmpty)
    }
    @Test func broadCrossFamilyAndRecipeAlternativesStayUnresolved() {
        #expect(assess("fish cooked", [identity("a", "Fish, cooked"), identity("b", "Fish pie, cooked")]).isEmpty)
        #expect(assess("dark chocolate", [identity("a", "Chocolate, dark"), identity("b", "Chocolate, dark, fondant filled")]).isEmpty)
        #expect(assess("bread", [identity("a", "Bread, plain"), identity("b", "Bread, with cheese")]).isEmpty)
    }
    @Test func comparisonSymbolsAndSugarQualifiersAreNotErased() {
        let r = [identity("a", "Chocolate, dark, >60% cocoa"), identity("b", "Chocolate, dark, <60% cocoa")]
        #expect(assess("dark chocolate >60 cocoa", r) == ["a"])
        #expect(assess("dark chocolate <60 cocoa", r) == ["b"])
        #expect(assess("cola zero", [identity("a", "Cola, regular"), identity("b", "Cola, zero sugar")]) == ["b"])
    }
    @Test func legacyEstimateCandidatesMustAlsoRespectRecipeCompatibility() {
        #expect(!EstimateRetrievalBridge.compatibleSourceEvidence([
            "Sauce, tomato, regular", "Sauce, tomato, with cream"]))
        #expect(!EstimateRetrievalBridge.compatibleSourceEvidence([
            "Cheese, feta", "Cheese, feta, reduced fat", "Cheese, feta, marinated"]))
        #expect(!EstimateRetrievalBridge.compatibleSourceEvidence([
            "Spread, regular", "Spread, increased protein"]))
        #expect(EstimateRetrievalBridge.compatibleSourceEvidence([
            "Banana, Cavendish, raw", "Banana, Lady Finger, raw"]))
        for query in ["Tomato sauce", "Peanut butter", "Feta"] {
            #expect(EstimateGroundingPolicy.ausnutBasis(scopedQuery: query, amount: grams) == nil)
        }
    }
    @Test func contradictoryPreparationCannotPickTheFirstConvenientBasis() {
        let r = [identity("a", "Rice, raw"), identity("b", "Rice, cooked")]
        #expect(assess("rice raw cooked", r).isEmpty)
        #expect(assess("rice raw fried", r).isEmpty)
    }
    @Test func actualBundleAddsNarrowEvidenceWithoutChangingStrictSearch() throws {
        let result = EstimateGroundedMealEngine.evaluate([
            EstimateGroundedComponent(exactInput: GroundedComponentInput(description: "raspberries", sourceID: nil,
                amount: grams, estimatedNutrition: nil, assumptions: []), scopedEstimateQuery: "raspberries raw")])
        #expect(result.complete && result.evidence == .sourcedEstimate && result.exactGroundedCount == 0)
        #expect(result.components[0].estimateBasis?.candidateSourceIDs == [.ausnut("16201012")])
        #expect(AUSNUTFoodSearchIndex.bundled()?.assessIdentity("raspberries raw").defaultSourceID == nil)
    }
    @Test func exactSourceAlwaysWinsAndInvalidIDCannotBeReplaced() {
        for id in ["16502001", "invalid"] {
            let c = EstimateGroundedComponent(exactInput: GroundedComponentInput(description: "raspberries", sourceID: .ausnut(id),
                amount: grams, estimatedNutrition: nil, assumptions: []), scopedEstimateQuery: "raspberries raw")
            let r = EstimateGroundedMealEngine.evaluate([c])
            #expect(r.estimateGroundedCount == 0)
            #expect(r.exactGroundedCount == (id == "invalid" ? 0 : 1))
        }
    }
    @Test func estimatedAndUserGramsKeepDistinctProvenance() throws {
        #expect(GroundedAmountAdapter.resolve(user: q(37), estimate: estimated())?.amount.value == 37)
        #expect(GroundedAmountAdapter.resolve(user: q(37), estimate: estimated())?.amount.provenance == .user)
        #expect(GroundedAmountAdapter.resolve(user: nil, estimate: estimated())?.amount.provenance == .estimated)
        #expect(GroundedAmountAdapter.resolve(user: q(-1), estimate: estimated()) == nil)
    }
    @Test func explicitMillilitresNeedAgreeingExactSourceMeasures() {
        let measures = [AUSNUTFoodMeasure(name: "can", quantity: 1, grams: 330, measureID: 1, volume: 330),
                        AUSNUTFoodMeasure(name: "can", quantity: 1, grams: 375, measureID: 2, volume: 375)]
        let r = GroundedAmountAdapter.resolve(user: q(250, unit: .millilitres), estimate: estimated(),
            exactIdentity: identity("drink", "Drink", measures: measures))
        #expect(r?.amount.value == 250 && r?.amount.provenance == .user)
        #expect(r?.original?.unit == .millilitres && r?.measureID != nil)
        let bad = measures + [AUSNUTFoodMeasure(name: "glass", quantity: 1, grams: 400, measureID: 3, volume: 200)]
        #expect(GroundedAmountAdapter.resolve(user: q(250, unit: .millilitres), estimate: estimated(), exactIdentity: identity("bad", "Drink", measures: bad)) == nil)
        #expect(GroundedAmountAdapter.resolve(user: q(250, unit: .millilitres), estimate: estimated()) == nil)
    }
    @Test(arguments: ["slice", "cup", "glass", "bowl", "banana"])
    func naturalMeasuresRequireExactIDAndIndependentlyCheckedUnit(unit: String) {
        let source = identity("a", "Fixture", measures: [AUSNUTFoodMeasure(name: unit, quantity: 1, grams: 50,
            measureID: 9, descriptors: [unit])])
        let user = q(2, unit: .count, scope: .servingCount)
        let r = GroundedAmountAdapter.resolve(user: user, estimate: nil, exactIdentity: source, measureID: 9, naturalUnit: unit)
        #expect(r?.amount.value == 100 && r?.measureID == 9 && r?.original == user)
        #expect(GroundedAmountAdapter.resolve(user: user, estimate: nil, exactIdentity: source, measureID: 99, naturalUnit: unit) == nil)
        #expect(GroundedAmountAdapter.resolve(user: user, estimate: nil, exactIdentity: source, measureID: 9, naturalUnit: "different") == nil)
    }
    @Test(arguments: [FoodAmountScope.servingCount, .naturalPortion, .packageFraction])
    func countsContainersAndPacketFractionKeepOriginalEvidenceWithEstimatedGrams(scope: FoodAmountScope) {
        let user = q(scope == .packageFraction ? 0.5 : 2, unit: scope == .packageFraction ? .fraction : .count, scope: scope)
        let r = GroundedAmountAdapter.resolve(user: user, estimate: estimated(60))
        #expect(r?.original == user && r?.amount.value == 60 && r?.amount.provenance == .estimated)
    }
    @Test func unknownOrMealTotalScopeCannotBecomeConvenientComponentGrams() {
        #expect(GroundedAmountAdapter.resolve(user: q(scope: .unknownScope), estimate: estimated()) == nil)
        #expect(GroundedAmountAdapter.resolve(user: q(scope: .mealTotalAmount), estimate: estimated()) == nil)
    }
    @Test func partialPointMealRemainsIncompleteEvenWithNewBridge() throws {
        let p = FoodMealProposal(components: ["raspberries", "fictional snack"].enumerated().map { i, name in
            FoodComponentProposal(id: "c\(i)", name: name, preparation: .raw, preparationText: nil, userAmount: nil,
                estimatedAmount: estimated(), assumptions: [])
        }, mealTotal: nil, question: nil, assumptions: [])
        let v = try #require(FoodAmountSemanticFirewall.assess(p,
            context: FoodSemanticContext(description: "meal", userQuantities: [], preparationConstraints: [])).accepted)
        let r = GroundedPointEstimatePolicy.evaluate(v) { EstimateGroundedMealEngine.evaluate(GroundedPointEstimatePolicy.components(from: $0)) }
        #expect(r.availablePoint != nil && r.completeNutrition == nil && r.evidence == .estimate)
    }
}
