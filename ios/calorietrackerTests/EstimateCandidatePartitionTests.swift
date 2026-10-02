import Foundation
import Testing
@testable import calorietracker

@MainActor
struct EstimateCandidatePartitionTests {
    private func context(_ name: String, role: EstimateCandidateContext.Role = .ingredient,
                         preparation: FoodPreparationBasis = .cooked, text: String? = nil,
                         meal: String = "meal") -> EstimateCandidateContext {
        EstimateCandidateContext(component: name, role: role, mealDescription: meal,
            preparation: preparation, preparationText: text)
    }
    private func assess(_ c: EstimateCandidateContext, _ names: [String]) -> EstimateCandidatePartitionResult {
        EstimateCandidatePartition.assess(c, identities: names.enumerated().map {
            AUSNUTFoodIdentity(id: "s\($0.offset)", name: $0.element, measures: [])
        })
    }

    @Test func ingredientDoesNotAcquireContainingCompleteDish() {
        let r = assess(context("carrot"), ["Carrot, cooked", "Soup, carrot, cooked"])
        #expect(r.evidenceIDs == ["s0"])
        #expect(r.partitions.contains { $0.rejectionReasons.contains("component_not_containing_complete_dish") })
    }
    @Test func condimentDoesNotAcquireMeatInSauce() {
        let r = assess(context("tomato sauce", role: .condiment, preparation: .other),
            ["Sauce, tomato, regular", "Meat dish, tomato sauce, cooked"])
        #expect(r.evidenceIDs == ["s0"])
        #expect(r.partitions.flatMap(\.candidates).map(\.sourceID).sorted() == ["s0", "s1"])
    }
    @Test func spreadDoesNotAcquireContainingSandwich() {
        let r = assess(context("nut spread", role: .spread, preparation: .other),
            ["Spread, nut", "Sandwich, nut spread"])
        #expect(r.evidenceIDs == ["s0"])
    }
    @Test func readyToEatBakeryDoesNotRequireCookedWordOrMixUncooked() {
        let r = assess(context("bread roll", role: .carrier), ["Bread roll, white", "Bread roll, uncooked"])
        #expect(r.evidenceIDs == ["s0"])
        #expect(r.partitions.flatMap(\.candidates).contains { $0.facets.basis == .dryUncooked })
    }
    @Test func alternativeCookingMethodsAreNotSimultaneousIncompatibilities() {
        let f = EstimateCandidatePartition.facets("Vegetable, boiled, baked or grilled, no added fat")
        #expect(f.basis == .cookedPrepared && f.methods == ["boiled", "baked", "grilled"])
        let r = assess(context("vegetable", text: "grilled"),
            ["Vegetable, boiled, baked or grilled, no added fat", "Vegetable, raw"])
        #expect(r.evidenceIDs == ["s0"])
    }
    @Test func negatedAddedFatIsNotPositiveFatAndGroupsStaySeparate() {
        #expect(EstimateCandidatePartition.facets("Vegetable, cooked, without added fat").fat == .none)
        let r = assess(context("vegetable"), ["Vegetable, cooked, no added fat", "Vegetable, cooked, added fat"])
        #expect(r.partitions.count == 2 && r.evidenceIDs.isEmpty)
        #expect(r.reasons.contains("multiple_compatible_partitions_require_scope"))
    }
    @Test func regularReducedAndNoSugarPartitionsNeverBlend() {
        let r = assess(context("drink", preparation: .other),
            ["Drink, regular", "Drink, reduced sugar", "Drink, no sugar"])
        #expect(Set(r.partitions.flatMap(\.candidates).map { $0.facets.sugar }) == [.regular, .reduced, .none])
        #expect(r.partitions.count == 3)
        #expect(r.evidenceIDs.isEmpty)
    }
    @Test func recipeModifiersAreRetainedAndCannotPoisonOrMergeOrdinary() {
        let r = assess(context("plain vegetable"), ["Vegetable, cooked", "Vegetable, cooked, marinated"])
        #expect(r.evidenceIDs == ["s0"])
        #expect(r.partitions.contains { !$0.eligible && $0.candidates[0].facets.recipeModifiers == ["marinated"] })
    }
    @Test func waterOnlyDoesNotMeanMilkAndWaterOrEnhancedRecipe() {
        let r = assess(context("porridge made with water", role: .preparedDish),
            ["Porridge, oats, made with water", "Porridge, oats, made with milk & water"])
        #expect(r.evidenceIDs == ["s0"])
        #expect(r.partitions.contains { $0.rejectionReasons.contains("unrequested_recipe_liquid") })
    }
    @Test func sourceStorageAndDrainedEvidenceRemainDistinct() {
        let r = assess(context("bean"), ["Bean, cooked", "Bean, canned, drained, cooked"])
        #expect(r.partitions.count == 2 && r.evidenceIDs.isEmpty)
        #expect(r.partitions.flatMap(\.candidates).contains { $0.facets.drained && $0.facets.storage == ["canned"] })
    }
    @Test func fullPreparationTextSurvivesAndRejectsUnsupportedMethod() {
        let c = context("vegetable", text: "roasted")
        let r = assess(c, ["Vegetable, boiled", "Vegetable, roasted"])
        #expect(r.context.preparationText == "roasted" && r.evidenceIDs == ["s1"])
        #expect(r.partitions.contains { $0.rejectionReasons.contains("explicit_method_not_supported") })
    }
    @Test func dryReadyTextureIsNotUncookedRice() {
        let snack = assess(context("crispbread", role: .carrier, preparation: .dry), ["Biscuit, rye, crispbread"])
        #expect(snack.evidenceIDs == ["s0"])
        let rice = assess(context("rice", preparation: .dry), ["Rice, cooked", "Rice, uncooked"])
        #expect(rice.evidenceIDs == ["s1"])
    }
    @Test func plainNaturalAndCompoundFormsAreGenericNotSourceIDMappings() {
        #expect(assess(context("plain greek yoghurt", preparation: .other),
            ["Yoghurt, natural, greek style"]).evidenceIDs == ["s0"])
        #expect(assess(context("wrap flatbread", role: .carrier, preparation: .other),
            ["Bread, flat wrap or tortilla"]).evidenceIDs == ["s0"])
    }
    @Test func exactIdentityIsUnchangedAndEstimateNeverClaimsVerified() throws {
        let identities = [AUSNUTFoodIdentity(id: "a", name: "Yoghurt, natural, greek style", measures: [])]
        #expect(AUSNUTFoodSearchIndex(identities: identities).assessIdentity("plain greek yoghurt").defaultSourceID == nil)
        let basis = try #require(EstimateCandidatePartition.basis(context: context("plain greek yoghurt", preparation: .other),
            amount: GroundedAmount(value: 100, unit: .grams, provenance: .estimated), identities: identities,
            resolver: { id, _ in GroundedSourceResolution(sourceID: id, sourceName: identities[0].name,
                sourceType: .ausnut, sourceVersion: "fixture-v1", sourceURL: nil,
                nutrition: NutritionFacts(calories: 100, proteinGrams: 5, carbohydrateGrams: 7, fatGrams: 4)) }))
        #expect(basis.candidateSourceIDs == [.ausnut("a")] && basis.candidates[0].sourceVersion == "fixture-v1")
        #expect(!basis.uncertainty.isEmpty && basis.assumptions.contains(EstimateCandidatePartition.version))
        let input = EstimateGroundedComponent(exactInput: GroundedComponentInput(description: "plain greek yoghurt", sourceID: nil,
            amount: GroundedAmount(value: 100, unit: .grams, provenance: .estimated), estimatedNutrition: nil, assumptions: []),
            scopedEstimateQuery: "plain greek yoghurt")
        let result = EstimateGroundedMealEngine.evaluate([input], basisResolver: { _, _ in basis })
        #expect(result.evidence == .sourcedEstimate && result.exactGroundedCount == 0)
    }
    @Test func invalidExactSourceCannotBeReplacedByPartition() {
        let c = EstimateGroundedComponent(exactInput: GroundedComponentInput(description: "banana", sourceID: .ausnut("invalid"),
            amount: GroundedAmount(value: 100, unit: .grams, provenance: .estimated), estimatedNutrition: nil, assumptions: []),
            scopedEstimateQuery: "banana raw", partitionContext: context("banana", preparation: .raw))
        #expect(EstimateGroundedMealEngine.evaluate([c]).unresolvedCount == 1)
    }
    @Test func contextBuilderDoesNotLosePreparationOrUserQuantity() throws {
        let proposal = FoodMealProposal(components: [FoodComponentProposal(id: "c", name: "vegetable", preparation: .cooked,
            preparationText: "roasted", userAmount: nil,
            estimatedAmount: FoodQuantityProposal(evidenceID: nil, originalText: nil, value: 120, unit: .grams, scope: .componentAmount),
            assumptions: [])], mealTotal: nil, question: nil, assumptions: [])
        let accepted = try #require(FoodAmountSemanticFirewall.assess(proposal,
            context: FoodSemanticContext(description: "roasted vegetable", userQuantities: [], preparationConstraints: [])).accepted)
        let component = GroundedPointEstimatePolicy.components(from: accepted)[0]
        #expect(component.partitionContext?.preparationText == "roasted" && component.exactInput.amount?.value == 120)
    }
    @Test(arguments: [
        ("Plain Greek yoghurt", FoodPreparationBasis.other), ("mashed sweet potato", .cooked),
        ("peas", .cooked), ("Oat porridge made with water", .cooked), ("fish", .cooked),
        ("Bread", .other), ("Tomato sauce", .other), ("wrap flatbread", .other),
        ("Bread roll", .cooked), ("Pepperoni pizza", .cooked), ("Salad", .raw),
        ("Dark chocolate", .other), ("rye crispbreads", .dry), ("peanut butter", .other),
        ("Zucchini", .cooked), ("Feta cheese", .other)
    ])
    func retainedDiagnosticsPreserveIDsAndDoNotMergePartitions(name: String, prep: FoodPreparationBasis) throws {
        let identities = try #require(AustralianNutritionService.searchableIdentities)
        let proposal = FoodComponentProposal(id: "c", name: name, preparation: prep,
            preparationText: name == "Zucchini" ? "roasted" : nil, userAmount: nil, estimatedAmount: nil, assumptions: [])
        let r = EstimateCandidatePartition.assess(EstimateCandidateContext.component(proposal, in: "meal"), identities: identities)
        let ids = r.partitions.flatMap(\.candidates).map(\.sourceID)
        #expect(Set(ids).count == ids.count && !ids.isEmpty)
        #expect(Set(r.evidenceIDs).isSubset(of: Set(ids)))
        #expect(r.evidenceIDs.isEmpty || r.partitions.filter(\.eligible).count == 1)
        if name == "fish" || name == "Salad" { #expect(r.evidenceIDs.isEmpty) }
    }
}
