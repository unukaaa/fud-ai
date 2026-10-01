import Foundation

/// A representative profile, not a selected food identity or population-weighted
/// expectation. No independent per-nutrient medians or envelope midpoints.
struct GroundedComponentPoint: Sendable {
    enum Method: String, Sendable { case exactSource, scopedSingleRecord, energyOrderedProfileMedian }
    let nutrition: NutritionFacts
    let method: Method
    let evidence: [GroundedSourceResolution]
    let contributors: [GroundedSourceResolution]
    let weights: [Double]
    let envelope: GroundedNutritionEnvelope
    let assumptions: [String]
    let uncertainty: [String]
}

struct GroundedPointMeal: Sendable {
    let grounding: EstimateGroundedMealResult
    let points: [GroundedComponentPoint?]
    /// Diagnostic partial sum only. Consumers must use completeNutrition.
    let availablePoint: NutritionFacts?
    let completeNutrition: NutritionFacts?
    let evidence: GroundedMealResult.Evidence
    let reasons: [String]
    let validatedInput: ValidatedFoodProposal
    var loggable: Bool { completeNutrition != nil }
}

enum GroundedPointEstimatePolicy {
    static let version = "energy-ordered-whole-profile-median-v1"

    static func point(for component: EstimateGroundedComponentResult) -> GroundedComponentPoint? {
        if let source = component.exactResult.source, usable(source.nutrition),
           let envelope = component.envelope {
            return GroundedComponentPoint(nutrition: source.nutrition, method: .exactSource,
                evidence: [source], contributors: [source], weights: [1], envelope: envelope,
                assumptions: component.exactResult.input.assumptions,
                uncertainty: component.exactResult.input.amount?.provenance == .estimated ? ["Amount estimated."] : [])
        }
        guard let basis = component.estimateBasis, !basis.candidates.isEmpty,
              basis.candidates.allSatisfy({ usable($0.nutrition) }),
              Set(basis.candidateSourceIDs).count == basis.candidates.count,
              Set(basis.candidates.map(\.sourceVersion)).count == 1,
              basis.candidates.allSatisfy({ $0.sourceVersion?.isEmpty == false }),
              GroundedNutritionEnvelope.enclosing(basis.candidates.map(\.nutrition)) == basis.envelope else { return nil }
        // Compatibility is established by EstimateGroundingPolicy, not by sorting.
        let ordered = basis.candidates.sorted { lhs, rhs in
            let a = profile(lhs.nutrition), b = profile(rhs.nutrition)
            if a != b { return a.lexicographicallyPrecedes(b) }
            return String(describing: lhs.sourceID) < String(describing: rhs.sourceID)
        }
        let middle = ordered.count / 2
        let contributors = ordered.count.isMultiple(of: 2) ? [ordered[middle - 1], ordered[middle]] : [ordered[middle]]
        let weights = contributors.count == 2 ? [0.5, 0.5] : [1.0]
        guard let nutrition = NutritionFacts.adding(zip(contributors, weights).map { $0.nutrition.scaled(by: $1) }),
              usable(nutrition) else { return nil }
        return GroundedComponentPoint(nutrition: nutrition,
            method: ordered.count == 1 ? .scopedSingleRecord : .energyOrderedProfileMedian,
            evidence: basis.candidates, contributors: contributors, weights: weights,
            envelope: basis.envelope, assumptions: component.exactResult.input.assumptions + basis.assumptions,
            uncertainty: basis.uncertainty + ["Representative estimate only; not an exact variant identity.",
                "Uniform source-record weighting is not evidence of population prevalence.",
                "Fixed-amount source range does not include portion or missing-recipe uncertainty."])
    }

    /// Gate accepts only a firewall-approved proposal; all declared components and
    /// amount evidence must survive. Missing components cannot become a whole meal.
    static func evaluate(_ validated: ValidatedFoodProposal,
                         grounding: (ValidatedFoodProposal) -> EstimateGroundedMealResult) -> GroundedPointMeal {
        let result = grounding(validated)
        var reasons: [String] = []
        if result.components.count != validated.proposal.components.count { reasons.append("component_coverage_mismatch") }
        for (proposal, component) in zip(validated.proposal.components, result.components) {
            if proposal.name != component.exactResult.input.description { reasons.append("component_identity_binding_mismatch") }
            let quantity = proposal.userAmount.flatMap { $0.unit == .grams ? $0 : nil } ?? proposal.estimatedAmount
            let amount = component.exactResult.input.amount
            if quantity?.unit != .grams || quantity?.scope != .componentAmount || amount?.unit != .grams
                || amount?.value != quantity?.value || amount?.isValid != true {
                reasons.append("unsupported_or_changed_amount_basis:\(proposal.id)")
            } else {
                let expected: GroundedAmountProvenance = proposal.userAmount?.unit == .grams ? .user : .estimated
                if amount?.provenance != expected { reasons.append("amount_provenance_changed:\(proposal.id)") }
            }
        }
        let points = result.components.map { point(for: $0) }
        let available = NutritionFacts.adding(points.compactMap { $0?.nutrition }).flatMap { usable($0) ? $0 : nil }
        let complete = result.complete && reasons.isEmpty && !points.isEmpty && points.allSatisfy { $0 != nil }
        return GroundedPointMeal(grounding: result, points: points, availablePoint: available,
            completeNutrition: complete ? available : nil,
            evidence: complete && available != nil ? result.evidence : .estimate,
            reasons: reasons + (complete ? [] : ["meal_incomplete"]), validatedInput: validated)
    }

    /// Natural counts/fractions remain in validatedInput. A separate model-estimated
    /// edible gram amount is usable but never called a source serving/conversion.
    static func components(from validated: ValidatedFoodProposal) -> [EstimateGroundedComponent] {
        validated.proposal.components.map { c in
            let q = c.userAmount.flatMap { $0.unit == .grams ? $0 : nil } ?? c.estimatedAmount
            let amount = q.flatMap { $0.unit == .grams && $0.scope == .componentAmount ?
                GroundedAmount(value: $0.value, unit: .grams, provenance: c.userAmount?.unit == .grams ? .user : .estimated) : nil }
            return EstimateGroundedComponent(exactInput: GroundedComponentInput(description: c.name,
                sourceID: nil, amount: amount, estimatedNutrition: nil, assumptions: c.assumptions),
                scopedEstimateQuery: c.preparation == .unknown ? nil : c.name +
                    (c.preparation == .other ? "" : " " + c.preparation.rawValue))
        }
    }

    private static func profile(_ n: NutritionFacts) -> [Double] {
        [n.calories!, n.proteinGrams!, n.carbohydrateGrams!, n.fatGrams!]
    }
    private static func usable(_ n: NutritionFacts) -> Bool {
        [n.calories, n.proteinGrams, n.carbohydrateGrams, n.fatGrams].allSatisfy { $0.map { $0.isFinite && $0 >= 0 } ?? false }
    }
}
