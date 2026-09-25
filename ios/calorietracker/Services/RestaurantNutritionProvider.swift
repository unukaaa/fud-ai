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
        let explicitlyRequestsMeal = normalized.contains(" meal") || normalized.hasSuffix("meal") || normalized.contains(" combo") || normalized.hasSuffix("combo")
        return items
            .compactMap { item -> (RestaurantMenuItem, Int)? in
                let bestAliasScore = (item.aliases + [item.name])
                    .map(RestaurantQueryNormalizer.normalize)
                    .compactMap { alias -> Int? in
                        guard let range = normalized.range(of: alias) else { return nil }
                        let position = normalized.distance(from: normalized.startIndex, to: range.lowerBound)
                        let endsPrimaryPhrase = range.upperBound == normalized.endIndex ? 1_000 : 0
                        return max(0, 10_000 - (position * 100)) + endsPrimaryPhrase + alias.count
                    }
                    .max()
                return bestAliasScore.map { score in
                    let mealPriority = explicitlyRequestsMeal && item.category == "meal" ? 100_000 : 0
                    return (item, score + mealPriority)
                }
            }
            .max { $0.1 < $1.1 }?.0
    }

    func uniqueRestaurantForItem(in text: String, dataset: RestaurantNutritionDataset) -> Restaurant? {
        let normalized = RestaurantQueryNormalizer.normalize(text)
        let matches = dataset.menuItems.compactMap { item -> (String, Int)? in
            guard let restaurantID = item.provenance?.restaurantID,
                  let length = (item.aliases + [item.name])
                    .map(RestaurantQueryNormalizer.normalize)
                    .filter({ normalized.contains($0) })
                    .map(\.count)
                    .max()
            else { return nil }
            return (restaurantID, length)
        }
        guard let longest = matches.map(\.1).max() else { return nil }
        let matchingRestaurantIDs = Set(matches.filter { $0.1 == longest }.map(\.0))
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
        let parentText = query.rawText.components(separatedBy: "Clarification:").first ?? query.rawText
        let normalizedParent = RestaurantQueryNormalizer.normalize(parentText)
        let primaryClause = normalizedParent
            .components(separatedBy: " with ").first?
            .components(separatedBy: " and ").first
            ?? parentText
        let restaurant = query.restaurantID.flatMap { id in
            store.dataset.restaurants.first { $0.id == id }
        } ?? matcher.restaurant(in: query.rawText, dataset: store.dataset)
            ?? matcher.uniqueRestaurantForItem(in: query.rawText, dataset: store.dataset)

        guard let restaurant else { return nil }
        let restaurantItems = store.dataset.menuItems.filter { item in
            item.provenance?.restaurantID == nil || item.provenance?.restaurantID == restaurant.id
        }
        guard let initiallyMatchedItem = matcher.item(in: primaryClause, items: restaurantItems) else { return nil }
        let initialGroups = initiallyMatchedItem.mealConfigurations.first?.clarificationGroups ?? []
        let initialSelections = resolvedComponentSelections(in: query.rawText, groups: initialGroups)
        let selectedItemID = initialSelections
            .first { selection in initialGroups.first(where: { $0.id == selection.groupID })?.reason == .mealCompleteness }?
            .sourceItemID
        let item = selectedItemID.flatMap { targetID in restaurantItems.first { $0.id == targetID } }
            ?? initiallyMatchedItem

        let selectedVariant = selectedVariant(in: query.rawText, for: item)

        let quantitySelectsVariant = query.quantity.map { quantity in
            guard let selectedVariant else { return false }
            return (selectedVariant.aliases + [selectedVariant.name]).contains {
                RestaurantQueryNormalizer.quantity(in: $0) == quantity
            }
        } ?? false
        let parentQuantity = quantitySelectsVariant ? 1 : max(query.quantity ?? 1, 1)

        let modifiers = item.modifiers.filter { modifier in
            modifier.aliases.contains { alias in
                let normalizedAlias = RestaurantQueryNormalizer.normalize(alias)
                return normalized.contains(normalizedAlias) || query.modifierTerms.contains { term in
                    RestaurantQueryNormalizer.normalize(term) == normalizedAlias
                }
            }
        }

        let additionalComponents = explicitAdditionalComponents(
            in: parentText,
            primaryItem: item,
            candidates: restaurantItems
        )
        let quantityBelongsToAdditionalComponent = additionalComponents.contains { $0.quantity == query.quantity }
        let effectiveParentQuantity = quantityBelongsToAdditionalComponent ? 1 : parentQuantity

        let itemGroups = item.mealConfigurations.first?.clarificationGroups ?? []
        let clarifiedComponents = resolvedComponentSelections(in: query.rawText, groups: itemGroups)
        let resolvedGroupIDs = answeredGroupIDs(in: query.rawText, groups: itemGroups)
        let unresolvedGroups = normalized.contains("best estimate")
            ? []
            : itemGroups.filter { !resolvedGroupIDs.contains($0.id) }

        let plan: RestaurantClarificationPlan
        if !unresolvedGroups.isEmpty && additionalComponents.isEmpty {
            plan = RestaurantClarificationPlan(groups: unresolvedGroups)
        } else if !item.variants.isEmpty && selectedVariant == nil {
            let choices = item.variants.map { RestaurantClarificationChoice(id: $0.id, title: $0.name, value: $0.id) } + [RestaurantClarificationChoice(id: "best_estimate", title: "Use best estimate", value: "best_estimate")]
            let quantityVariants = item.variants.allSatisfy { $0.servingQuantity != nil && $0.servingUnit != nil }
            plan = RestaurantClarificationPlan(groups: [RestaurantClarificationGroup(
                id: quantityVariants ? "quantity" : "size",
                reason: quantityVariants ? .quantity : .size,
                title: quantityVariants ? "Quantity" : "Size",
                choices: choices,
                allowsMultiple: false,
                optional: false
            )])
        } else {
            plan = RestaurantClarificationPlan(groups: [])
        }

        let variantComponents = (selectedVariant?.componentIDs ?? []).compactMap { componentID in
            if let component = store.dataset.menuItems.first(where: { $0.id == componentID }) {
                return RestaurantResolvedComponent(groupID: componentID, name: component.name, quantity: 1, sourceItemID: componentID)
            }
            for component in store.dataset.menuItems {
                if let variant = component.variants.first(where: { $0.id == componentID }) {
                    return RestaurantResolvedComponent(groupID: componentID, name: "\(variant.name) \(component.name)", quantity: 1, sourceItemID: componentID)
                }
            }
            return nil
        }

        return RestaurantMatch(
            restaurant: restaurant,
            menuItem: item,
            quantity: effectiveParentQuantity,
            selectedVariant: selectedVariant,
            matchedModifiers: modifiers,
            additionalComponents: additionalComponents,
            resolvedComponents: clarifiedComponents + variantComponents,
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

        let explicitlyLabelled = groups.compactMap { group -> RestaurantResolvedComponent? in
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
        let labelledGroupIDs = Set(explicitlyLabelled.map(\.groupID))
        let normalizedText = RestaurantQueryNormalizer.normalize(text)
        let unlabelledCandidates = groups.compactMap { group -> (RestaurantClarificationGroup, RestaurantClarificationChoice)? in
            guard !labelledGroupIDs.contains(group.id),
                  let choice = group.choices.first(where: { choice in
                      let terms = group.reason == .mealCompleteness
                          ? [RestaurantQueryNormalizer.normalize(choice.title)]
                          : choiceTerms(for: choice)
                      return choice.value != "best_estimate" && terms.contains { term in
                          normalizedText.contains(term)
                      }
                  })
            else { return nil }
            return (group, choice)
        }
        let unlabelled = unlabelledCandidates.compactMap { group, choice -> RestaurantResolvedComponent? in
            guard unlabelledCandidates.filter({ $0.1.value == choice.value }).count == 1 else { return nil }
            return RestaurantResolvedComponent(
                groupID: group.id,
                name: choice.title,
                quantity: RestaurantQueryNormalizer.quantity(in: choice.title) ?? 1,
                sourceItemID: choice.value
            )
        }
        return explicitlyLabelled + unlabelled
    }

    private func selectedVariant(
        in text: String,
        for item: RestaurantMenuItem
    ) -> RestaurantMenuItemVariant? {
        guard !item.variants.isEmpty else { return nil }
        let clarificationSegments = text
            .components(separatedBy: "Clarification:")
            .dropFirst()
            .joined(separator: " ")
            .split(separator: ";")
            .map { RestaurantQueryNormalizer.normalize(String($0)) }
        let explicitVariant = clarificationSegments.compactMap { segment in
            item.variants
                .compactMap { variant -> (RestaurantMenuItemVariant, Int)? in
                    let matchLength = (variant.aliases + [variant.name])
                        .map(RestaurantQueryNormalizer.normalize)
                        .filter(segment.contains)
                        .map(\.count)
                        .max()
                    return matchLength.map { (variant, $0) }
                }
                .max { $0.1 < $1.1 }?.0
        }.first
        if let explicitVariant { return explicitVariant }

        let normalizedParent = RestaurantQueryNormalizer.normalize(
            text.components(separatedBy: "Clarification:").first ?? text
        )
        return item.variants
            .compactMap { variant -> (RestaurantMenuItemVariant, Int)? in
                let matchLength = (variant.aliases + [variant.name])
                    .map(RestaurantQueryNormalizer.normalize)
                    .filter(normalizedParent.contains)
                    .map(\.count)
                    .max()
                return matchLength.map { (variant, $0) }
            }
            .max { $0.1 < $1.1 }?.0
    }

    private func choiceTerms(for choice: RestaurantClarificationChoice) -> [String] {
        var terms = [choice.title]
        if let item = store.dataset.menuItems.first(where: { $0.id == choice.value }) {
            terms.append(contentsOf: item.aliases)
            terms.append(item.name)
        }
        let normalizedTerms = terms.map(RestaurantQueryNormalizer.normalize)
        return normalizedTerms + normalizedTerms.compactMap { term in
            term.hasPrefix("regular ") ? String(term.dropFirst("regular ".count)) : nil
        }
    }

    private func answeredGroupIDs(
        in text: String,
        groups: [RestaurantClarificationGroup]
    ) -> Set<String> {
        let answerSegments = text
            .components(separatedBy: "Clarification:")
            .dropFirst()
            .joined(separator: " ")
            .split(separator: ";")
            .map { RestaurantQueryNormalizer.normalize(String($0)) }
        var answered = Set(groups.compactMap { group in
            answerSegments.contains { $0.hasPrefix(RestaurantQueryNormalizer.normalize(group.title)) }
                ? group.id
                : nil
        })

        let normalizedText = RestaurantQueryNormalizer.normalize(text)
        let textTokens = Set(normalizedText.split(separator: " ").map(String.init))
        let candidates = groups.flatMap { group in
            group.choices.compactMap { choice -> (String, String)? in
                let terms = group.reason == .mealCompleteness
                    ? [RestaurantQueryNormalizer.normalize(choice.title)]
                    : choiceTerms(for: choice)
                let matchesTerm = terms.contains { term in
                    let tokens = term.split(separator: " ").map(String.init).filter { $0 != "regular" }
                    return normalizedText.contains(term) || (!tokens.isEmpty && tokens.allSatisfy(textTokens.contains))
                }
                guard choice.value != "best_estimate",
                      matchesTerm
                else { return nil }
                return (group.id, choice.value)
            }
        }
        for candidate in candidates where candidates.filter({ $0.1 == candidate.1 }).count == 1 {
            answered.insert(candidate.0)
        }
        return answered
    }

    private func explicitAdditionalComponents(
        in text: String,
        primaryItem: RestaurantMenuItem,
        candidates: [RestaurantMenuItem]
    ) -> [RestaurantMatchedComponent] {
        let normalized = RestaurantQueryNormalizer.normalize(text)
        guard primaryItem.category != "meal",
              normalized.contains(" and ") || normalized.contains(" with ")
        else { return [] }

        return candidates.compactMap { candidate in
            guard candidate.id != primaryItem.id,
                  let alias = (candidate.aliases + [candidate.name])
                    .map(RestaurantQueryNormalizer.normalize)
                    .filter({ normalized.contains($0) })
                    .max(by: { $0.count < $1.count })
            else { return nil }
            let prefix = normalized.components(separatedBy: alias).first ?? ""
            let quantity = prefix.split(separator: " ").last.flatMap { Int($0) } ?? 1
            return RestaurantMatchedComponent(menuItem: candidate, quantity: max(quantity, 1))
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
        let servingWeightGrams = selectedVariant?.servingWeightGrams ?? menuItem.servingWeightGrams
        let servingQuantity = selectedVariant?.servingQuantity ?? Double(quantity)
        let servingUnit = selectedVariant?.servingUnit ?? menuItem.servingUnit
        let hasKnownServingWeight = servingWeightGrams.map { $0 > 0 } ?? false
        let servingReference = hasKnownServingWeight
            ? (servingWeightGrams ?? 0) * Double(quantity)
            : servingQuantity
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
                .loggedServing(quantity: servingQuantity, unit: servingUnit ?? "serving")
            ],
            selectedServingUnit: servingUnit,
            selectedServingQuantity: servingQuantity,
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
