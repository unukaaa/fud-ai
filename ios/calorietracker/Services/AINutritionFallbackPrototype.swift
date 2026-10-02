import Foundation
import CryptoKit

/// Independent eligibility review, NOT a provider decision or a convenient
/// response to low retrieval coverage. No permission is granted by default.
enum AINutritionFallbackReason: String, Codable, Sendable {
    case noApprovedRepresentativeBasis, noUsefulTrustedNutrition
    case representationPending, retrievalPending
    var permitsEstimate: Bool {
        self == .noApprovedRepresentativeBasis || self == .noUsefulTrustedNutrition
    }
}

struct AIComponentNutritionRequest: Codable, Sendable {
    let requestID: String
    let componentID: String
    let description: String
    let mealContext: String
    let preparation: FoodPreparationBasis
    let preparationText: String?
    let consumedGrams: Double
    let amountProvenance: String
    let originalUserQuantity: FoodQuantityProposal?
    let fallbackReason: AINutritionFallbackReason
    let trustedCandidateIDs: [String]
    let assumptions: [String]
    static let version = "consumed-component-ai-nutrition-v1"

    fileprivate init(_ c: FoodComponentProposal, context: FoodSemanticContext,
                     amount: GroundedAmount, reason: AINutritionFallbackReason, candidates: [String]) {
        componentID = c.id; description = c.name; mealContext = context.description
        preparation = c.preparation; preparationText = c.preparationText
        consumedGrams = amount.value; amountProvenance = String(describing: amount.provenance)
        originalUserQuantity = c.userAmount; fallbackReason = reason
        trustedCandidateIDs = candidates.sorted(); assumptions = c.assumptions
        // Binding includes the independent meal context and original quantity.
        // Deterministic IDs permit offline replay without reinterpreting inputs.
        let encoder = JSONEncoder(); encoder.outputFormatting = [.sortedKeys]
        let quantity = (try? encoder.encode(c.userAmount)).map { String(decoding: $0, as: UTF8.self) } ?? "null"
        let fields = [Self.version, c.id, c.name, context.description, c.preparation.rawValue,
                      c.preparationText ?? "", String(amount.value), amountProvenance, quantity,
                      reason.rawValue] + trustedCandidateIDs + c.assumptions
        requestID = SHA256.hash(data: (try? encoder.encode(fields)) ?? Data()).map { String(format: "%02x", $0) }.joined()
    }
}

/// ONE canonical basis: nutrition for consumedGrams of ONE component. Not per
/// 100 g, not a recipe/meal total, and never authoritative/source nutrition.
struct AIComponentNutritionProposal: Codable, Sendable {
    let requestID: String
    let componentID: String
    let description: String
    let basis: String
    let preparation: FoodPreparationBasis
    let preparationText: String?
    let consumedGrams: Double
    let amountProvenance: String
    let originalUserQuantity: FoodQuantityProposal?
    let calories: Double
    let protein: Double
    let carbohydrate: Double
    let fat: Double
    let calorieLower: Double
    let calorieUpper: Double
    let assumptions: [String]
    let uncertainty: [String]
}

/// Supplied by the caller/transport, not invented by model JSON.
struct AINutritionProviderMetadata: Codable, Sendable {
    let provider: String
    let model: String
    let timestamp: Date
    let contractVersion: String
}

struct AIComponentNutritionResponse: Sendable {
    let proposal: AIComponentNutritionProposal
    let metadata: AINutritionProviderMetadata
}

struct ValidatedAIComponentNutrition: Sendable {
    let request: AIComponentNutritionRequest
    let response: AIComponentNutritionResponse
    let nutrition: NutritionFacts
    let diagnostics: [String]
    fileprivate init(request: AIComponentNutritionRequest, response: AIComponentNutritionResponse) {
        self.request = request; self.response = response
        let p = response.proposal
        nutrition = NutritionFacts(calories: p.calories, proteinGrams: p.protein,
                                   carbohydrateGrams: p.carbohydrate, fatGrams: p.fat)
        diagnostics = ["AI estimate, not sourced/verified.", "Calorie range is model-estimated, not a statistical confidence interval.",
                       "4/4/9 sanity check does not measure nutrition accuracy or model fibre/alcohol contributions."]
    }
}

