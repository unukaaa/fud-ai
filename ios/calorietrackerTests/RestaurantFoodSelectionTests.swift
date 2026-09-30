import Testing
@testable import calorietracker

struct RestaurantFoodSelectionTests {
    private func product(_ query: String, itemID: String, variantID: String? = nil) throws -> SearchFoodSuggestion {
        let index = try #require(RestaurantFoodSearchIndex.bundled())
        return try #require(index.search(query).first {
            $0.itemID == itemID && $0.variantID == variantID
        })
    }

    @Test func exactProductSelectionUsesAuthoritativeResolver() async throws {
        let bigMac = try product("big ma", itemID: "mcd-au-big-mac")
        let selection = try #require(bigMac.restaurantSelection)
        let result = await FoodQueryResolutionService.resolve(selection: selection)
        #expect(result.restaurantSelection == selection)
        #expect(result.restaurantMatch?.menuItem.id == selection.itemID)
        #expect(result.analysis?.calories == 557)
        #expect(result.analysis?.nutritionSource == "Verified restaurant nutrition")
        #expect(result.restaurantMatch?.quantity == 1)

        let zinger = try product("zinger bur", itemID: "kfc-au-zinger-burger")
        let zingerResult = await FoodQueryResolutionService.resolve(selection: try #require(zinger.restaurantSelection))
        #expect(zingerResult.restaurantMatch?.menuItem.id == "kfc-au-zinger-burger")
        #expect(zingerResult.analysis?.calories == 448)
    }

    @Test func variantSelectionPreservesParentAndVariantIdentity() async throws {
        let medium = try product("wonderm", itemID: "boost-au-wondermelon", variantID: "boost-au-wondermelon-medium")
        let selection = try #require(medium.restaurantSelection)
        let result = await FoodQueryResolutionService.resolve(selection: selection)
        #expect(result.restaurantMatch?.menuItem.id == selection.itemID)
        #expect(result.restaurantMatch?.selectedVariant?.id == selection.variantID)
        #expect(result.analysis?.calories == 156)
        #expect(result.restaurantMatch?.nutrition?.proteinGrams == 10.2)
        #expect(result.analysis?.nutritionSource == "Verified restaurant nutrition")

        let nuggets = try product("6 nug", itemID: "mcd-au-chicken-mcnuggets", variantID: "mcd-au-mcnuggets-6")
        let nuggetResult = await FoodQueryResolutionService.resolve(selection: try #require(nuggets.restaurantSelection))
        #expect(nuggetResult.restaurantMatch?.menuItem.id == "mcd-au-chicken-mcnuggets")
        #expect(nuggetResult.restaurantMatch?.selectedVariant?.id == "mcd-au-mcnuggets-6")
        #expect(nuggetResult.restaurantMatch?.quantity == 1)
        #expect(nuggetResult.analysis?.calories == 216)
        #expect(nuggetResult.analysis?.selectedServingQuantity == 6)
    }

    @Test func parentSelectionRetainsIdentityThroughClarification() async throws {
        let parent = try product("wonderm", itemID: "boost-au-wondermelon")
        let selection = try #require(parent.restaurantSelection)
        let pending = await FoodQueryResolutionService.resolve(selection: selection)
        #expect(pending.restaurantSelection == selection)
        #expect(pending.restaurantMatch?.menuItem.id == selection.itemID)
        #expect(pending.restaurantMatch?.clarificationPlan.groups.map(\.reason) == [.size])

        let completed = await FoodQueryResolutionService.resolve(
            selection: try #require(pending.restaurantSelection), clarificationAnswer: "Size: Medium"
        )
        #expect(completed.restaurantSelection == selection)
        #expect(completed.restaurantMatch?.menuItem.id == selection.itemID)
        #expect(completed.restaurantMatch?.selectedVariant?.id == "boost-au-wondermelon-medium")
        #expect(completed.restaurantMatch?.clarificationPlan.isEmpty == true)
        #expect(completed.analysis?.calories == 156)
    }

    @Test func selectedConfiguredMealBecomesTheContinuationIdentity() async throws {
        let burger = try product("Zinger", itemID: "kfc-au-zinger-burger")
        let burgerSelection = try #require(burger.restaurantSelection)
        #expect(burgerSelection.restaurantID == "kfc_au")
        let order = await FoodQueryResolutionService.resolve(selection: burgerSelection)
        #expect(order.restaurantMatch?.menuItem.id == "kfc-au-zinger-burger")
        #expect(order.restaurantMatch?.clarificationPlan.groups.map(\.id) == ["order"])

        let box = await FoodQueryResolutionService.resolve(
            selection: burgerSelection, clarificationAnswer: "Order: Zinger Box"
        )
        #expect(box.restaurantMatch?.menuItem.id == "kfc-au-zinger-box-regular")
        #expect(box.restaurantMatch?.menuItem.mealConfigurations.first?.id
                == "kfc-au-zinger-box-regular-components")
        #expect(box.restaurantMatch?.clarificationPlan.groups.map(\.id)
                == ["chicken", "first-side", "second-side", "drink"])
        let boxSelection = try #require(box.restaurantSelection)
        #expect(boxSelection.restaurantID == "kfc_au")
        #expect(boxSelection.itemID == "kfc-au-zinger-box-regular")
        #expect(boxSelection.variantID == nil)

        let completed = await FoodQueryResolutionService.resolve(
            selection: boxSelection,
            clarificationAnswer: "Chicken: 3 Wicked Wings; First side: Regular Chips; Second side: Regular Potato & Gravy; Drink: Regular Pepsi Max"
        )
        #expect(completed.restaurantSelection == boxSelection)
        #expect(completed.restaurantMatch?.menuItem.id == "kfc-au-zinger-box-regular")
        #expect(completed.restaurantMatch?.clarificationPlan.isEmpty == true)
        #expect(completed.restaurantMatch?.resolvedComponents.map(\.groupID)
                == ["chicken", "first-side", "second-side", "drink"])
        #expect(completed.restaurantMatch?.resolvedComponents.map(\.sourceItemID)
                == ["kfc-au-3-wicked-wings", "kfc-au-regular-chips", "kfc-au-potato-gravy", "kfc-au-regular-pepsi-max"])
        #expect(completed.analysis?.calories == 1026)
        #expect(completed.analysis?.nutritionSource == "Verified restaurant nutrition")
    }

    @Test func staleOrWrongIDsNeverFallBackToTextOrAI() async throws {
        let index = try #require(RestaurantFoodSearchIndex.bundled())
        #expect(index.search("KFC").first?.restaurantSelection == nil)
        let selections = [
            RestaurantFoodSelection(restaurantID: "mcdonalds_au", itemID: "not-an-item", variantID: nil),
            RestaurantFoodSelection(restaurantID: "kfc_au", itemID: "mcd-au-big-mac", variantID: nil),
            RestaurantFoodSelection(restaurantID: "boost_au", itemID: "boost-au-wondermelon", variantID: "not-a-variant")
        ]
        for selection in selections {
            let result = await FoodQueryResolutionService.resolve(selection: selection)
            #expect(result.restaurantMatch == nil)
            #expect(result.analysis == nil)
            #expect(result.route?.state == .needsClarification)
            #expect(result.unresolvedComponents.count == 1)
        }
    }
}
