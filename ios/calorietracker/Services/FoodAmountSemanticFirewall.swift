import Foundation

enum FoodAmountScope: String, Codable, Sendable {
    case componentAmount, mealTotalAmount, servingCount, packageFraction, naturalPortion, unknownScope
}

enum FoodSemanticUnit: String, Codable, Sendable {
    case grams, millilitres, count, fraction
}

enum FoodPreparationBasis: String, Codable, Sendable {
    case unknown, raw, dry, cooked, drained, fried, other
}

/// Independent caller evidence, not authority created by the provider's echo.
struct ExplicitFoodQuantity: Codable, Equatable, Sendable {
    let id: String
    let originalText: String
    let value: Double
    let unit: FoodSemanticUnit
    let scope: FoodAmountScope
    let componentName: String?
}

struct FoodQuantityProposal: Codable, Equatable, Sendable {
    let evidenceID: String?
    let originalText: String?
    let value: Double
    let unit: FoodSemanticUnit
    let scope: FoodAmountScope
}

struct FoodComponentProposal: Codable, Equatable, Sendable {
    let id: String
    let name: String
    let preparation: FoodPreparationBasis
    let preparationText: String?
    let userAmount: FoodQuantityProposal?
    let estimatedAmount: FoodQuantityProposal?
    let assumptions: [String]
}

/// No source IDs, nutrition or model confidence can confer source authority here.
struct FoodMealProposal: Codable, Equatable, Sendable {
    let components: [FoodComponentProposal]
    let mealTotal: FoodQuantityProposal?
    let question: String?
    let assumptions: [String]
}

/// Supplied by the trusted retrieval/user-evidence adapter, never decoded from a model.
struct FoodPreparationConstraint: Sendable {
    let componentName: String
    let explicitBasis: FoodPreparationBasis?
    let explicitText: String?
    let candidateBases: Set<FoodPreparationBasis>
    let materialVariantUnresolved: Bool
    let candidateSourceIDs: [GroundedSourceID]
    /// Opt-in Estimate Mode interpretation from independent user/source context.
    /// Nil preserves the strict pre-existing contract.
    var estimateInterpretation: AsEatenPreparationEvidence? = nil
}

struct FoodSemanticContext: Sendable {
    let description: String
    let userQuantities: [ExplicitFoodQuantity]
    let preparationConstraints: [FoodPreparationConstraint]
}

struct ValidatedFoodProposal: Sendable {
    let proposal: FoodMealProposal
    let context: FoodSemanticContext
    fileprivate init(proposal: FoodMealProposal, context: FoodSemanticContext) {
        self.proposal = proposal
        self.context = context
    }
}

struct FoodSemanticAssessment: Sendable {
    enum Outcome: String, Sendable {
        case valid, repairable, clarificationRequired, estimateWithUncertainty, invalidProviderOutput
    }
    let outcome: Outcome
    let reasons: [String]
    let original: FoodMealProposal
    let accepted: ValidatedFoodProposal?
}

/// Meaning checks precede all retrieval/arithmetic. This is not an NLP quantity
/// extractor: the caller must provide independent, checked user/source evidence.
enum FoodAmountSemanticFirewall {
    static let version = "amount-preparation-semantic-v1"