struct AINutritionValidation: Sendable {
    enum Outcome: String, Sendable { case valid, requiresReview, invalid }
    let outcome: Outcome
    let reasons: [String]
    let accepted: ValidatedAIComponentNutrition?
}

enum AIComponentNutritionValidator {
    static func assess(_ response: AIComponentNutritionResponse, for request: AIComponentNutritionRequest) -> AINutritionValidation {
        let p = response.proposal, m = response.metadata
        var invalid: [String] = []
        if p.requestID != request.requestID || p.componentID != request.componentID || p.description != request.description {
            invalid.append("component_binding_changed")
        }
        if p.basis != "consumedComponent" || p.consumedGrams != request.consumedGrams
            || p.amountProvenance != request.amountProvenance || p.originalUserQuantity != request.originalUserQuantity {
            invalid.append("consumed_amount_or_original_quantity_changed")
        }
        if p.preparation != request.preparation || p.preparationText != request.preparationText { invalid.append("preparation_changed") }
        if [p.consumedGrams, p.calories, p.protein, p.carbohydrate, p.fat, p.calorieLower, p.calorieUpper].contains(where: { !$0.isFinite || $0 < 0 })
            || p.consumedGrams <= 0 { invalid.append("nonfinite_or_negative_nutrition") }
        if p.calorieLower > p.calories || p.calorieUpper < p.calories { invalid.append("range_does_not_enclose_point") }
        if p.assumptions.isEmpty || p.uncertainty.isEmpty { invalid.append("missing_estimate_uncertainty") }
        if m.provider.isEmpty || m.model.isEmpty || !m.timestamp.timeIntervalSince1970.isFinite
            || m.contractVersion != AIComponentNutritionRequest.version { invalid.append("missing_caller_metadata") }
        // Conservative mass/energy ceilings, not nutrition-accuracy thresholds.
        // Protein + available carbohydrate + fat cannot exceed edible mass.
        // 9 kcal/g is a broad ceiling above the FSANZ 37 kJ/g fat factor.
        let epsilon = max(request.consumedGrams, 1) * Double.ulpOfOne * 16
        if p.protein + p.carbohydrate + p.fat > request.consumedGrams + epsilon { invalid.append("macros_exceed_consumed_mass") }
        if p.calorieUpper > request.consumedGrams * 9 + epsilon { invalid.append("energy_exceeds_consumed_mass_ceiling") }
        let macroEnergy = p.protein * 4 + p.carbohydrate * 4 + p.fat * 9
        if !invalid.isEmpty { return AINutritionValidation(outcome: .invalid, reasons: invalid, accepted: nil) }
        // No perfect Atwater equality. The model's own uncertainty range must
        // permit approximate macro energy; otherwise human review, not auto-fix.
        if macroEnergy < p.calorieLower || macroEnergy > p.calorieUpper {
            return AINutritionValidation(outcome: .requiresReview,
                reasons: ["macro_energy_outside_estimated_range_fibre_alcohol_rounding_need_review"], accepted: nil)
        }
        return AINutritionValidation(outcome: .valid, reasons: [],
            accepted: ValidatedAIComponentNutrition(request: request, response: response))
    }
}

struct AINutritionFallbackMeal: Sendable {
    struct Component: Sendable {
        let id: String
        let name: String
        let trustedPoint: GroundedComponentPoint?
        let aiEstimate: ValidatedAIComponentNutrition?
        let reasons: [String]
        var nutrition: NutritionFacts? { trustedPoint?.nutrition ?? aiEstimate?.nutrition }
    }
    let assessment: FoodSemanticAssessment
    let trustedProgress: GroundedPointMeal?
    let preservedPriorProgress: GroundedPointMeal?
    let components: [Component]
    let requests: [AIComponentNutritionRequest]
    /// Diagnostic only; must never be published as complete meal nutrition.
    let availableNutrition: NutritionFacts?
    let completeNutrition: NutritionFacts?
    let evidence: GroundedMealResult.Evidence
    var loggable: Bool { completeNutrition != nil }
}

