import Foundation
import Testing
@testable import calorietracker

@MainActor
struct EstimateFormulationBoundaryTests {
    private func assess(_ query: String, _ names: [String], role: EstimateCandidateContext.Role = .carrier) -> EstimateCandidatePartitionResult {
        EstimateCandidatePartition.assess(EstimateCandidateContext(component: query, role: role,
            mealDescription: "meal", preparation: .other, preparationText: nil),
            identities: names.enumerated().map { AUSNUTFoodIdentity(id: "s\($0.offset)", name: $0.element, measures: []) })
    }
    private func sharePartition(_ r: EstimateCandidatePartitionResult, _ a: String, _ b: String) -> Bool {
        r.partitions.contains { Set($0.candidates.map(\.sourceID)).isSuperset(of: [a, b]) }
    }

    @Test func ordinaryAndLowCarbohydrateWrapsNeverSharePartition() {
        let r = assess("wrap", ["Bread, wrap, white", "Bread, wrap, white, low carbohydrate"])
        #expect(!sharePartition(r, "s0", "s1"))
        #expect(r.evidenceIDs.isEmpty)
    }
    @Test func ordinaryCompatibleWrapsCanStillSharePartition() {
        let r = assess("wrap", ["Bread, wrap, white", "Bread, wrap, wholemeal"])
        #expect(sharePartition(r, "s0", "s1"))
        #expect(r.evidenceIDs == ["s0", "s1"])
    }
    @Test func unspecifiedAndThinPizzaBasesNeverSharePartition() {
        let r = assess("pepperoni pizza", ["Pizza, pepperoni, takeaway", "Pizza, pepperoni, takeaway, thin base"], role: .preparedDish)
        #expect(!sharePartition(r, "s0", "s1"))
        #expect(r.evidenceIDs.isEmpty)
    }
    @Test func harmlessThinBaseAndCrustWordingRemainCompatible() {
        let r = assess("pepperoni pizza", ["Pizza, pepperoni, takeaway, thin base", "Pizza, pepperoni, takeaway, thin crust"], role: .preparedDish)
        #expect(sharePartition(r, "s0", "s1"))
        #expect(r.evidenceIDs == ["s0", "s1"])
    }
    @Test func highProteinFormulationIsNotOrdinaryProduct() {
        let r = assess("bread", ["Bread, commercial", "Bread, commercial, high protein"])
        #expect(!sharePartition(r, "s0", "s1"))
        #expect(r.evidenceIDs.isEmpty)
    }
    @Test func glutenFreeAndStandardBreadRemainDistinct() {
        let r = assess("bread", ["Bread, commercial", "Bread, commercial, gluten free"])
        #expect(!sharePartition(r, "s0", "s1"))
        #expect(r.evidenceIDs.isEmpty)
    }
    @Test func reducedNoAndRegularSugarBoundariesAreRetained() {
        let r = assess("drink", ["Drink, regular", "Drink, reduced sugar", "Drink, no sugar"], role: .ingredient)
        #expect(r.partitions.count == 3 && r.evidenceIDs.isEmpty)
        #expect(!sharePartition(r, "s0", "s1") && !sharePartition(r, "s0", "s2"))
    }
    @Test func lactoseFreeLabelAloneDoesNotInventMacroIncompatibilityOrSuitability() {
        let r = assess("feta cheese", ["Cheese, feta", "Cheese, feta, lactose free"], role: .ingredient)
        #expect(sharePartition(r, "s0", "s1"))
        #expect(r.partitions.flatMap(\.candidates).contains { $0.facets.clauses.contains("lactose free") })
        let explicit = assess("lactose free feta cheese", ["Cheese, feta", "Cheese, feta, lactose free"], role: .ingredient)
        #expect(explicit.evidenceIDs == ["s1"])
        #expect(!r.uncertainty.isEmpty)
    }
    @Test func exactSourceWinsRegardlessOfEstimateFacetMismatch() {
        let c = EstimateGroundedComponent(exactInput: GroundedComponentInput(description: "explicit source selection",
            sourceID: .ausnut("12302008"), amount: GroundedAmount(value: 100, unit: .grams, provenance: .user),
            estimatedNutrition: nil, assumptions: []), scopedEstimateQuery: "ordinary wrap",
            partitionContext: EstimateCandidateContext(component: "ordinary wrap", role: .carrier,
                mealDescription: "meal", preparation: .raw, preparationText: nil))
        let r = EstimateGroundedMealEngine.evaluate([c])
        #expect(r.exactGroundedCount == 1 && r.evidence == .sourced)
        #expect(r.components[0].estimateBasis == nil)
        #expect(r.components[0].exactResult.source?.sourceID == .ausnut("12302008"))
    }
    @Test func estimateEnvelopeCannotBecomeSourcedOrVerified() throws {
        let ids = [AUSNUTFoodIdentity(id: "fixture", name: "Bread, wrap", measures: [])]
        let context = EstimateCandidateContext(component: "wrap", role: .carrier, mealDescription: "meal",
            preparation: .other, preparationText: nil)
        let amount = GroundedAmount(value: 100, unit: .grams, provenance: .user)
        let basis = try #require(EstimateCandidatePartition.basis(context: context, amount: amount, identities: ids,
            resolver: { id, _ in GroundedSourceResolution(sourceID: id, sourceName: "Bread, wrap", sourceType: .ausnut,
                sourceVersion: "fixture-v1", sourceURL: nil,
                nutrition: NutritionFacts(calories: 100, proteinGrams: 4, carbohydrateGrams: 20, fatGrams: 2)) }))
        let input = EstimateGroundedComponent(exactInput: GroundedComponentInput(description: "wrap", sourceID: nil,
            amount: amount, estimatedNutrition: nil, assumptions: []), scopedEstimateQuery: "wrap")
        let r = EstimateGroundedMealEngine.evaluate([input], basisResolver: { _, _ in basis })
        #expect(r.evidence == .sourcedEstimate && r.exactGroundedCount == 0)
        #expect(basis.candidateSourceIDs == [.ausnut("fixture")] && !basis.uncertainty.isEmpty)
    }
    @Test func bundledBlockerIDsNeverShareAnEligiblePartition() throws {
        let identities = try #require(AustralianNutritionService.searchableIdentities)
        let wrap = EstimateCandidatePartition.assess(EstimateCandidateContext(component: "wrap flatbread", role: .carrier,
            mealDescription: "wrap", preparation: .other, preparationText: nil), identities: identities)
        #expect(!sharePartition(wrap, "12302007", "12302008"))
        let pizza = EstimateCandidatePartition.assess(EstimateCandidateContext(component: "Pepperoni pizza", role: .preparedDish,
            mealDescription: "takeaway pizza", preparation: .cooked, preparationText: nil), identities: identities)
        #expect(!sharePartition(pizza, "13502009", "13502010"))
        #expect(wrap.evidenceIDs.isEmpty && pizza.evidenceIDs.isEmpty)
    }
    @Test func absentQualifierIsNotStandardAndCombinedQualifiersSurvive() {
        let unknown = EstimateCandidatePartition.facets("Bread, commercial")
        let modified = EstimateCandidatePartition.facets("Bread, commercial, low-carb, high-protein, gluten-free")
        #expect(unknown.formulation == [.unspecified] && unknown.base == [.unspecified])
        #expect(modified.formulation == [.lowCarbohydrate, .highProtein, .glutenFree])
        #expect(EstimateCandidatePartition.facets("Pizza, regular base").base == [.standard])
        #expect(EstimateCandidatePartition.facets("Pizza, thin crust").base == [.thin])
    }
    @Test func structuralFormsGeneralizeBeyondPizzaAndOrdinaryWords() {
        #expect(EstimateCandidatePartition.facets("Pie, thick crust").base == [.thickDeepPan])
        #expect(EstimateCandidatePartition.facets("Tart, stuffed crust").base == [.stuffed])
        #expect(EstimateCandidatePartition.facets("Prepared dish, deep-pan").base == [.thickDeepPan])
        #expect(EstimateCandidatePartition.facets("Cream, thick").base == [.unspecified])
        #expect(EstimateCandidatePartition.facets("Vegetable, stuffed").base == [.unspecified])
    }
    @Test func lactoseFreeBundledNutritionRetainsBothSourceProfiles() throws {
        let identities = try #require(AustralianNutritionService.searchableIdentities)
        let context = EstimateCandidateContext(component: "Feta cheese", role: .ingredient, mealDescription: "meal",
            preparation: .other, preparationText: nil)
        let basis = try #require(EstimateCandidatePartition.basis(context: context,
            amount: GroundedAmount(value: 100, unit: .grams, provenance: .user), identities: identities))
        #expect(Set(basis.candidateSourceIDs) == [.ausnut("19401007"), .ausnut("19401008")])
        #expect(basis.candidates.count == 2 && !basis.uncertainty.isEmpty)
        let partitions = EstimateCandidatePartition.assess(context, identities: identities)
        #expect(partitions.partitions.flatMap(\.candidates).contains { $0.facets.dietaryLabels == ["lactose_free"] })
    }
    @Test func sourceExplicitFormulationAndBaseMarkersAreRecognizedAcrossBundle() throws {
        let identities = try #require(AustralianNutritionService.searchableIdentities)
        #expect(identities.count == 3_741)
        for food in identities {
            let name = food.name.lowercased(), f = EstimateCandidatePartition.facets(food.name)
            if name.contains("low carbohydrate") { #expect(f.formulation.contains(.lowCarbohydrate)) }
            if name.contains("high protein") { #expect(f.formulation.contains(.highProtein)) }
            if name.contains("gluten free") { #expect(f.formulation.contains(.glutenFree)) }
            if name.contains("thin base") { #expect(f.base.contains(.thin)) }
            if name.contains("thick base") { #expect(f.base.contains(.thickDeepPan)) }
        }
        #expect(EstimateCandidatePartition.facets("Milk, skim").formulation == [.skimmed])
        #expect(EstimateCandidatePartition.facets("Product, fat free").formulation == [.fatFree])
    }
}
