import Foundation
import Testing
@testable import calorietracker

struct FoodClarificationPlanTests {
    private func candidates(_ query: String) throws -> [(id: String, name: String)] {
        let index = try #require(AUSNUTFoodSearchIndex.bundled())
        return try index.assessIdentity(query).candidateSourceIDs.map { id in
            let foodID = String(id.dropFirst("ausnut:".count))
            return (id, try #require(AustralianNutritionService.identity(forID: foodID)).name)
        }
    }

    @Test func milkStartsWithSourceBackedConsumerTypes() throws {
        let sources = try candidates("milk")
        let plan = try #require(FoodClarificationPlan.make(query: "milk", sources: sources))
        #expect(plan.dimension == .fatType)
        #expect(plan.question == "What type of milk?")
        let labels = Set(plan.options.map(\.label))
        #expect(labels.isSuperset(of: ["Full cream", "Light", "Skim", "Lactose-free", "Other milk"]))
        let fullCream = try #require(plan.options.first { $0.label == "Full cream" })
        #expect(fullCream.sourceIDs.contains("ausnut:19101002"))
        #expect(fullCream.resolvedSourceID == nil)
        let other = try #require(plan.options.first { $0.label == "Other milk" })
        #expect(other.sourceIDs.contains("ausnut:19105001")) // evaporated stays reachable, not dominant
        #expect(Set(plan.options.flatMap(\.sourceIDs)) == Set(sources.map(\.id)))
    }

    @Test func chocolateAsksTypeBeforeDarkCocoaDetail() throws {
        let sources = try candidates("chocolate")
        let plan = try #require(FoodClarificationPlan.make(query: "chocolate", sources: sources))
        #expect(plan.dimension == .kind)
        #expect(plan.question == "What type of chocolate?")
        #expect(Set(plan.options.map(\.label)).isSuperset(of: ["Milk chocolate", "Dark chocolate", "White chocolate"]))
        let dark = try #require(plan.options.first { $0.label == "Dark chocolate" })
        #expect(dark.resolvedSourceID == nil)
        #expect(dark.sourceIDs.contains("ausnut:28101001"))
        #expect(dark.sourceIDs.contains("ausnut:28101002"))
        #expect(Set(plan.options.flatMap(\.sourceIDs)) == Set(sources.map(\.id)))
    }

    @Test func ricePrioritizesCookedVersusDry() throws {
        let plan = try #require(FoodClarificationPlan.make(query: "rice", sources: candidates("rice")))
        #expect(plan.dimension == .cookingState)
        #expect(Set(plan.options.map(\.label)).contains("Cooked"))
        #expect(Set(plan.options.map(\.label)).contains("Dry / uncooked"))
        #expect(plan.options.first { $0.label == "Dry / uncooked" }?.sourceIDs.contains("ausnut:12102002") == true)
    }

    @Test func chickenStartsWithCutWithoutSelectingANamedRecord() throws {
        let plan = try #require(FoodClarificationPlan.make(query: "chicken", sources: candidates("chicken")))
        #expect(plan.dimension == .cut)
        let breast = try #require(plan.options.first { $0.label == "Breast" })
        #expect(breast.sourceIDs.contains("ausnut:18301009"))
        #expect(breast.sourceIDs.contains("ausnut:18301010"))
        #expect(breast.resolvedSourceID == nil)
    }

    @Test func smallBananaFamilyRemainsDirectSourcedChoices() throws {
        let sources = try candidates("banana")
        #expect(FoodClarificationPlan.make(query: "banana", sources: sources) == nil)
    }

    @Test func unsupportedOrMixedSourcesFailBackToExactChoices() {
        let sources = (1...8).map { (id: "ausnut:\($0)", name: "Example, form \($0)") }
        #expect(FoodClarificationPlan.make(query: "example", sources: sources) == nil)
        let mixed = sources + [(id: "restaurant:item:one", name: "Example, branded")]
        #expect(FoodClarificationPlan.make(query: "example", sources: mixed) == nil)
    }

    @Test func representativePlansPartitionExactIDsAndNeverResolveAGroup() throws {
        for query in ["milk", "chocolate", "rice", "chicken"] {
            let sources = try candidates(query)
            let plan = try #require(FoodClarificationPlan.make(query: query, sources: sources))
            let listed = plan.options.flatMap(\.sourceIDs)
            #expect(listed.count == sources.count)
            #expect(Set(listed) == Set(sources.map(\.id)))
            for option in plan.options {
                #expect(option.sourceIDs.count == 1 || option.resolvedSourceID == nil)
                if let exact = option.resolvedSourceID {
                    #expect(sources.contains { $0.id == exact })
                }
            }
        }
    }
}
