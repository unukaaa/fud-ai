import Foundation

/// Keeps source coverage separate from the existing matching/derivation confidence.
/// Only AUSNUT presentation is changed; other source classes retain their UI rules.
struct AUSNUTSourcePresentation {
    enum Coverage: Equatable {
        case full, partial, notAUSNUT
    }

    let coverage: Coverage
    let resolutionConfidence: String

    init(source: String, confidence: String, ingredients: [MealIngredient]) {
        resolutionConfidence = confidence
        guard source == "AUSNUT Australia" else {
            coverage = .notAUSNUT
            return
        }
        // Derivation/match confidence is not source coverage. An exact AUSNUT
        // record has no ingredient breakdown; a resolved meal is only fully
        // sourced when every ingredient has an AUSNUT source.
        coverage = ingredients.isEmpty || ingredients.allSatisfy {
            $0.nutritionSource == "AUSNUT Australia"
        } ? .full : .partial
    }

    var badge: String? {
        switch coverage {
        case .full: "✓ AUSNUT"
        case .partial: "⚠️ Partially AUSNUT"
        case .notAUSNUT: nil
        }
    }
}
