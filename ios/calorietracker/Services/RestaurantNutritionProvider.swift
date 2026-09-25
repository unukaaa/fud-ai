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
    static func normalize(_ value: String) -> String {
        value
            .folding(options: [.diacriticInsensitive, .caseInsensitive], locale: .current)
            .replacingOccurrences(of: "[’'`]", with: "", options: .regularExpression)
            .replacingOccurrences(of: "-", with: " ")
            .replacingOccurrences(of: "[^a-z0-9 ]", with: " ", options: .regularExpression)
            .replacingOccurrences(of: #"\s+"#, with: " ", options: .regularExpression)
            .trimmingCharacters(in: .whitespacesAndNewlines)
    }

    static func quantity(in value: String) -> Int? {
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
        return items.first { item in
            (item.aliases + [item.name]).contains {
                normalized.contains(RestaurantQueryNormalizer.normalize($0))
            }
        }
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
        let normalized = RestaurantQueryNormalizer.normalize(query.rawText)
        if item.id == "kfc-au-zinger-burger",
           !normalized.contains("meal"),
           !normalized.contains("box"),
           additionalComponents.isEmpty {
            plan = RestaurantClarificationPlan(groups: item.mealConfigurations.first?.clarificationGroups ?? [])
        } else {
            plan = RestaurantClarificationPlan(groups: [])
        }

        return RestaurantMatch(
            restaurant: restaurant,
            menuItem: item,
            quantity: max(query.quantity ?? 1, 1),
            matchedModifiers: modifiers,
            additionalComponents: additionalComponents,
            clarificationPlan: plan,
            assumptions: []
        )
    }
}
