import Foundation
import Testing
@testable import calorietracker

struct EstimateGroundingPolicyTests {
    private func amount(_ value: Double = 120) -> GroundedAmount {
        GroundedAmount(value: value, unit: .grams, provenance: .estimated)
    }
    private func component(_ query: String, id: GroundedSourceID? = nil,
                           amount: GroundedAmount? = nil) -> EstimateGroundedComponent {
        EstimateGroundedComponent(
            exactInput: GroundedComponentInput(description: query, sourceID: id,
                amount: amount ?? self.amount(), estimatedNutrition: nil, assumptions: ["Raw preparation assumed"]),
            scopedEstimateQuery: query)
    }

    @Test func strictBananaIdentityStaysUnresolvedWhileScopedEstimateRetainsBothSources() throws {
        let index = try #require(AUSNUTFoodSearchIndex.bundled())
        #expect(index.assessIdentity("banana").defaultSourceID == nil)
        let result = EstimateGroundedMealEngine.evaluate([component("banana raw")])
        let basis = try #require(result.components[0].estimateBasis)
        #expect(Set(basis.candidateSourceIDs) == [.ausnut("16502001"), .ausnut("16502002")])
        #expect(result.evidence == .sourcedEstimate)
        #expect(result.exactGroundedCount == 0 && result.estimateGroundedCount == 1)
        #expect(result.complete)
        #expect(result.components[0].exactResult.source == nil)
        #expect(result.components[0].exactResult.nutrition == nil)
        #expect(basis.method == .scopedSourceEnvelope)
        #expect(!basis.assumptions.isEmpty && !basis.uncertainty.isEmpty)
        #expect(basis.candidates.allSatisfy { $0.sourceType == .ausnut && $0.sourceVersion == "AUSNUT 2023" })
    }

    @Test func envelopeUsesActualExtremaNotAverageAndScalesDeterministically() throws {
        let basis = try #require(EstimateGroundingPolicy.ausnutBasis(scopedQuery: "banana raw", amount: amount()))
        let calories = basis.candidates.compactMap { $0.nutrition.calories }
        #expect(basis.envelope.lower.calories == calories.min())
        #expect(basis.envelope.upper.calories == calories.max())
        #expect(basis.envelope.lower.calories != basis.envelope.upper.calories)
        for source in basis.candidates {
            let original = try #require(ExistingFoodGrounder.resolve(source.sourceID, amount: amount()))
            #expect(source.nutrition == original.nutrition)
        }
        let twice = EstimateGroundedMealEngine.evaluate([component("banana raw"), component("banana raw")])
        #expect(twice.availableEnvelope?.lower.calories == basis.envelope.lower.calories! * 2)
        #expect(twice.availableEnvelope?.upper.carbohydrateGrams == basis.envelope.upper.carbohydrateGrams! * 2)
    }

    @Test func mixedPreparationAndUnsupportedFamilyRemainUnresolved() {
        for query in ["banana", "rice", "chicken breast", "fictional moon snack"] {
            let result = EstimateGroundedMealEngine.evaluate([component(query)])
            #expect(result.evidence == .estimate)
            #expect(result.estimateGroundedCount == 0)
            #expect(result.unresolvedCount == 1 && !result.complete)
        }
    }

    @Test func fittingNFDUsesOnlyItsOwnSourceEvidenceWithoutBlendingVarieties() throws {
        let basis = try #require(EstimateGroundingPolicy.ausnutBasis(scopedQuery: "raw apple", amount: amount()))
        #expect(basis.candidateSourceIDs == [.ausnut("16101015")])
        #expect(basis.envelope.lower == basis.envelope.upper)
        #expect(EstimateGroundedMealEngine.evaluate([component("raw apple")]).evidence == .sourcedEstimate)
    }

    @Test func exactAUSNUTRestaurantAndBarcodeResolutionAlwaysWin() {
        let grams = GroundedAmount(value: 100, unit: .grams, provenance: .user)
        let ausnut = EstimateGroundedMealEngine.evaluate([component("banana raw", id: .ausnut("16502001"), amount: grams)])
        #expect(ausnut.evidence == .sourced && ausnut.estimateGroundedCount == 0)
        #expect(ausnut.components[0].exactResult.source?.sourceID == .ausnut("16502001"))
        let serving = GroundedAmount(value: 1, unit: .servings, provenance: .source)
        let restaurant = EstimateGroundedMealEngine.evaluate([component("Big Mac", id: .restaurant(restaurantID: "mcdonalds_au", itemID: "mcd-au-big-mac"), amount: serving)])
        #expect(restaurant.evidence == .sourced && restaurant.availableEnvelope?.lower.calories == 557)
        let barcodeID = GroundedSourceID.barcode("synthetic-gtin")
        let barcode = EstimateGroundedMealEngine.evaluate([component("banana raw", id: barcodeID, amount: grams)], resolver: { id, _ in
            GroundedSourceResolution(sourceID: id, sourceName: "Synthetic exact label", sourceType: .nutritionLabel,
                sourceVersion: "fixture", sourceURL: nil,
                nutrition: NutritionFacts(calories: 100, kilojoules: nil, proteinGrams: 1, carbohydrateGrams: 20, fatGrams: 2))
        })
        #expect(barcode.evidence == .sourced && barcode.estimateGroundedCount == 0)
        #expect(barcode.components[0].exactResult.source?.sourceID == barcodeID)
    }

