import Foundation

protocol RestaurantNutritionProvider {
    func match(_ query: RestaurantFoodQuery) async -> RestaurantMatch?
}

struct RestaurantDatasetStore: Sendable {
    private final class ResourceBundleToken {}

    let dataset: RestaurantNutritionDataset

    init(dataset: RestaurantNutritionDataset) {
        self.dataset = dataset
    }

    static func bundled(in bundle: Bundle? = nil) -> RestaurantDatasetStore? {
        let bundles = bundle.map { [$0] } ?? [Bundle.main, Bundle(for: ResourceBundleToken.self)]
        guard let url = bundles.compactMap({
            $0.url(forResource: "restaurant-nutrition-v1", withExtension: "json")
        }).first,
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

    func uniqueRestaurantForItem(in text: String, dataset: RestaurantNutritionDataset) -> Restaurant? {
        let matchingRestaurantIDs = Set(dataset.menuItems.compactMap { item -> String? in
            guard self.item(in: text, items: [item]) != nil else { return nil }
            return item.provenance?.restaurantID
        })
        guard matchingRestaurantIDs.count == 1, let restaurantID = matchingRestaurantIDs.first else { return nil }
        return dataset.restaurants.first { $0.id == restaurantID }
    }
}

struct LocalRestaurantNutritionProvider: RestaurantNutritionProvider, Sendable {
    let store: RestaurantDatasetStore
    private let matcher = RestaurantAliasMatcher()

    init(store: RestaurantDatasetStore) {
        self.store = store
    }

