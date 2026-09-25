import Foundation

enum NutritionSourceType: String, Codable, Equatable, Sendable {
    case verifiedRestaurant
    case ausnut
    case structuredEstimate
    case aiEstimate
    case barcode
    case nutritionLabel
}

struct NutritionFacts: Codable, Equatable, Sendable {
    var calories: Double?
    var kilojoules: Double?
    var proteinGrams: Double?
    var carbohydrateGrams: Double?
    var fatGrams: Double?
    var otherNutrients: [String: Double] = [:]

    func scaled(by factor: Double) -> NutritionFacts {
        NutritionFacts(
            calories: calories.map { $0 * factor },
            kilojoules: kilojoules.map { $0 * factor },
            proteinGrams: proteinGrams.map { $0 * factor },
            carbohydrateGrams: carbohydrateGrams.map { $0 * factor },
            fatGrams: fatGrams.map { $0 * factor },
            otherNutrients: otherNutrients.mapValues { $0 * factor }
        )
    }

    static func adding(_ values: [NutritionFacts]) -> NutritionFacts? {
        guard values.contains(where: { $0.calories != nil || $0.kilojoules != nil || $0.proteinGrams != nil || $0.carbohydrateGrams != nil || $0.fatGrams != nil }) else { return nil }
        func sum(_ keyPath: KeyPath<NutritionFacts, Double?>) -> Double? {
            let present = values.compactMap { $0[keyPath: keyPath] }
            return present.isEmpty ? nil : present.reduce(0, +)
        }
        var other: [String: Double] = [:]
        for value in values {
            for (key, amount) in value.otherNutrients { other[key, default: 0] += amount }
        }
        return NutritionFacts(calories: sum(\.calories), kilojoules: sum(\.kilojoules), proteinGrams: sum(\.proteinGrams), carbohydrateGrams: sum(\.carbohydrateGrams), fatGrams: sum(\.fatGrams), otherNutrients: other)
    }
}

struct NutritionProvenance: Codable, Equatable, Sendable {
    let sourceType: NutritionSourceType
    let restaurantID: String?
    let sourceURL: String?
    let country: String?
    let capturedDate: String?
    let lastVerifiedDate: String?
    let datasetVersion: String?
    let sourceQuality: String?
}

struct NutritionAssumption: Codable, Equatable, Sendable {
    let key: String
    let value: String
    let grams: Double?
}

struct Restaurant: Codable, Equatable, Sendable, Identifiable {
    let id: String
    let name: String
    let aliases: [String]
    let country: String
}

struct RestaurantComponent: Codable, Equatable, Sendable, Identifiable {
    let id: String
    let name: String
    let aliases: [String]
    let nutrition: NutritionFacts?
    let provenance: NutritionProvenance?
}

struct RestaurantModifier: Codable, Equatable, Sendable, Identifiable {
    let id: String
    let name: String
    let aliases: [String]
    let removesComponentID: String?
    let addsComponentID: String?
    let nutritionDelta: NutritionFacts?
    let provenance: NutritionProvenance?
}

struct RestaurantMenuItemVariant: Codable, Equatable, Sendable, Identifiable {
    let id: String
    let name: String
    let aliases: [String]
    let nutrition: NutritionFacts?
    let provenance: NutritionProvenance?
}

struct RestaurantMealConfiguration: Codable, Equatable, Sendable, Identifiable {
    let id: String
    let name: String
    let aliases: [String]
    let componentIDs: [String]
    let clarificationGroups: [RestaurantClarificationGroup]
}

struct RestaurantMenuItem: Codable, Equatable, Sendable, Identifiable {
    let id: String
    let name: String
    let aliases: [String]
    let category: String
    let servingQuantity: Double?
    let servingUnit: String?
    let servingWeightGrams: Double?
    let nutrition: NutritionFacts?
    let components: [RestaurantComponent]
    let modifiers: [RestaurantModifier]
    let variants: [RestaurantMenuItemVariant]
    let mealConfigurations: [RestaurantMealConfiguration]
    let provenance: NutritionProvenance?
}

struct RestaurantDatasetSource: Codable, Equatable, Sendable {
    let name: String
    let version: String
    let sourceURL: String?
    let country: String
    let lastUpdated: String
}

struct RestaurantNutritionDataset: Codable, Equatable, Sendable {
    let datasetVersion: String
    let source: RestaurantDatasetSource
    let restaurants: [Restaurant]
    let menuItems: [RestaurantMenuItem]
}

struct RestaurantFoodQuery: Equatable, Sendable {
    let rawText: String
    let restaurantID: String?
    let itemTerms: [String]
    let quantity: Int?
    let modifierTerms: [String]
}

enum RestaurantClarificationReason: String, Codable, Equatable, Sendable {
    case itemIdentity
    case mealCompleteness
    case size
    case variant
    case modifier
    case quantity
    case component
    case substitution
}

struct RestaurantClarificationChoice: Codable, Equatable, Sendable, Identifiable {
    let id: String
    let title: String
    let value: String
}

struct RestaurantClarificationGroup: Codable, Equatable, Sendable, Identifiable {
    let id: String
    let reason: RestaurantClarificationReason
    let title: String
    let choices: [RestaurantClarificationChoice]
    let allowsMultiple: Bool
    let optional: Bool
}

struct RestaurantClarificationPlan: Codable, Equatable, Sendable {
    let groups: [RestaurantClarificationGroup]

    var isEmpty: Bool { groups.isEmpty }
}

struct RestaurantMatchedComponent: Equatable, Sendable {
    let menuItem: RestaurantMenuItem
    let quantity: Int

    var nutrition: NutritionFacts? { menuItem.nutrition?.scaled(by: Double(quantity)) }
}

struct RestaurantMatch: Equatable, Sendable {
    let restaurant: Restaurant
    let menuItem: RestaurantMenuItem
    let quantity: Int
    let selectedVariant: RestaurantMenuItemVariant?
    let matchedModifiers: [RestaurantModifier]
    let additionalComponents: [RestaurantMatchedComponent]
    let clarificationPlan: RestaurantClarificationPlan
    let assumptions: [NutritionAssumption]

    var nutrition: NutritionFacts? {
        var values = [selectedVariant?.nutrition ?? menuItem.nutrition].compactMap { $0 }.map { $0.scaled(by: Double(quantity)) }
        values.append(contentsOf: additionalComponents.compactMap(\.nutrition))
        values.append(contentsOf: matchedModifiers.compactMap { $0.nutritionDelta })
        return NutritionFacts.adding(values)
    }
}
