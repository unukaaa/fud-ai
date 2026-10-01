import Foundation

/// Independent interpretation evidence. A cooking verb need not describe the
/// state at which an ingredient was weighed. No food-name exception table.
struct AsEatenPreparationEvidence: Sendable {
    enum Mode: Sendable { case exactSource, estimate }
    enum Context: Sendable { case ordinaryMeal, recipeIngredient, genuinelyAmbiguous }
    enum AmountRelationship: Sendable { case consumedFood, ingredientBeforeCooking, unspecified }
    let mode: Mode
    let context: Context
    let relationship: AmountRelationship
    let explicitUserBasis: FoodPreparationBasis?
    let exactSourceBasis: FoodPreparationBasis?
    let supportedBases: Set<FoodPreparationBasis>
}

struct AsEatenPreparationAssessment: Sendable {
    let basis: FoodPreparationBasis?
    let requiresClarification: Bool
    let assumption: String?
    let reason: String
}

enum AsEatenPreparationPolicy {
    static let version = "as-eaten-v1"

    static func assess(_ evidence: AsEatenPreparationEvidence) -> AsEatenPreparationAssessment {
        func result(_ basis: FoodPreparationBasis?, _ reason: String, estimated: Bool = false,
                    clarify: Bool = false) -> AsEatenPreparationAssessment {
            AsEatenPreparationAssessment(basis: basis, requiresClarification: clarify,
                assumption: estimated ? "Estimate Mode interpretation: \(reason); amount basis \(basis?.rawValue ?? "unresolved")." : nil,
                reason: reason)
        }
        // An exact label/source's basis is never converted by a consumer convention.
        if let source = evidence.exactSourceBasis {
            return result(source, "exact_source_basis_retained",
                clarify: evidence.explicitUserBasis.map { $0 != source } ?? false)
        }
        if let explicit = evidence.explicitUserBasis, explicit != .unknown {
            return result(explicit, "explicit_user_basis")
        }
        guard evidence.mode == .estimate else {
            return result(nil, "exact_mode_remains_strict", clarify: evidence.supportedBases.count > 1)
        }
        if evidence.relationship == .ingredientBeforeCooking || evidence.context == .recipeIngredient {
            if evidence.supportedBases.contains(.dry) { return result(.dry, "pre_cook_ingredient_amount", estimated: true) }
            if evidence.supportedBases.contains(.raw) { return result(.raw, "pre_cook_ingredient_amount", estimated: true) }
            return result(nil, "unsupported_pre_cook_basis", clarify: true)
        }
        if evidence.context == .ordinaryMeal {
            if evidence.supportedBases.contains(.cooked) { return result(.cooked, "ordinary_meal_as_eaten", estimated: true) }
            let supported = evidence.supportedBases.subtracting([.unknown])
            if supported.count == 1 { return result(supported.first, "single_supported_as_eaten_basis", estimated: true) }
        }
        return result(nil, "preparation_unresolved", clarify: evidence.supportedBases.count > 1)
    }
}