    func match(_ query: RestaurantFoodQuery) async -> RestaurantMatch? {
        let normalized = RestaurantQueryNormalizer.normalize(query.rawText)
        let clarificationText = query.rawText
            .components(separatedBy: "Clarification:")
            .dropFirst()
            .joined(separator: " ")
        let restaurant = query.restaurantID.flatMap { id in
            store.dataset.restaurants.first { $0.id == id }
        } ?? matcher.restaurant(in: query.rawText, dataset: store.dataset)
            ?? matcher.uniqueRestaurantForItem(in: query.rawText, dataset: store.dataset)

        guard let restaurant else { return nil }
        let restaurantItems = store.dataset.menuItems.filter { item in
            item.provenance?.restaurantID == nil || item.provenance?.restaurantID == restaurant.id
        }
        let item: RestaurantMenuItem?
        if restaurant.id == "kfc_au", normalized.contains("zinger box") {
            item = restaurantItems.first { $0.id == "kfc-au-zinger-box-regular" }
        } else {
            item = (!clarificationText.isEmpty ? matcher.item(in: clarificationText, items: restaurantItems) : nil)
                ?? matcher.item(in: query.rawText, items: restaurantItems)
        }
        guard let item else { return nil }

        let selectedVariant = item.variants.first { variant in
            variant.aliases.map(RestaurantQueryNormalizer.normalize).contains { normalized.contains($0) }
        }

        let modifiers = item.modifiers.filter { modifier in
            modifier.aliases.contains { alias in
                let normalizedAlias = RestaurantQueryNormalizer.normalize(alias)
                return normalized.contains(normalizedAlias) || query.modifierTerms.contains { term in
                    RestaurantQueryNormalizer.normalize(term) == normalizedAlias
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
           !normalized.contains("burger only"),
           !normalized.contains("standalone"),
           !normalized.contains("best estimate"),
           additionalComponents.isEmpty {
            plan = RestaurantClarificationPlan(groups: item.mealConfigurations.first?.clarificationGroups ?? [])
        } else if item.id == "kfc-au-zinger-box-regular" {
            let groups = item.mealConfigurations.first?.clarificationGroups ?? []
            let resolvedGroups = groups.filter { group in
                if normalized.contains("best estimate") { return false }
                switch group.id {
                case "chicken": return !normalized.contains("wicked") && !normalized.contains("recipe") && !normalized.contains("fillet") && !normalized.contains("tender")
                case "first-side": return !normalized.contains("first side")
                case "second-side": return !normalized.contains("second side")
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

        let resolvedComponents = resolvedComponentSelections(
            in: query.rawText,
            groups: item.mealConfigurations.first?.clarificationGroups ?? []
        )

        return RestaurantMatch(
            restaurant: restaurant,
            menuItem: item,
            quantity: max(query.quantity ?? 1, 1),
            selectedVariant: selectedVariant,
            matchedModifiers: modifiers,
            additionalComponents: additionalComponents,
            resolvedComponents: resolvedComponents,
            clarificationPlan: plan,
            assumptions: []
        )
    }

    private func resolvedComponentSelections(
        in text: String,
        groups: [RestaurantClarificationGroup]
    ) -> [RestaurantResolvedComponent] {
        let answerSegments = text
            .components(separatedBy: "Clarification:")
            .dropFirst()
            .joined(separator: " ")
            .split(separator: ";")
            .map(String.init)

        return groups.compactMap { group in
            guard let segment = answerSegments.first(where: {
                RestaurantQueryNormalizer.normalize($0).hasPrefix(RestaurantQueryNormalizer.normalize(group.title))
            }),
            let choice = group.choices.first(where: {
                RestaurantQueryNormalizer.normalize(segment).contains(RestaurantQueryNormalizer.normalize($0.title))
            }) else { return nil }
            return RestaurantResolvedComponent(
                groupID: group.id,
                name: choice.title,
                quantity: RestaurantQueryNormalizer.quantity(in: choice.title) ?? 1,
                sourceItemID: choice.value == "best_estimate" ? nil : choice.value
            )
        }
    }
}

enum RestaurantNutritionAnalysisService {
    static func match(description: String) async -> RestaurantMatch? {
        await match(description: description, store: RestaurantDatasetStore.bundled())
    }

    static func match(description: String, store: RestaurantDatasetStore?) async -> RestaurantMatch? {
        guard let store else { return nil }
        let parentDescription = description.components(separatedBy: "Clarification:").first ?? description
        let provider = LocalRestaurantNutritionProvider(store: store)
        return await provider.match(RestaurantFoodQuery(
            rawText: description,
            restaurantID: nil,
            itemTerms: [],
            quantity: RestaurantQueryNormalizer.quantity(in: parentDescription),
            modifierTerms: []
        ))
    }
}

extension RestaurantMatch {
    var foodAnalysis: GeminiService.FoodAnalysis? {
        guard let nutrition else { return nil }
        let facts = nutrition.otherNutrients
        let restaurantName = restaurant.name.replacingOccurrences(of: " Australia", with: "")
        let displayName = selectedVariant.map { "\(restaurantName) \(menuItem.name) - \($0.name)" }
            ?? "\(restaurantName) \(menuItem.name)"
        let hasKnownServingWeight = menuItem.servingWeightGrams.map { $0 > 0 } ?? false
        let servingReference = hasKnownServingWeight
            ? (menuItem.servingWeightGrams ?? 0) * Double(quantity)
            : Double(quantity)
        let provenance = selectedVariant?.provenance ?? menuItem.provenance
        let hasUnquantifiedModifier = matchedModifiers.contains { $0.nutritionDelta == nil }
        let detailSuffix = hasUnquantifiedModifier ? " · selected modifier not included in published totals" : ""
        return GeminiService.FoodAnalysis(
            name: displayName,
            calories: Int((nutrition.calories ?? ((nutrition.kilojoules ?? 0) / 4.184)).rounded()),
            protein: nutrition.proteinGrams ?? 0,
            carbs: nutrition.carbohydrateGrams ?? 0,
            fat: nutrition.fatGrams ?? 0,
            servingSizeGrams: servingReference,
            emoji: restaurant.id == "boost_au" ? "🥤" : "🍔",
            sugar: facts["sugarsGrams"],
            fiber: facts["fibreGrams"],
            sodium: facts["sodiumMilligrams"],
            servingUnitOptions: hasKnownServingWeight ? [] : [
                .loggedServing(quantity: Double(quantity), unit: menuItem.servingUnit ?? "serving")
            ],
            selectedServingUnit: menuItem.servingUnit,
            selectedServingQuantity: Double(quantity),
            servingSizeIsKnown: hasKnownServingWeight,
            resolvedComponents: resolvedComponents,
            nutritionSource: "Verified restaurant nutrition",
            nutritionSourceDetail: provenance.map { source in
                [restaurant.name, source.datasetVersion].compactMap { $0 }.joined(separator: " · ")
            }.map { $0 + detailSuffix } ?? restaurant.name + detailSuffix,
            nutritionConfidence: hasUnquantifiedModifier ? "Medium" : "High",
            proteinIsKnown: nutrition.proteinGrams != nil,
            carbsAreKnown: nutrition.carbohydrateGrams != nil,
            fatIsKnown: nutrition.fatGrams != nil
        )
    }
}
