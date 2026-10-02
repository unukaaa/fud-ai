import Foundation

enum FoodQuantityEvidenceProvenance: String, Codable, Sendable {
    case userSupplied
}

/// Provider-neutral projection of independently checked caller evidence. This is
/// not a language extractor: unknown scope/noun attachment must remain unknown.
struct FoodQuantityAttachment: Codable, Equatable, Sendable {
    let evidenceID: String
    let originalText: String
    let value: Double
    let unit: FoodSemanticUnit
    let scope: FoodAmountScope
    let componentName: String?
    let provenance: FoodQuantityEvidenceProvenance

    init(_ evidence: ExplicitFoodQuantity) {
        evidenceID = evidence.id
        originalText = evidence.originalText
        value = evidence.value
        unit = evidence.unit
        scope = evidence.scope
        componentName = evidence.componentName
        provenance = .userSupplied
    }
}

/// Only caller-checked bindings enter this provider-neutral request. A provider
/// must echo the scope and noun attachment, not infer them again from prose.
struct FoodQuantityInterpretationContract: Codable, Sendable {
    let version: String
    let description: String
    let quantities: [FoodQuantityAttachment]
    static let instructions = "The quantities are independently checked USER_SUPPLIED constraints, not suggestions. Echo each binding exactly once using its evidenceID, originalText, value, unit and scope; place it on the checked componentName or mealTotal. Component amounts/counts must not move to a containing meal. Natural portions and package fractions retain their scopes. Estimate missing amounts separately. Never replace or reinterpret a checked binding."

    init(context: FoodSemanticContext) {
        version = "checked-quantity-binding-v1"
        description = context.description
        quantities = context.userQuantities.map { FoodQuantityAttachment($0) }
    }
}