/// Offline/injected prototype only. No networking, production routing, source
/// mutation or persistence. Permissions require an independent blocker review.
enum AINutritionFallbackPrototype {
    static func evaluate(_ proposal: FoodMealProposal, context: FoodSemanticContext,
                         permissions: [String: AINutritionFallbackReason],
                         priorProgress: GroundedPointMeal? = nil,
                         grounding: (ValidatedFoodProposal) -> EstimateGroundedMealResult = {
                             EstimateGroundedMealEngine.evaluate(GroundedPointEstimatePolicy.components(from: $0))
                         },
                         fallback: (AIComponentNutritionRequest) -> AIComponentNutritionResponse? = { _ in nil }) -> AINutritionFallbackMeal {
        let assessment = FoodAmountSemanticFirewall.assess(proposal, context: context)
        guard let valid = assessment.accepted else {
            return AINutritionFallbackMeal(assessment: assessment, trustedProgress: nil, preservedPriorProgress: priorProgress,
                components: [], requests: [], availableNutrition: nil, completeNutrition: nil, evidence: .estimate)
        }
        // Both exact and trusted-envelope attempts occur inside the existing
        // estimate grounding engine, before any third-lane request can exist.
        let trusted = GroundedPointEstimatePolicy.evaluate(valid, grounding: grounding)
        let bindingsSafe = trusted.reasons.allSatisfy { $0 == "meal_incomplete" }
        var requests: [AIComponentNutritionRequest] = []
        var components: [AINutritionFallbackMeal.Component] = []
        let inputs = GroundedPointEstimatePolicy.components(from: valid)
        for (i, c) in valid.proposal.components.enumerated() {
            let point = trusted.points.indices.contains(i) ? trusted.points[i] : nil
            var ai: ValidatedAIComponentNutrition?
            var reasons: [String] = []
            if point == nil {
                if !bindingsSafe { reasons.append("trusted_component_or_amount_binding_unsafe") }
                else if valid.proposal.question != nil { reasons.append("clarification_pending") }
                else if c.preparation == .unknown { reasons.append("preparation_unresolved") }
                else if let reason = permissions[c.id], reason.permitsEstimate,
                        let amount = inputs[i].exactInput.amount, amount.isValid, amount.unit == .grams {
                    let candidates = inputs[i].partitionContext.flatMap { ctx in
                        AustralianNutritionService.searchableIdentities.map { EstimateCandidatePartition.assess(ctx, identities: $0).partitions.flatMap(\.candidates).map(\.sourceID) }
                    } ?? []
                    let request = AIComponentNutritionRequest(c, context: context, amount: amount, reason: reason, candidates: candidates)
                    requests.append(request)
                    if let response = fallback(request) {
                        let validation = AIComponentNutritionValidator.assess(response, for: request)
                        ai = validation.accepted; reasons += validation.reasons
                    } else { reasons.append("fallback_unavailable_preserve_trusted_progress") }
                } else { reasons.append("not_independently_authorized_or_amount_unresolved") }
            }
            components.append(.init(id: c.id, name: c.name, trustedPoint: point, aiEstimate: ai, reasons: reasons))
        }
        let available = NutritionFacts.adding(components.compactMap(\.nutrition))
        let complete = bindingsSafe && valid.proposal.question == nil && !components.isEmpty
            && components.allSatisfy { $0.nutrition != nil }
        let anyAI = components.contains { $0.aiEstimate != nil }
        return AINutritionFallbackMeal(assessment: assessment, trustedProgress: trusted, preservedPriorProgress: priorProgress,
            components: components, requests: requests, availableNutrition: available,
            completeNutrition: complete ? available : nil,
            evidence: complete && !anyAI ? trusted.evidence : .estimate)
    }
}
