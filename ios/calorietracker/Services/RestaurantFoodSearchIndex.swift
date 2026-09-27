import Foundation

/// Search identities only. Nutrition and provenance remain owned by the
/// restaurant dataset and its resolver.
struct SearchFoodSuggestion: Equatable, Identifiable, Sendable {
    enum Kind: Equatable, Sendable { case brand, product }
    enum MatchReason: Int, Equatable, Sendable {
        case exact = 0
        case prefix = 1
        case tokenPrefix = 2
        case alias = 3
        case brandOnly = 4
    }

    let id: String
    let kind: Kind
    let title: String
    let subtitle: String
    let restaurantID: String
    let itemID: String?
    let variantID: String?
    let matchReason: MatchReason

    var restaurantSelection: RestaurantFoodSelection? {
        guard kind == .product, let itemID else { return nil }
        return RestaurantFoodSelection(restaurantID: restaurantID, itemID: itemID, variantID: variantID)
    }
}

struct RestaurantFoodSearchIndex: Sendable {
    private struct Product: Sendable {
        let title: String
        let restaurantID: String
        let restaurantName: String
        let itemID: String
        let variantID: String?
        let primaryNames: [String]
        let aliases: [String]
        let order: Int
    }

    private struct Brand: Sendable {
        let id: String
        let name: String
        let aliases: [String]
        let hasVerifiedItems: Bool
    }

    private let brands: [Brand]
    private let products: [Product]

    init(store: RestaurantDatasetStore) {
        let dataset = store.dataset
        brands = dataset.restaurants.map { restaurant in
            Brand(
                id: restaurant.id,
                name: restaurant.name,
                aliases: (restaurant.aliases + [restaurant.name]).map(Self.normalize),
                hasVerifiedItems: dataset.menuItems.contains { item in
                    item.provenance?.restaurantID == restaurant.id
                        && item.provenance?.sourceType == .verifiedRestaurant
                        && (item.nutrition != nil || item.variants.contains { $0.nutrition != nil })
                }
            )
        }

        let namesByID = Dictionary(uniqueKeysWithValues: dataset.restaurants.map { ($0.id, $0.name) })
        var indexed: [Product] = []
        for item in dataset.menuItems {
            guard let restaurantID = item.provenance?.restaurantID,
                  let restaurantName = namesByID[restaurantID] else { continue }
            let itemNames = [item.name].map(Self.normalize)
            let itemAliases = item.aliases.map(Self.normalize)
            let itemOrder = indexed.count
            indexed.append(Product(
                title: item.name, restaurantID: restaurantID, restaurantName: restaurantName,
                itemID: item.id, variantID: nil, primaryNames: itemNames,
                aliases: itemAliases, order: itemOrder
            ))
            for variant in item.variants {
                let qualifiedNames = ["\(item.name) \(variant.name)", "\(variant.name) \(item.name)"]
                // Single-word size aliases have no product identity on their own.
                let qualifiedAliases = variant.aliases.filter {
                    let words = Self.normalize($0).split(separator: " ")
                    return words.count > 1 || (words.count == 1 && words[0].contains(where: \.isNumber))
                }
                let variantOrder = indexed.count
                indexed.append(Product(
                    title: "\(item.name) — \(variant.name)",
                    restaurantID: restaurantID, restaurantName: restaurantName,
                    itemID: item.id, variantID: variant.id,
                    primaryNames: qualifiedNames.map(Self.normalize),
                    aliases: qualifiedAliases.map(Self.normalize),
                    order: variantOrder
                ))
            }
        }
        products = indexed
    }

    static func bundled() -> RestaurantFoodSearchIndex? {
        RestaurantDatasetStore.bundled().map(RestaurantFoodSearchIndex.init(store:))
    }

    func search(_ text: String, limit: Int = 5) -> [SearchFoodSuggestion] {
        let query = Self.normalize(text)
        guard !query.isEmpty, limit > 0 else { return [] }

        if let brand = brands.first(where: { $0.aliases.contains(query) }) {
            let brandSuggestion = SearchFoodSuggestion(
                id: "brand:\(brand.id)", kind: .brand, title: brand.name,
                subtitle: brand.hasVerifiedItems ? "Verified items available" : "Items available",
                restaurantID: brand.id, itemID: nil, variantID: nil, matchReason: .brandOnly
            )
            let available = products.filter { $0.restaurantID == brand.id && $0.variantID == nil }
                .prefix(limit).map { suggestion(for: $0, reason: .brandOnly) }
            return [brandSuggestion] + available
        }

        return products.compactMap { product -> (Product, SearchFoodSuggestion.MatchReason)? in
            guard let reason = Self.match(query, in: product) else { return nil }
            return (product, reason)
        }
        .sorted { left, right in
            if left.1.rawValue != right.1.rawValue { return left.1.rawValue < right.1.rawValue }
            return left.0.order < right.0.order
        }
        .prefix(limit)
        .map { suggestion(for: $0.0, reason: $0.1) }
    }

    private func suggestion(for product: Product, reason: SearchFoodSuggestion.MatchReason) -> SearchFoodSuggestion {
        SearchFoodSuggestion(
            id: product.variantID.map { "variant:\($0)" } ?? "item:\(product.itemID)",
            kind: .product, title: product.title, subtitle: product.restaurantName,
            restaurantID: product.restaurantID, itemID: product.itemID,
            variantID: product.variantID, matchReason: reason
        )
    }

    private static func match(_ query: String, in product: Product) -> SearchFoodSuggestion.MatchReason? {
        if product.primaryNames.contains(query) || product.aliases.contains(query) { return .exact }
        if product.primaryNames.contains(where: { $0.hasPrefix(query) }) { return .prefix }
        let queryWords = query.split(separator: " ").map(String.init)
        if product.primaryNames.contains(where: { name in
            let words = name.split(separator: " ").map(String.init)
            guard queryWords.count <= words.count else { return false }
            return zip(queryWords, words).allSatisfy { pair in pair.1.hasPrefix(pair.0) }
        }) { return .tokenPrefix }
        if product.aliases.contains(where: { $0.hasPrefix(query) }) { return .alias }
        return nil
    }

    nonisolated private static func normalize(_ value: String) -> String {
        RestaurantQueryNormalizer.normalize(value).lowercased()
    }
}