    @Test func invalidExplicitIdentityIsNotReplacedAndPartialProgressRemainsHonest() {
        let result = EstimateGroundedMealEngine.evaluate([
            component("banana raw"), component("banana raw", id: .ausnut("does-not-exist"))])
        #expect(!result.complete && result.evidence == .estimate)
        #expect(result.estimateGroundedCount == 1 && result.unresolvedCount == 1)
        #expect(result.availableEnvelope != nil)
        #expect(result.components[1].estimateBasis == nil)
    }

    @Test func invalidAmountsMissingNutrientsAndVersionMismatchFailClosed() {
        #expect(EstimateGroundingPolicy.ausnutBasis(scopedQuery: "banana raw", amount: amount(-1)) == nil)
        #expect(EstimateGroundingPolicy.ausnutBasis(scopedQuery: "banana raw", amount: amount(.infinity)) == nil)
        #expect(EstimateGroundingPolicy.ausnutBasis(scopedQuery: "banana raw", amount: GroundedAmount(value: 1, unit: .servings, provenance: .estimated)) == nil)
        let bad = EstimateGroundingPolicy.ausnutBasis(scopedQuery: "banana raw", amount: amount(), resolver: { id, _ in
            GroundedSourceResolution(sourceID: id, sourceName: "bad fixture", sourceType: .ausnut,
                sourceVersion: "fixture", sourceURL: nil,
                nutrition: NutritionFacts(calories: 100, kilojoules: nil, proteinGrams: nil, carbohydrateGrams: 20, fatGrams: 1))
        })
        #expect(bad == nil)
        let mismatch = EstimateGroundingPolicy.ausnutBasis(scopedQuery: "banana raw", amount: amount(), resolver: { id, amount in
            guard let source = ExistingFoodGrounder.resolve(id, amount: amount) else { return nil }
            return GroundedSourceResolution(sourceID: id, sourceName: source.sourceName, sourceType: .ausnut,
                sourceVersion: id == .ausnut("16502001") ? "v1" : "v2", sourceURL: nil, nutrition: source.nutrition)
        })
        #expect(mismatch == nil)
    }

    @Test func suppliedNutritionRemainsEstimateAndEstimatedExactAmountRemainsSourcedEstimate() {
        let estimated = EstimateGroundedComponent(exactInput: GroundedComponentInput(description: "unknown", sourceID: nil,
            amount: nil, estimatedNutrition: NutritionFacts(calories: 90, kilojoules: nil, proteinGrams: 1, carbohydrateGrams: 20, fatGrams: 0), assumptions: ["Fixture estimate"]), scopedEstimateQuery: nil)
        #expect(EstimateGroundedMealEngine.evaluate([estimated]).evidence == .estimate)
        #expect(EstimateGroundedMealEngine.evaluate([component("banana", id: .ausnut("16502001"))]).evidence == .sourcedEstimate)
    }

    @Test func aggregateOverflowCannotBecomeACompleteNutritionClaim() {
        let input = component("synthetic", id: .barcode("synthetic"))
        let result = EstimateGroundedMealEngine.evaluate([input, input], resolver: { id, _ in
            GroundedSourceResolution(sourceID: id, sourceName: "Synthetic", sourceType: .nutritionLabel,
                sourceVersion: "fixture", sourceURL: nil,
                nutrition: NutritionFacts(calories: Double.greatestFiniteMagnitude, kilojoules: nil,
                                         proteinGrams: 1, carbohydrateGrams: 1, fatGrams: 1))
        })
        #expect(!result.complete && result.evidence == .estimate)
        #expect(result.availableEnvelope == nil)
    }

    @Test func candidateOrderCannotSelectARepresentativeVariant() throws {
        let ids = try #require(AustralianNutritionService.searchableIdentities)
        let reversed = AUSNUTFoodSearchIndex(identities: Array(ids.reversed()))
        let normal = try #require(EstimateGroundingPolicy.ausnutBasis(scopedQuery: "banana raw", amount: amount()))
        let reverse = try #require(EstimateGroundingPolicy.ausnutBasis(scopedQuery: "banana raw", amount: amount(), index: reversed))
        #expect(normal.candidateSourceIDs == reverse.candidateSourceIDs)
        #expect(normal.envelope == reverse.envelope)
    }
}
