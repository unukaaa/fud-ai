import Testing
@testable import calorietracker

@MainActor struct FoodQueryInterpreterTests {
    @Test func resolutionDiagnosticsCaptureMixedSuccess() async throws {
        let query = "zinger burger homemade potato salad"
        let result = try await FoodQueryResolutionService.resolve(description: query, estimate: { _ in
            GeminiService.FoodAnalysis(name: "Homemade potato salad", calories: 180,
                                       protein: 3, carbs: 24, fat: 8, servingSizeGrams: 150)
        })
        #if DEBUG
        let trace = result.debugDiagnostics(for: query)
        #expect(trace.complete)
        #expect(trace.routeState == .ordinaryFoodFallback)
        #expect(trace.components.count == 2)
        #expect(trace.attempts.contains { $0.resolver == "RestaurantNutritionProvider" && $0.candidateItemID != nil })
        #expect(trace.attempts.contains { $0.resolver == "Text nutrition fallback" && $0.outcome == "selected" })
        #expect(trace.text.contains("Completeness:"))
        #endif
    }

    @Test func resolutionDiagnosticsCaptureBrandDiscovery() async throws {
        let result = try await FoodQueryResolutionService.resolve(description: "KFC", estimate: { _ in
            Issue.record("Brand discovery must not invoke nutrition fallback")
            return GeminiService.FoodAnalysis(name: "Unknown", calories: 0, protein: 0, carbs: 0, fat: 0,
                                              servingSizeGrams: 0)
        })
        #if DEBUG
        let trace = result.debugDiagnostics(for: "KFC")
        #expect(trace.routeState == .brandDiscovery)
        #expect(trace.attempts.count == 1)
        #expect(trace.attempts[0].outcome == "brandDiscovery")
        #endif
    }

    @Test func resolutionDiagnosticsCaptureKnownFood() async throws {
        let result = try await FoodQueryResolutionService.resolve(description: "Big Mac")
        #if DEBUG
        let trace = result.debugDiagnostics(for: "Big Mac")
        #expect(trace.routeState == .resolvedFood)
        #expect(trace.complete)
        #expect(trace.attempts.contains { $0.candidateItemID != nil && $0.outcome == "selected" })
        #endif
    }

    @Test func resolutionDiagnosticsCaptureOrdinaryFallback() async throws {
        let query = "homemade potato salad"
        let result = try await FoodQueryResolutionService.resolve(description: query, estimate: { _ in
            GeminiService.FoodAnalysis(name: "Homemade potato salad", calories: 180,
                                       protein: 3, carbs: 24, fat: 8, servingSizeGrams: 150)
        })
        #if DEBUG
        let trace = result.debugDiagnostics(for: query)
        #expect(trace.routeState == .ordinaryFoodFallback)
        #expect(trace.complete)
        #expect(trace.attempts.contains { $0.resolver == "Text nutrition fallback" && $0.outcome == "selected" })
        #endif
    }

    @Test func resolutionDiagnosticsCaptureUnresolvedIdentity() async throws {
        let query = "zxqv blorp"
        let result = try await FoodQueryResolutionService.resolve(description: query, estimate: { _ in
            GeminiService.FoodAnalysis(name: "Unrelated food", calories: 100,
                                       protein: 1, carbs: 20, fat: 1, servingSizeGrams: 100)
        })
        #if DEBUG
        let trace = result.debugDiagnostics(for: query)
        #expect(!trace.complete)
        #expect(trace.attempts.contains { $0.outcome == "identityRejected" })
        #expect(trace.components.contains { $0.state == .unresolved && $0.reason != nil })
        #endif
    }

    @Test func resolutionDiagnosticsCaptureMixedFailure() async throws {
        let query = "zinger burger homemade potato salad"
        let result = try await FoodQueryResolutionService.resolve(description: query, estimate: { _ in
            GeminiService.FoodAnalysis(name: "Garden greens", calories: 50,
                                       protein: 2, carbs: 8, fat: 1, servingSizeGrams: 100)
        })
        #if DEBUG
        let trace = result.debugDiagnostics(for: query)
        #expect(!trace.complete)
        #expect(trace.components.contains { $0.state == .verifiedRestaurant })
        #expect(trace.components.contains { $0.state == .unresolved && $0.reason != nil })
        #expect(trace.attempts.contains { $0.outcome == "identityRejected" })
        #endif
    }

