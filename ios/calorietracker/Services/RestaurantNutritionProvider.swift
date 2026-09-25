import Foundation

protocol RestaurantNutritionProvider {
    func match(_ query: RestaurantFoodQuery) async -> RestaurantMatch?
}

struct RestaurantDatasetStore: Sendable {
    let dataset: RestaurantNutritionDataset

    init(dataset: RestaurantNutritionDataset) {
        self.dataset = dataset
    }

    static func bundled() -> RestaurantDatasetStore? {
        guard let url = Bundle.main.url(forResource: "restaurant-nutrition-v1", withExtension: "json"),
              let data = try? Data(contentsOf: url),
              let dataset = try? JSONDecoder().decode(RestaurantNutritionDataset.self, from: data)
        else { return nil }
        return RestaurantDatasetStore(dataset: dataset)
    }
}

enum RestaurantQueryNormalizer {
    nonisolated static func normalize(_ value: String) -> String {
        value
            .folding(options: [.diacriticInsensitive, .caseInsensitive], locale: .current)
            .replacingOccurrences(of: "[’'`]", with: "", options: .regularExpression)
            .replacingOccurrences(of: "-", with: " ")
            .replacingOccurrences(of: "[^a-z0-9 ]", with: " ", options: .regularExpression)
            .replacingOccurrences(of: #"\s+"#, with: " ", options: .regularExpression)
            .trimmingCharacters(in: .whitespacesAndNewlines)
    }

    nonisolated static func quantity(in value: String) -> Int? {
        let pattern = #"\b(\d+)\b"#
        guard let match = value.range(of: pattern, options: .regularExpression) else { return nil }
        return Int(value[match].trimmingCharacters(in: .whitespacesAndNewlines))
    }
}

struct RestaurantAliasMatcher: Sendable {
    func restaurant(in text: String, dataset: RestaurantNutritionDataset) -> Restaurant? {
        let normalized = RestaurantQueryNormalizer.normalize(text)
        return dataset.restaurants.first { restaurant in
            (restaurant.aliases + [restaurant.name]).contains {
                normalized.contains(RestaurantQueryNormalizer.normalize($0))
            }
        }
    }

    func item(in text: String, items: [RestaurantMenuItem]) -> RestaurantMenuItem? {
        let normalized = RestaurantQueryNormalizer.normalize(text)
        return items
            .compactMap { item -> (RestaurantMenuItem, Int)? in
                let bestAliasLength = (item.aliases + [item.name])
                    .map(RestaurantQueryNormalizer.normalize)
                    .filter { normalized.contains($0) }
                    .map(\.count)
                    .max()
                return bestAliasLength.map { (item, $0) }
            }
            .max { $0.1 < $1.1 }?.0
    }
}

struct LocalRestaurantNutritionProvider: RestaurantNutritionProvider, Sendable {
    let store: RestaurantDatasetStore
    private let matcher = RestaurantAliasMatcher()

    init(store: RestaurantDatasetStore) {
        self.store = store
    }

    func match(_ query: RestaurantFoodQuery) async -> RestaurantMatch? {
        let restaurant = query.restaurantID.flatMap { id in
            store.dataset.restaurants.first { $0.id == id }
        } ?? matcher.restaurant(in: query.rawText, dataset: store.dataset)

        guard let restaurant else { return nil }
        let restaurantItems = store.dataset.menuItems.filter { item in
            item.provenance?.restaurantID == nil || item.provenance?.restaurantID == restaurant.id
        }
        guard let item = matcher.item(in: query.rawText, items: restaurantItems) else { return nil }

        let normalized = RestaurantQueryNormalizer.normalize(query.rawText)
        let selectedVariant = item.variants.first { variant in
            variant.aliases.map(RestaurantQueryNormalizer.normalize).contains { normalized.contains($0) }
        }

        let modifiers = item.modifiers.filter { modifier in
            query.modifierTerms.contains { term in
                modifier.aliases.contains { alias in
                    RestaurantQueryNormalizer.normalize(term) == RestaurantQueryNormalizer.normalize(alias)
                }
            }
        }

        let additionalComponents: [RestaurantMatchedComponent]
        if item.id == "kfc-au-zinger-burger",
           let wings = store.dataset.menuItems.first(where: { $0.id == "kfc-au-wicked-wing" }),
           RestaurantQueryNormalizer.normalize(query.rawText).contains("wicked wing") {
            additionalComponents = [RestaurantMatchedComponent(menuItem: wings, quantity: max(RestaurantQueryNormalizer.quantity(in: query.rawText) ?? 1, 1))]
        } else {
            additionalComponents = []
        }

        let plan: RestaurantClarificationPlan
        if item.id == "kfc-au-zinger-burger",
           !normalized.contains("meal"),
           !normalized.contains("box"),
           additionalComponents.isEmpty {
            plan = RestaurantClarificationPlan(groups: item.mealConfigurations.first?.clarificationGroups ?? [])
        } else if item.id == "kfc-au-zinger-box-regular" {
            let groups = item.mealConfigurations.first?.clarificationGroups ?? []
            let resolvedGroups = groups.filter { group in
                switch group.id {
                case "chicken": return !normalized.contains("wicked") && !normalized.contains("recipe") && !normalized.contains("fillet") && !normalized.contains("tender")
                case "drink": return !normalized.contains("pepsi") && !normalized.contains("7up") && !normalized.contains("mountain dew") && !normalized.contains("solo") && !normalized.contains("sunkist") && !normalized.contains("water") && !normalized.contains("juice")
                default: return true
                }
            }
            plan = RestaurantClarificationPlan(groups: resolvedGroups)
        } else if !item.variants.isEmpty && selectedVariant == nil {
            let choices = item.variants.map { RestaurantClarificationChoice(id: $0.id, title: $0.name, value: $0.id) } + [RestaurantClarificationChoice(id: "best_estimate", title: "Use best estimate", value: "best_estimate")]
            plan = RestaurantClarificationPlan(groups: [RestaurantClarificationGroup(id: "size", reason: .size, title: "Size", choices: choices, allowsMultiple: false, optional: false)])
        } else {
            plan = RestaurantClarificationPlan(groups: [])
        }

        return RestaurantMatch(
            restaurant: restaurant,
            menuItem: item,
            quantity: max(query.quantity ?? 1, 1),
            selectedVariant: selectedVariant,
            matchedModifiers: modifiers,
            additionalComponents: additionalComponents,
            clarificationPlan: plan,
            assumptions: []
        )
    }
}
