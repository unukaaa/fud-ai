import Foundation

/// Provider-neutral projection of independently checked caller evidence. This is
/// not a language extractor: unknown scope/noun attachment must remain unknown.
struct FoodQuantityAttachment: Codable, Equatable, Sendable {
    let evidenceID: String
    let originalText: String
    let value: Double
    let unit: FoodSemanticUnit
    let scope: FoodAmountScope
    let componentName: String?

    init(_ evidence: ExplicitFoodQuantity) {
        evidenceID = evidence.id
        originalText = evidence.originalText
        value = evidence.value
        unit = evidence.unit
        scope = evidence.scope
        componentName = evidence.componentName
    }
}

/// Only caller-checked bindings enter this provider-neutral request. A provider
/// must echo the scope and noun attachment, not infer them again from prose.
struct FoodQuantityInterpretationContract: Codable, Sendable {
    let version: String
    let description: String
    let quantities: [FoodQuantityAttachment]
    static let instructions = "Echo each quantity once with its original evidenceID, text, value, unit and scope. Component amounts/counts bind only to the checked componentName, not a containing meal. Meal-total quantities belong only to mealTotal. Natural portions and package fractions retain their scopes. Keep estimated edible grams separate. Unknown bindings remain unresolved; never reinterpret checked evidence."

    init(context: FoodSemanticContext) {
        version = "checked-quantity-binding-v1"
        description = context.description
        quantities = context.userQuantities.map { FoodQuantityAttachment($0) }
    }
}