    static func assess(_ proposal: FoodMealProposal, context: FoodSemanticContext) -> FoodSemanticAssessment {
        var invalid: [String] = []
        var clarify: [String] = []
        var uncertainty: [String] = []
        var repairs: [String] = []
        var used: Set<String> = []
        let evidence = context.userQuantities
        if Set(evidence.map(\.id)).count != evidence.count { invalid.append("duplicate_user_evidence") }
        if proposal.components.isEmpty || Set(proposal.components.map(\.id)).count != proposal.components.count {
            invalid.append("empty_or_duplicate_components")
        }
        for item in evidence {
            if item.id.isEmpty || item.originalText.isEmpty || !context.description.contains(item.originalText)
                || !validQuantity(item.value, unit: item.unit, scope: item.scope) {
                invalid.append("invalid_independent_user_evidence:\(item.id)")
            }
        }
        func checkEcho(_ q: FoodQuantityProposal, component: String?) {
            guard let id = q.evidenceID, let source = evidence.first(where: { $0.id == id }) else {
                invalid.append("unrecognised_user_quantity"); return
            }
            guard used.insert(id).inserted else { invalid.append("user_quantity_counted_twice:\(id)"); return }
            if q.value != source.value || q.unit != source.unit || q.scope != source.scope
                || q.originalText != source.originalText {
                invalid.append("explicit_quantity_reinterpreted:\(id)")
            }
            if source.scope == .mealTotalAmount {
                if component != nil { invalid.append("meal_total_assigned_to_component:\(id)") }
            } else if source.scope == .unknownScope {
                clarify.append("unknown_quantity_scope:\(id)")
            } else if let target = source.componentName, let component, matches(target, component) {
                // Exact user amount remains the calculation basis, not the estimate.
            } else {
                invalid.append("wrong_quantity_target:\(id)")
            }
        }
        if let total = proposal.mealTotal { checkEcho(total, component: nil) }
        var normalised: [FoodComponentProposal] = []
        for c in proposal.components {
            if c.id.isEmpty || c.name.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty {
                invalid.append("malformed_component")
            }
            if let q = c.userAmount { checkEcho(q, component: c.name) }
            var estimate = c.estimatedAmount
            var preparation = c.preparation
            var assumptions = c.assumptions
            if let q = estimate {
                if q.evidenceID != nil || q.originalText != nil
                    || !validQuantity(q.value, unit: q.unit, scope: q.scope)
                    || q.scope == .mealTotalAmount || q.scope == .unknownScope {
                    invalid.append("invalid_estimated_amount:\(c.id)")
                }
                if let user = c.userAmount, [.grams, .millilitres].contains(user.unit) {
                    // The ONLY repair: remove redundant provider estimate. No scaling,
                    // density conversion, redistribution or invented quantity.
                    estimate = nil
                    repairs.append("discard_redundant_estimate_preserve_user_amount:\(c.id)")
                } else {
                    uncertainty.append("estimated_amount:\(c.id)")
                }
            }
            if c.userAmount == nil && estimate == nil { uncertainty.append("amount_unresolved:\(c.id)") }
            for constraint in context.preparationConstraints where matches(constraint.componentName, c.name) {
                guard !constraint.candidateSourceIDs.isEmpty else {
                    invalid.append("missing_preparation_source_evidence:\(c.id)"); continue
                }
                if let explicit = constraint.explicitBasis {
                    guard let text = constraint.explicitText, !text.isEmpty, context.description.contains(text) else {
                        invalid.append("invalid_explicit_preparation_evidence:\(c.id)"); continue
                    }
                    if c.preparation != explicit || c.preparationText != text {
                        invalid.append("explicit_preparation_changed:\(c.id)")
                    }
                }
                if let interpretation = constraint.estimateInterpretation {
                    let state = AsEatenPreparationPolicy.assess(interpretation)
                    if state.requiresClarification { clarify.append("preparation_interpretation_unresolved:\(c.id)") }
                    if let basis = state.basis {
                        if preparation == .unknown {
                            preparation = basis
                            repairs.append("retain_independent_preparation_interpretation:\(c.id)")
                        } else if preparation != basis { invalid.append("amount_preparation_basis_conflict:\(c.id)") }
                    }
                    if let assumption = state.assumption { assumptions.append(assumption); uncertainty.append("as_eaten_assumption:\(c.id)") }
                } else if constraint.explicitBasis == nil && constraint.candidateBases.contains(.dry) && constraint.candidateBases.contains(.cooked) {
                    clarify.append("dry_or_cooked_basis:\(c.id)")
                }
                if constraint.materialVariantUnresolved { clarify.append("material_source_variant:\(c.id)") }
            }
            if c.preparation == .unknown { uncertainty.append("preparation_unresolved:\(c.id)") }
            normalised.append(FoodComponentProposal(id: c.id, name: c.name, preparation: preparation,
                preparationText: c.preparationText, userAmount: c.userAmount, estimatedAmount: estimate,
                assumptions: assumptions))
        }
        for item in evidence where !used.contains(item.id) { invalid.append("explicit_quantity_omitted:\(item.id)") }
        if let total = proposal.mealTotal, total.scope == .mealTotalAmount {
            if ![.grams, .millilitres].contains(total.unit) { invalid.append("uncomparable_meal_total") }
            var amounts: [Double] = []
            for c in normalised {
                let q = c.userAmount.flatMap { $0.unit == total.unit ? $0 : nil } ?? c.estimatedAmount
                guard let q, q.unit == total.unit else {
                    invalid.append("meal_allocation_missing_or_incompatible_unit:\(c.id)"); continue
                }
                amounts.append(q.value)
            }
            let sum = amounts.reduce(0, +)
            // Machine arithmetic tolerance only, NOT a portion/nutrition tolerance.
            let tolerance = max(abs(total.value), 1) * Double.ulpOfOne * Double(max(amounts.count, 1)) * 8
            if !sum.isFinite || sum > total.value + tolerance { invalid.append("component_sum_exceeds_meal_total") }
            else if amounts.count == normalised.count && abs(sum - total.value) > tolerance {
                invalid.append("meal_total_not_fully_allocated")
            }
        }
        let outcome: FoodSemanticAssessment.Outcome
        if !invalid.isEmpty { outcome = .invalidProviderOutput }
        else if !clarify.isEmpty { outcome = .clarificationRequired }
        else if !repairs.isEmpty { outcome = .repairable }
        else if !uncertainty.isEmpty { outcome = .estimateWithUncertainty }
        else { outcome = .valid }
        let accepted = invalid.isEmpty && clarify.isEmpty ? ValidatedFoodProposal(
            proposal: FoodMealProposal(components: normalised, mealTotal: proposal.mealTotal,
                question: proposal.question, assumptions: proposal.assumptions), context: context) : nil
        return FoodSemanticAssessment(outcome: outcome, reasons: invalid + clarify + repairs + uncertainty,
            original: proposal, accepted: accepted)
    }

