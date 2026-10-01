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