    @Test(arguments: ["KFC", "Boost", "Maccas"])
    func brandOnlyQueryRoutesToDiscoveryWithoutCallingAI(query: String) async throws {
        var estimated = false
        let result = try await FoodQueryResolutionService.resolve(
            description: query,
            estimate: { _ in
                estimated = true
                return GeminiService.FoodAnalysis(name: "Guessed meal", calories: 500,
                                                  protein: 10, carbs: 50, fat: 20, servingSizeGrams: 300)
            })
        #expect(result.route?.state == .brandDiscovery)
        #expect(result.analysis == nil)
        #expect(!estimated)
    }

    @Test(arguments: ["Big Mac", "Wondermelon"])
    func knownMenuItemRoutesAsResolvedFood(query: String) {
        let route = FoodIntentRouter.route(query)
        #expect(route.state == .resolvedFood)
        #expect(route.matchedMenuItems.count == 1)
    }

    @Test func ordinaryFoodAndLocationRemainSeparate() {
        let salad = FoodIntentRouter.route("homemade potato salad")
        #expect(salad.state == .ordinaryFoodFallback)
        let roll = FoodIntentRouter.route("chicken schnitzel roll from local bakery")
        #expect(roll.state == .ordinaryFoodFallback)
        #expect(roll.foodIdentity == "chicken schnitzel roll")
        #expect(roll.locationContext == "local bakery")
        let analysis = GeminiService.FoodAnalysis(name: "Chicken schnitzel roll", calories: 550,
                                                  protein: 25, carbs: 55, fat: 25, servingSizeGrams: 300)
        #expect(FoodQueryResolutionService.trackEstimate(
            analysis, query: "chicken schnitzel roll from local bakery").isComplete)
    }

    @Test func unsupportedProductNeedsPreservedIdentityAndRemainsUnverified() {
        let matching = GeminiService.FoodAnalysis(name: "Mango Boost drink", calories: 180,
                                                  protein: 2, carbs: 40, fat: 1, servingSizeGrams: 350)
        let substituted = GeminiService.FoodAnalysis(name: "Mango smoothie", calories: 180,
                                                     protein: 2, carbs: 40, fat: 1, servingSizeGrams: 350)
        #expect(FoodIntentRouter.route("Mango boost", analysis: matching).state == .unverifiedProductEstimate)
        #expect(FoodIntentRouter.route("Mango boost", analysis: substituted).state == .needsClarification)
        #expect(FoodIntentRouter.route("Mango Magic", analysis: matching,
                                       productIdentityIsKnown: true).state == .needsClarification)
        let named = GeminiService.FoodAnalysis(name: "Mango Magic drink", calories: 180,
                                               protein: 2, carbs: 40, fat: 1, servingSizeGrams: 350)
        #expect(FoodIntentRouter.route("Mango Magic", analysis: named,
                                       productIdentityIsKnown: true).state == .unverifiedProductEstimate)
    }

    @Test func unclearInputNeedsClarificationAfterFailedIdentityCheck() {
        let unknown = GeminiService.FoodAnalysis(name: "Unknown item", calories: 0,
                                                 protein: 0, carbs: 0, fat: 0, servingSizeGrams: 0)
        #expect(FoodIntentRouter.route("zxqv blorp", analysis: unknown).state == .needsClarification)
    }

    private func estimated(_ query: String) async throws -> GeminiService.FoodAnalysis {
        let normalized = query.lowercased()
        if normalized.contains("potato salad") {
            return GeminiService.FoodAnalysis(name: "Homemade potato salad", calories: 180, protein: 3,
                                              carbs: 24, fat: 8, servingSizeGrams: 150)
        }
        if normalized.contains("coleslaw") {
            return GeminiService.FoodAnalysis(name: "Homemade coleslaw", calories: 120, protein: 2,
                                              carbs: 12, fat: 7, servingSizeGrams: 100)
        }
        if normalized.contains("banana") {
            return GeminiService.FoodAnalysis(name: "Banana", calories: 100, protein: 1,
                                              carbs: 25, fat: 0, servingSizeGrams: 118)
        }
        if normalized.contains("coke") || normalized.contains("cola") {
            return GeminiService.FoodAnalysis(name: "Coca-Cola Zero Sugar", calories: 3, protein: 0,
                                              carbs: 0, fat: 0, servingSizeGrams: 375)
        }
        if normalized.contains("egg") {
            let includesCoffee = normalized.contains("coffee")
            let includesOil = normalized.contains("oil")
            var analysis = GeminiService.FoodAnalysis(name: includesCoffee ? "Eggs rye toast coffee with milk" : "Eggs rye toast", calories: includesCoffee ? 350 : (includesOil ? 350 : 310),
                                                      protein: 20, carbs: 35, fat: 12, servingSizeGrams: 300)
            analysis.ingredients = [
                MealIngredient(name: "Eggs", grams: 100, calories: 150, protein: 12, carbs: 1, fat: 10),
                MealIngredient(name: "Rye toast", grams: 80, calories: 160, protein: 5, carbs: 30, fat: 2)
            ]
            if includesCoffee {
                analysis.ingredients.append(MealIngredient(name: "Coffee with milk", grams: 120,
                                                           calories: 40, protein: 3, carbs: 4, fat: 0))
            }
            if includesOil {
                analysis.ingredients.append(MealIngredient(name: "Oil", grams: 5,
                                                           calories: 40, protein: 0, carbs: 0, fat: 4))
            }
            return analysis
        }
        if normalized.contains("chicken") {
            var analysis = GeminiService.FoodAnalysis(name: "Chicken rice broccoli", calories: 450,
                                                      protein: 35, carbs: 50, fat: 10, servingSizeGrams: 400)
            analysis.ingredients = [
                MealIngredient(name: "Chicken", grams: 150, calories: 240, protein: 30, carbs: 0, fat: 8),
                MealIngredient(name: "Rice", grams: 150, calories: 170, protein: 4, carbs: 38, fat: 1),
                MealIngredient(name: "Broccoli", grams: 100, calories: 40, protein: 1, carbs: 12, fat: 1)
            ]
            return analysis
        }
        return GeminiService.FoodAnalysis(name: query, calories: 100, protein: 1, carbs: 15, fat: 3, servingSizeGrams: 100)
    }

    @Test(arguments: ["zingo buga cog zero", "zingo buga cog zero 2 wiked wings", "zingo buga cog zero too wiked wings"])
    func productionMixedRestaurantQueryAccountsForEveryItem(query: String) async throws {
        let resolution = try await FoodQueryResolutionService.resolve(description: query, estimate: estimated)
        #expect(resolution.isComplete)
        #expect(resolution.components.count == (query.contains("wings") ? 3 : 2))
        #expect(resolution.components.contains { $0.name.lowercased().contains("zinger") })
        #expect(resolution.components.contains { $0.name.lowercased().contains("cola") })
        #expect(resolution.components.contains { $0.name.lowercased().contains("zinger") && $0.state == .verifiedRestaurant })
        #expect(resolution.analysis?.calories == resolution.components.compactMap(\.calories).reduce(0, +))
        if query.contains("wings") {
            #expect(resolution.components.contains { $0.name.lowercased().contains("wing") && $0.quantity == 2 && $0.state == .verifiedRestaurant })
        }
    }

    @Test func productionMixedSourceMealKeepsRestaurantAndEstimatedFood() async throws {
        let resolution = try await FoodQueryResolutionService.resolve(
            description: "Zinger Burger homemade potato salad", estimate: estimated)
        #expect(resolution.isComplete)
        #expect(resolution.components.count == 2)
        #expect(resolution.components.contains { $0.state == .verifiedRestaurant && $0.name.contains("Zinger") })
        #expect(resolution.components.contains { $0.state == .aiEstimate && $0.name.contains("potato salad") })
        #expect(resolution.analysis?.nutritionSource == "Mixed nutrition sources")
        #expect(resolution.analysis?.ingredients.count == 2)
        #expect(resolution.analysis?.calories == resolution.components.compactMap(\.calories).reduce(0, +))
    }

    @Test func compositeFallbackUsesDishIdentityNotItsIngredientNames() async throws {
        let resolution = try await FoodQueryResolutionService.resolve(
            description: "zinger burger homemade potato salad",
            estimate: { _ in
                var analysis = GeminiService.FoodAnalysis(name: "Homemade potato salad", calories: 180,
                                                          protein: 3, carbs: 24, fat: 8, servingSizeGrams: 150)
                analysis.ingredients = [
                    MealIngredient(name: "Potatoes", grams: 110, calories: 100, protein: 2, carbs: 22, fat: 0),
                    MealIngredient(name: "Mayonnaise", grams: 40, calories: 80, protein: 1, carbs: 2, fat: 8)
                ]
                return analysis
            })
        #expect(resolution.isComplete)
        #expect(resolution.components.count == 2)
        #expect(resolution.components[0].state == .verifiedRestaurant)
        #expect(resolution.components[1].name == "Homemade potato salad")
        #expect(resolution.components[1].state == .aiEstimate)
        #expect(resolution.analysis?.nutritionSource == "Mixed nutrition sources")
        #expect(resolution.analysis?.calories == resolution.components.compactMap(\.calories).reduce(0, +))
        #if DEBUG
        let trace = resolution.debugDiagnostics(for: "zinger burger homemade potato salad")
        #expect(trace.complete)
        #expect(trace.components.count == 2)
        #expect(!trace.components[0].deterministicCandidates.isEmpty)
        #expect(trace.components[1].selectedResolver == "aiEstimate")
        #expect(trace.components[1].normalizedQuery == "homemade potato salad")
        #endif
    }

    @Test func pizzaFallbackStillCombinesWithVerifiedBurger() async throws {
        let resolution = try await FoodQueryResolutionService.resolve(
            description: "zinger burger a slice of pizza",
            estimate: { _ in GeminiService.FoodAnalysis(name: "A slice of pizza", calories: 285,
                                                         protein: 12, carbs: 36, fat: 10,
                                                         servingSizeGrams: 120) })
        #expect(resolution.isComplete)
        #expect(resolution.components.count == 2)
        #expect(resolution.components[0].state == .verifiedRestaurant)
        #expect(resolution.components[1].state == .aiEstimate)
        #expect(resolution.analysis?.calories == resolution.components.compactMap(\.calories).reduce(0, +))
    }

    @Test(arguments: ["zinger burger a slice of pizza", "zinger burger banana",
                      "Big Mac and homemade coleslaw", "6 nuggets and apple"])
    func mixedFallbackKeepsEveryFoodAndQuantity(query: String) async throws {
        let resolution = try await FoodQueryResolutionService.resolve(
            description: query,
            estimate: { phrase in
                let normalized = phrase.lowercased()
                let name = normalized.contains("pizza") ? "A slice of pizza"
                    : normalized.contains("banana") ? "Banana"
                    : normalized.contains("coleslaw") ? "Homemade coleslaw" : "Apple"
                return GeminiService.FoodAnalysis(name: name, calories: 100, protein: 1,
                                                  carbs: 15, fat: 3, servingSizeGrams: 100)
            })
        #expect(resolution.isComplete)
        #expect(resolution.components.count == 2)
        #expect(resolution.components[0].state == .verifiedRestaurant)
        #expect(resolution.components[1].state == .aiEstimate)
        #expect(resolution.analysis?.calories == resolution.components.compactMap(\.calories).reduce(0, +))
        if query.contains("nuggets") {
            #expect(resolution.components[0].quantity == 1)
            #expect(resolution.components[0].calories == 216)
        }
    }

    @Test func ambiguousBrandedPhrasesRequireIdentityPreservation() async throws {
        for (query, substitute) in [("Mango boost", "Mango smoothie"),
                                    ("Mango magic", "Mango smoothie"),
                                    ("Lychee crush", "Lychee soda")] {
            let unresolved = try await FoodQueryResolutionService.resolve(
                description: query,
                estimate: { _ in GeminiService.FoodAnalysis(name: substitute, calories: 150,
                                                             protein: 1, carbs: 30, fat: 1,
                                                             servingSizeGrams: 300) })
            #expect(!unresolved.isComplete)
            #expect(unresolved.unresolvedComponents.count == 1)
        }
        let preserved = try await FoodQueryResolutionService.resolve(
            description: "Mango magic",
            estimate: { _ in GeminiService.FoodAnalysis(name: "Mango Magic drink", calories: 150,
                                                         protein: 1, carbs: 30, fat: 1,
                                                         servingSizeGrams: 300) })
        #expect(preserved.isComplete)
        #expect(preserved.components.first?.state == .aiEstimate)
        #expect(preserved.components.first?.sourceItemID == nil)
    }

    @Test(arguments: ["zinger burger homemade potato salad", "zinger burger home made potato salad"])
    func deviceResidualFoodStaysOnePhrase(query: String) async throws {
        let resolution = try await FoodQueryResolutionService.resolve(description: query, estimate: estimated)
        #expect(resolution.isComplete)
        #expect(resolution.components.count == 2)
        #expect(resolution.components.contains { $0.state == .verifiedRestaurant && $0.name.contains("Zinger") })
        #expect(resolution.components.contains { $0.state == .aiEstimate && $0.name == "Homemade potato salad" })
        #expect(resolution.analysis?.calories == resolution.components.compactMap(\.calories).reduce(0, +))
    }

    @Test(arguments: ["too eggs ry toast bit oil", "2 eggs rye toast bit of oil"])
    func deviceConversationalQuantitiesSurviveClarification(query: String) async throws {
        let initial = try await FoodQueryResolutionService.resolve(description: query, estimate: estimated)
        #expect(initial.isComplete)
        #expect(initial.components.map(\.name).contains("Oil"))
        // This mirrors ContentView's Phase 2D continuation after the toast choice.
        let answer = try await estimated("2 eggs rye toast bit of oil\nClarification: Toast quantity: 2 slices")
        let final = FoodQueryResolutionService.trackEstimate(answer, query: query)
        #expect(final.isComplete)
        #expect(final.unresolvedComponents.isEmpty)
        #expect(final.components.map(\.name).contains("Oil"))
        #expect(final.analysis?.calories == final.components.compactMap(\.calories).reduce(0, +))
    }

    @Test func otherCompositeFoodsKeepTheirPhraseBoundaries() async throws {
        let coleslaw = try await FoodQueryResolutionService.resolve(
            description: "zinger burger homemade coleslaw", estimate: estimated)
        #expect(coleslaw.isComplete)
        #expect(coleslaw.components.count == 2)
        #expect(coleslaw.components.contains { $0.name == "Homemade coleslaw" })

        for query in ["coffee with milk", "greek yoghurt with berries"] {
            let result = try await FoodQueryResolutionService.resolve(description: query, estimate: estimated)
            #expect(result.isComplete)
            #expect(result.components.count == 1)
            #expect(result.components.first?.query == query)
        }
    }

    @Test func genuinelyUnknownFoodPhraseRemainsUnresolved() async throws {
        let resolution = try await FoodQueryResolutionService.resolve(
            description: "zinger burger mysterious garden salad",
            estimate: { _ in GeminiService.FoodAnalysis(name: "Garden", calories: 100, protein: 1,
                                                         carbs: 20, fat: 1, servingSizeGrams: 100) })
        #expect(!resolution.isComplete)
        #expect(resolution.components.contains { $0.state == .verifiedRestaurant })
        #expect(resolution.unresolvedComponents.count == 1)
        #expect(resolution.unresolvedComponents.first?.name == "mysterious garden salad")
    }

    @Test func threeSourceQueryAccountsForDrinkAndHomemadeSide() async throws {
        let resolution = try await FoodQueryResolutionService.resolve(
            description: "Zinger burger Coke Zero homemade potato salad", estimate: estimated)
        #expect(resolution.isComplete)
        #expect(resolution.components.count == 3)
        #expect(resolution.components.contains { $0.name.contains("Zinger") && $0.state == .verifiedRestaurant })
        #expect(resolution.components.contains { $0.name.contains("Coca-Cola") })
        #expect(resolution.components.contains { $0.name.contains("potato salad") && $0.state == .aiEstimate })
        #expect(resolution.analysis?.calories == resolution.components.compactMap(\.calories).reduce(0, +))
    }

    @Test(arguments: ["Big Mac medium chips Coke Zero", "6 nuggets Coke Zero"])
    func productionMcDonaldsComponentsAvoidPackMultiplication(query: String) async throws {
        let resolution = try await FoodQueryResolutionService.resolve(description: query, estimate: estimated)
        #expect(resolution.isComplete)
        #expect(resolution.components.count == (query.contains("Big Mac") ? 3 : 2))
        #expect(resolution.analysis?.calories == resolution.components.compactMap(\.calories).reduce(0, +))
        #expect(resolution.analysis?.calories == (query.contains("Big Mac") ? 876 : 219))
        if query.contains("nuggets") {
            #expect(resolution.components.contains { $0.name.contains("McNuggets") && $0.quantity == 1 })
        }
    }

    @Test func configuredMealClarificationStaysOneParent() async throws {
        let resolution = try await FoodQueryResolutionService.resolve(
            description: "Big Mac meal\nClarification: Size: Medium with Coke No Sugar", estimate: estimated)
        #expect(resolution.restaurantMatch?.menuItem.id == "mcd-au-big-mac-meal")
        #expect(resolution.analysis?.calories == 876)
        #expect(resolution.components.count == 1)
        #expect(resolution.components.first?.quantity == 1)
    }

    @Test func configuredMealAndExtraFoodCountParentOnce() async throws {
        let resolution = try await FoodQueryResolutionService.resolve(
            description: "Big Mac meal with medium fries and Coke No Sugar banana", estimate: estimated)
        #expect(resolution.isComplete)
        #expect(resolution.components.count == 2)
        #expect(resolution.components.first?.sourceItemID == "mcd-au-big-mac-meal")
        #expect(resolution.components.first?.quantity == 1)
        #expect(resolution.analysis?.calories == 976)
    }

    @Test func unsupportedModifierKeepsPublishedValueWithPartialProvenance() async throws {
        let resolution = try await FoodQueryResolutionService.resolve(
            description: "Big Mac no sauce", estimate: estimated)
        #expect(resolution.isComplete)
        #expect(resolution.analysis?.calories == 557)
        #expect(resolution.components.first?.state == .partiallyVerifiedRestaurant)
    }

    @Test(arguments: ["2 eggs rye toast", "2 eggs rye toast coffee with milk", "chicken rice broccoli"])
    func genericFoodBreakdownTracksEveryNamedIngredient(query: String) async throws {
        let resolution = try await FoodQueryResolutionService.resolve(description: query, estimate: estimated)
        #expect(resolution.isComplete)
        #expect(resolution.components.count == (query.contains("coffee") || query.contains("chicken") ? 3 : 2))
        #expect(resolution.analysis?.calories == resolution.components.compactMap(\.calories).reduce(0, +))
    }

    @Test func missingGenericFoodIsExplicitlyUnresolved() async throws {
        let resolution = try await FoodQueryResolutionService.resolve(
            description: "Zinger Burger homemade potato salad",
            estimate: { query in
                GeminiService.FoodAnalysis(name: "Potato", calories: 100, protein: 1,
                                           carbs: 20, fat: 1, servingSizeGrams: 100)
            })
        #expect(!resolution.isComplete)
        #expect(resolution.components.contains { $0.state == .unresolved && $0.name == "homemade potato salad" })
        #expect(resolution.components.contains { $0.state == .verifiedRestaurant })
        #expect(resolution.analysis == nil)
        let message = GeminiService.analysisErrorMessage(
            IncompleteFoodQueryError(foods: resolution.unresolvedComponents.map(\.name)))
        #expect(message.contains("salad"))
    }

    @Test func failedEstimateLeavesVerifiedComponentAndExplicitUnresolvedFood() async throws {
        struct EstimateUnavailable: Error {}
        let resolution = try await FoodQueryResolutionService.resolve(
            description: "Zinger Burger homemade potato salad",
            estimate: { _ in throw EstimateUnavailable() })
        #expect(!resolution.isComplete)
        #expect(resolution.components.contains { $0.state == .verifiedRestaurant })
        #expect(resolution.components.contains { $0.state == .unresolved && $0.name.contains("potato salad") })
    }

    @Test func mixedQueryStillPropagatesHostedQuotaErrors() async {
        do {
            _ = try await FoodQueryResolutionService.resolve(
                description: "Zinger Burger homemade potato salad",
                estimate: { _ in throw HostedAIQuotaError.quotaExceeded(remainingDaily: 0, creditBank: 0) })
            Issue.record("Expected the hosted quota error")
        } catch let error as HostedAIQuotaError {
            #expect(error == .quotaExceeded(remainingDaily: 0, creditBank: 0))
        } catch {
            Issue.record("Unexpected error: \(error)")
        }
    }

    @Test func partialAUSNUTAndEstimateKeepSeparateIngredientProvenance() async throws {
        let resolution = try await FoodQueryResolutionService.resolve(
            description: "grilled chicken breast with mystery sauce",
            estimate: { _ in
                var analysis = GeminiService.FoodAnalysis(name: "Grilled chicken breast with mystery sauce",
                                                          calories: 400, protein: 60, carbs: 5,
                                                          fat: 13, servingSizeGrams: 220)
                analysis.ingredients = [
                    MealIngredient(name: "Grilled chicken breast", grams: 200, calories: 330,
                                   protein: 60, carbs: 0, fat: 8),
                    MealIngredient(name: "Mystery sauce", grams: 20, calories: 70,
                                   protein: 0, carbs: 5, fat: 5)
                ]
                return AustralianNutritionService.applyingBestAustralianMatch(to: analysis)
            })
        #expect(resolution.isComplete)
        #expect(resolution.components.map(\.state) == [.ausnut, .aiEstimate])
        #expect(resolution.analysis?.calories == resolution.components.compactMap(\.calories).reduce(0, +))
    }

    @Test func mixedRestaurantAndPartialAUSNUTPersistEachIngredientSource() async throws {
        let resolution = try await FoodQueryResolutionService.resolve(
            description: "Zinger Burger grilled chicken breast with mystery sauce",
            estimate: { _ in
                var analysis = GeminiService.FoodAnalysis(name: "Grilled chicken breast with mystery sauce",
                                                          calories: 400, protein: 60, carbs: 5,
                                                          fat: 13, servingSizeGrams: 220)
                analysis.ingredients = [
                    MealIngredient(name: "Grilled chicken breast", grams: 200, calories: 330,
                                   protein: 60, carbs: 0, fat: 8),
                    MealIngredient(name: "Mystery sauce", grams: 20, calories: 70,
                                   protein: 0, carbs: 5, fat: 5)
                ]
                return AustralianNutritionService.applyingBestAustralianMatch(to: analysis)
            })
        #expect(resolution.isComplete)
        #expect(resolution.components.map(\.state) == [.verifiedRestaurant, .ausnut, .aiEstimate])
        #expect(resolution.analysis?.ingredients.map(\.nutritionSource) == [
            "Verified restaurant nutrition", "AUSNUT Australia", "AI estimate"
        ])
        #expect(resolution.analysis?.calories == resolution.analysis?.ingredients.ingredientTotals.calories)
    }
    @Test func originalDeviceFailurePreservesBothFoods() {
        let result = FoodQueryInterpreter.interpret("zingo buga cog zero")
        #expect(result.items.map(\.interpretedName) == ["Zinger Burger", "Coca-Cola Zero Sugar"])
        #expect(result.interpretedText.contains("Zinger Burger"))
        #expect(result.interpretedText.contains("Coca-Cola Zero Sugar"))
        #expect(result.hasMultipleItems)
    }

    @Test(arguments: [
        ("kfc zinga buga", "Zinger Burger"),
        ("maccas bigmak", "Big Mac"),
        ("wonda melon original", "Wondermelon")
    ])
    func noisyRestaurantLanguageFindsCanonicalFood(input: String, expected: String) {
        let result = FoodQueryInterpreter.interpret(input)
        #expect(result.items.contains { $0.interpretedName == expected })
    }

    @Test func quantityAndGenericLanguageAreConservativelyNormalized() {
        #expect(FoodQueryInterpreter.interpret("too eggs ry toast").interpretedText.contains("2 eggs"))
        #expect(FoodQueryInterpreter.interpret("chiken rice brocoli").interpretedText.contains("chicken rice broccoli"))
        #expect(FoodQueryInterpreter.interpret("coffy milk").interpretedText.contains("coffee milk"))
    }

    @Test(arguments: ["apple", "coke", "burger", "chicken", "wonder"])
    func ambiguousShortInputDoesNotBecomeBrandedFood(input: String) {
        let result = FoodQueryInterpreter.interpret(input)
        #expect(result.items.isEmpty)
        #expect(result.interpretedText == input)
    }

    @Test func modifierRelationshipIsNotSplitFromFood() {
        let result = FoodQueryInterpreter.interpret("big mak no sauce")
        #expect(result.interpretedText.contains("Big Mac no sauce"))
    }

    @Test func productionRestaurantRouteUsesInterpreterBeforeResolver() async {
        let result = await RestaurantNutritionAnalysisService.match(description: "maccas bigmak")
        #expect(result?.menuItem.id == "mcd-au-big-mac")
        #expect(result?.foodAnalysis?.calories == 557)
    }

    @Test func mixedRestaurantDatasetQueryIsNotPartiallyResolved() async {
        let result = await RestaurantNutritionAnalysisService.match(description: "zingo buga cog zero")
        #expect(result == nil)
    }

    @Test func plausibilityGuardFlagsContradictoryTinyResult() {
        let intent = FoodQueryInterpreter.interpret("zinga buga")
        let analysis = GeminiService.FoodAnalysis(name: "Food", calories: 10, protein: 0, carbs: 0, fat: 0, servingSizeGrams: 1)
        let guarded = FoodQueryInterpreter.applyingPlausibilityGuard(to: analysis, intent: intent)
        #expect(guarded.nutritionConfidence == "Low")
        #expect(guarded.nutritionSourceDetail?.contains("conflict") == true)
    }

    @Test(arguments: [
        ("one egg", "1 egg"), ("two eggs", "2 eggs"), ("too eggs", "2 eggs"),
        ("four eggs", "4 eggs"), ("for wicked wings", "4 Wicked Wing")
    ])
    func spokenQuantitiesStayAttached(input: String, expected: String) {
        #expect(FoodQueryInterpreter.interpret(input).interpretedText.contains(expected))
    }

    @Test(arguments: [("six nuggies", "6"), ("ten nuggets", "10")])
    func nuggetQuantitiesSurviveInterpretation(input: String, quantity: String) {
        let result = FoodQueryInterpreter.interpret(input).interpretedText.lowercased()
        #expect(result.contains(quantity))
        #expect(result.contains("nugget"))
    }

    @Test(arguments: [
        ("nana", "banana"), ("aple", "apple"), ("stake mash veg", "steak mash vegetables"),
        ("greek yog berries", "greek yoghurt berries"), ("coffy milk", "coffee milk"),
        ("latay", "latte"), ("too eggs ry toast", "2 eggs rye toast")
    ])
    func ordinaryNoiseIsRecoveredWithoutBranding(input: String, expected: String) {
        let result = FoodQueryInterpreter.interpret(input)
        #expect(result.interpretedText == expected)
        #expect(result.items.isEmpty)
    }

    @Test(arguments: [
        "zero", "meal", "box", "chips", "toast", "rice", "milk", "shake", "wing", "mac",
        "big", "original", "medium", "large", "water", "juice", "coffee", "latte"
    ])
    func additionalShortGenericInputsDoNotBecomeBranded(input: String) {
        #expect(FoodQueryInterpreter.interpret(input).items.isEmpty)
    }

    @Test func punctuationCasingAndFillerPreserveBothRestaurantFoods() {
        for input in [
            "ZINGER BURGER COKE ZERO", "Zinger burger, Coke Zero", "zinger burger + coke zero",
            "zinger burger and coke zero", "i had a zinger burger and coke zero"
        ] {
            let names = FoodQueryInterpreter.interpret(input).items.map(\.interpretedName)
            #expect(names.contains("Zinger Burger"))
            #expect(names.contains("Coca-Cola Zero Sugar"))
        }
    }

    @Test func deterministicRestaurantRouteRejectsUnresolvedFoodRemainder() async {
        #expect(await RestaurantNutritionAnalysisService.match(description: "Big Mac apple") == nil)
        #expect(await RestaurantNutritionAnalysisService.match(description: "zinger burger homemade potato salad") == nil)
        #expect(await RestaurantNutritionAnalysisService.match(description: "maccas nuggets banana") == nil)
    }

    @Test func cleanQuantityAndRestaurantContextStillResolve() async {
        let wings = await RestaurantNutritionAnalysisService.match(description: "2 Wicked Wings")
        #expect(wings?.menuItem.id == "kfc-au-wicked-wing")
        #expect(wings?.quantity == 2)
        let zinger = await RestaurantNutritionAnalysisService.match(description: "kfc zinga buga")
        #expect(zinger?.menuItem.id == "kfc-au-zinger-burger")
    }

    @Test func clarificationPayloadStillPreservesParentMeal() async {
        let bigMac = await RestaurantNutritionAnalysisService.match(
            description: "Big Mac meal\nClarification: Size: Medium with Coke No Sugar"
        )
        #expect(bigMac?.menuItem.id == "mcd-au-big-mac-meal")
        #expect(bigMac?.foodAnalysis?.calories == 876)
        let boost = await RestaurantNutritionAnalysisService.match(
            description: "Wondermelon\nClarification: Size: Original"
        )
        #expect(boost?.menuItem.id == "boost-au-wondermelon")
        #expect(boost?.foodAnalysis?.calories == 191)
    }

    @Test func representativeInterpreterPerformanceRemainsInteractive() {
        let queries = [
            "banana",
            "big mac medium chips coke zero",
            "zinger burger coke zero 2 wicked wings",
            "i had 2 eggs rye toast avocado coffee skim milk"
        ]
        let clock = ContinuousClock()
        let elapsed = clock.measure {
            for query in queries { _ = FoodQueryInterpreter.interpret(query) }
        }
        #expect(elapsed < .seconds(2))
    }
}