    private static func validQuantity(_ value: Double, unit: FoodSemanticUnit, scope: FoodAmountScope) -> Bool {
        guard value.isFinite, value > 0 else { return false }
        switch scope {
        case .componentAmount, .mealTotalAmount: return unit == .grams || unit == .millilitres
        case .servingCount, .naturalPortion: return unit == .count
        case .packageFraction: return unit == .fraction && value <= 1
        case .unknownScope: return true
        }
    }

    private static func matches(_ target: String, _ component: String) -> Bool {
        func tokens(_ value: String) -> Set<String> {
            Set(value.lowercased().split(whereSeparator: { !$0.isLetter && !$0.isNumber }).map(String.init))
        }
        let wanted = tokens(target)
        return !wanted.isEmpty && wanted.isSubset(of: tokens(component))
    }
}

struct SemanticGroundingAttempt: Sendable {
    let assessment: FoodSemanticAssessment
    let newResult: EstimateGroundedMealResult?
    /// Independent prior work, NOT a complete result for the rejected current meal.
    let preservedPriorProgress: EstimateGroundedMealResult?
}

enum SemanticGroundingGateway {
    static func evaluate(_ proposal: FoodMealProposal, context: FoodSemanticContext,
                         priorProgress: EstimateGroundedMealResult? = nil,
                         grounding: (ValidatedFoodProposal) -> EstimateGroundedMealResult) -> SemanticGroundingAttempt {
        let assessment = FoodAmountSemanticFirewall.assess(proposal, context: context)
        return SemanticGroundingAttempt(assessment: assessment,
            newResult: assessment.accepted.map(grounding), preservedPriorProgress: priorProgress)
    }
}
