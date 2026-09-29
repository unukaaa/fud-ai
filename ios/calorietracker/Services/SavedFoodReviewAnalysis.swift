import Foundation

extension FoodNutritionProvenance {
    static let legacyDisplaySource = "Source not recorded"

    static func capture(
        source: String,
        detail: String?,
        confidence: String,
        proteinIsKnown: Bool,
        carbsAreKnown: Bool,
        fatIsKnown: Bool,
        foodComponents: [FoodResolutionComponent] = [],
        restaurantComponents: [RestaurantResolvedComponent] = []
    ) -> Self {
        let classification: Classification
        switch source {
        case "Verified restaurant nutrition":
            classification = confidence == "High" && proteinIsKnown && carbsAreKnown && fatIsKnown
                ? .verifiedRestaurant : .partiallyVerifiedRestaurant
        case "AUSNUT Australia": classification = .ausnut
        case "AI estimate": classification = .aiEstimate
        case "Structured estimate": classification = .structuredEstimate
        case "Mixed nutrition sources": classification = .mixed
        case "Nutrition label": classification = .nutritionLabel
        case "Open Food Facts": classification = .barcode
        case legacyDisplaySource: classification = .unknown
        default: classification = .other
        }

        var references: [SourceReference] = []
        for component in foodComponents {
            guard let itemID = component.sourceItemID else { continue }
            let type: SourceType
            switch component.state {
            case .verifiedRestaurant, .partiallyVerifiedRestaurant: type = .restaurant
            case .ausnut: type = .ausnut
            default: continue
            }
            references.append(SourceReference(sourceType: type, itemID: itemID, componentID: nil))
        }
        for component in restaurantComponents {
            guard let itemID = component.sourceItemID else { continue }
            references.append(SourceReference(
                sourceType: .restaurant, itemID: itemID, componentID: component.groupID
            ))
        }
        return Self(
            classification: classification, displaySource: source, detail: detail,
            confidence: confidence, proteinIsKnown: proteinIsKnown,
            carbsAreKnown: carbsAreKnown, fatIsKnown: fatIsKnown,
            sourceReferences: references
        )
    }
}

extension GeminiService.FoodAnalysis {
    var historicalProvenanceSnapshot: FoodNutritionProvenance {
        if let savedNutritionProvenance { return savedNutritionProvenance }
        return FoodNutritionProvenance.capture(
            source: nutritionSource, detail: nutritionSourceDetail,
            confidence: nutritionConfidence, proteinIsKnown: proteinIsKnown,
            carbsAreKnown: carbsAreKnown, fatIsKnown: fatIsKnown,
            foodComponents: foodResolutionComponents,
            restaurantComponents: resolvedComponents
        )
    }
}

extension FoodEntry {
    /// Reopen the values and the source claim accepted with this saved entry.
    /// Source IDs are retained for traceability, never for silent re-resolution.
    func analysisForRepeatReview() -> GeminiService.FoodAnalysis {
        let provenance = nutritionProvenance
        var analysis = GeminiService.FoodAnalysis(
            name: name, calories: calories, protein: protein, carbs: carbs, fat: fat,
            servingSizeGrams: reviewServingReference, emoji: emoji,
            sugar: sugar, addedSugar: addedSugar, fiber: fiber,
            saturatedFat: saturatedFat, monounsaturatedFat: monounsaturatedFat,
            polyunsaturatedFat: polyunsaturatedFat, cholesterol: cholesterol,
            caffeine: caffeine, supplementalNutrients: supplementalNutrients,
            sodium: sodium, potassium: potassium, transFat: transFat,
            calcium: calcium, iron: iron, magnesium: magnesium, zinc: zinc,
            vitaminA: vitaminA, vitaminC: vitaminC, vitaminD: vitaminD,
            vitaminB12: vitaminB12, vitaminE: vitaminE, vitaminK: vitaminK,
            folate: folate, omega3: omega3,
            servingUnitOptions: reviewServingUnitOptions,
            selectedServingUnit: reviewSelectedServingUnit,
            selectedServingQuantity: reviewSelectedServingQuantity,
            servingSizeIsKnown: hasKnownServingSize,
            progressiveMeal: progressiveMeal, ingredients: ingredients,
            productMetadata: productMetadata,
            nutritionSource: provenance?.displaySource ?? FoodNutritionProvenance.legacyDisplaySource,
            nutritionSourceDetail: provenance?.detail,
            nutritionConfidence: provenance?.confidence ?? "Unknown",
            proteinIsKnown: provenance?.proteinIsKnown ?? true,
            carbsAreKnown: provenance?.carbsAreKnown ?? true,
            fatIsKnown: provenance?.fatIsKnown ?? true
        )
        analysis.savedNutritionProvenance = provenance
        return analysis
    }
}
