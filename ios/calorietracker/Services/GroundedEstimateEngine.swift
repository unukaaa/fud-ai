import Foundation

/// Input-specific interpretation (text, photo or voice) ends at this boundary.
/// Source IDs must be selected upstream; this engine never guesses a variant.
enum GroundedInputKind: Equatable, Sendable { case text, photo, voice }

enum GroundedSourceID: Hashable, Sendable {
    case ausnut(String)
    case restaurant(restaurantID: String, itemID: String)
    case barcode(String)
}

enum GroundedAmountUnit: Equatable, Sendable { case grams, servings }
enum GroundedAmountProvenance: Equatable, Sendable { case source, user, estimated }

struct GroundedAmount: Sendable {
    let value: Double
    let unit: GroundedAmountUnit
    let provenance: GroundedAmountProvenance

    var isValid: Bool { value.isFinite && value > 0 }
}

struct GroundedComponentInput: Sendable {
    let description: String
    let sourceID: GroundedSourceID?
    let amount: GroundedAmount?
    /// A future estimator may supply this; it is never promoted to sourced nutrition.
    let estimatedNutrition: NutritionFacts?
    let assumptions: [String]
}

struct GroundedMealInput: Sendable {
    let description: String
    let inputKind: GroundedInputKind
    let components: [GroundedComponentInput]
}

struct GroundedSourceResolution: Equatable, Sendable {
    let sourceID: GroundedSourceID
    let sourceName: String
    let sourceType: NutritionSourceType
    let sourceVersion: String?
    let sourceURL: String?
    let nutrition: NutritionFacts
}

struct GroundedComponentResult: Sendable {
    enum Evidence: Equatable, Sendable { case sourced, sourcedAmountEstimated, estimated, unresolved }

    let input: GroundedComponentInput
    let source: GroundedSourceResolution?
    let nutrition: NutritionFacts?
    let evidence: Evidence
}

struct GroundedMealResult: Sendable {
    enum Evidence: Equatable, Sendable { case sourced, sourcedEstimate, estimate }

    let input: GroundedMealInput
    let components: [GroundedComponentResult]
    /// Sum of available contributions. This is partial when `nutritionComplete` is false.
    let calculatedNutrition: NutritionFacts?
    let nutritionComplete: Bool
    let evidence: Evidence

    var groundedCount: Int { components.filter { $0.source != nil }.count }
    var unresolvedCount: Int { components.filter { $0.evidence == .unresolved }.count }
    var estimatedAmountCount: Int {
        components.filter { $0.evidence == .sourcedAmountEstimated }.count
    }
    var needsExternalEstimate: Bool { unresolvedCount > 0 }
}

enum GroundedQuestionBudget {
    enum NextStep: Equatable { case proceed, ask, estimate }

    /// Materiality is supplied by an upstream evidence check, never inferred
    /// from model confidence or an arbitrary nutrition percentage here.
    static func nextStep(questionsAsked: Int, materialAmbiguity: Bool,
                         largeConsequentialDifference: Bool) -> NextStep {
        guard materialAmbiguity else { return .proceed }
        if questionsAsked <= 0 { return .ask }
        if questionsAsked == 1 && largeConsequentialDifference { return .ask }
        return .estimate
    }
}

enum GroundedEstimateEngine {
    typealias Resolver = (GroundedSourceID, GroundedAmount) -> GroundedSourceResolution?

    static func evaluate(_ input: GroundedMealInput,
                         resolver: Resolver) -> GroundedMealResult {
        let components = input.components.map { component -> GroundedComponentResult in
            if let sourceID = component.sourceID, let amount = component.amount,
               amount.isValid, let source = resolver(sourceID, amount),
               source.sourceID == sourceID,
               (source.sourceType == .ausnut || source.sourceType == .verifiedRestaurant
                    || source.sourceType == .nutritionLabel),
               nutritionIsUsable(source.nutrition) {
                return GroundedComponentResult(
                    input: component, source: source, nutrition: source.nutrition,
                    evidence: amount.provenance == .estimated ? .sourcedAmountEstimated : .sourced
                )
            }
            if let estimate = component.estimatedNutrition, nutritionIsUsable(estimate) {
                return GroundedComponentResult(
                    input: component, source: nil, nutrition: estimate, evidence: .estimated
                )
            }
            return GroundedComponentResult(
                input: component, source: nil, nutrition: nil, evidence: .unresolved
            )
        }
        let values = components.compactMap(\.nutrition)
        let complete = !components.isEmpty && components.allSatisfy { component in
            guard let nutrition = component.nutrition else { return false }
            return nutrition.calories != nil && nutrition.proteinGrams != nil
                && nutrition.carbohydrateGrams != nil && nutrition.fatGrams != nil
        }
        let evidence: GroundedMealResult.Evidence
        if components.isEmpty || components.contains(where: {
            $0.evidence == .estimated || $0.evidence == .unresolved
        }) {
            evidence = .estimate
        } else if components.contains(where: { $0.evidence == .sourcedAmountEstimated }) {
            evidence = .sourcedEstimate
        } else {
            evidence = .sourced
        }
        return GroundedMealResult(
            input: input, components: components,
            calculatedNutrition: NutritionFacts.adding(values),
            nutritionComplete: complete, evidence: evidence
        )
    }

    private static func nutritionIsUsable(_ nutrition: NutritionFacts) -> Bool {
        let values = [nutrition.calories, nutrition.proteinGrams,
                      nutrition.carbohydrateGrams, nutrition.fatGrams].compactMap { $0 }
        return !values.isEmpty && values.allSatisfy { $0.isFinite && $0 >= 0 }
    }
}

/// Exact, bundled-only adapters. An unsupported ID/amount stays unresolved;
/// barcode lookup and configured restaurant meals need their existing paths.
enum ExistingFoodGrounder {
    static func resolve(_ id: GroundedSourceID, amount: GroundedAmount) -> GroundedSourceResolution? {
        guard amount.isValid else { return nil }
        switch id {
        case .ausnut(let foodID):
            guard amount.unit == .grams,
                  let identity = AustralianNutritionService.identity(forID: foodID),
                  let analysis = AustralianNutritionService.analysis(
                    for: AUSNUTFoodSelection(foodID: foodID), portion: .grams(amount.value)
                  ) else { return nil }
            return GroundedSourceResolution(
                sourceID: id, sourceName: identity.name, sourceType: .ausnut,
                sourceVersion: "AUSNUT 2023", sourceURL: nil,
                nutrition: NutritionFacts(
                    calories: Double(analysis.calories), kilojoules: nil,
                    proteinGrams: analysis.protein, carbohydrateGrams: analysis.carbs,
                    fatGrams: analysis.fat
                )
            )
        case .restaurant(let restaurantID, let itemID):
            guard amount.unit == .servings,
                  let dataset = RestaurantDatasetStore.bundled()?.dataset,
                  let item = dataset.menuItems.first(where: { $0.id == itemID }),
                  let provenance = item.provenance,
                  provenance.restaurantID == restaurantID,
                  provenance.sourceType == .verifiedRestaurant,
                  provenance.country == "AU",
                  item.variants.isEmpty, item.mealConfigurations.isEmpty,
                  let nutrition = item.nutrition else { return nil }
            return GroundedSourceResolution(
                sourceID: id, sourceName: item.name, sourceType: .verifiedRestaurant,
                sourceVersion: provenance.datasetVersion, sourceURL: provenance.sourceURL,
                nutrition: nutrition.scaled(by: amount.value)
            )
        case .barcode:
            return nil // Never start a remote lookup from deterministic aggregation.
        }
    }
}
