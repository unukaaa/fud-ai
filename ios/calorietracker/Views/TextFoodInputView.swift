import SwiftUI
import Combine

struct TextFoodInputView: View {
    @State private var foodDescription = ""
    @State private var placeholderIndex = 0
    @State private var suggestions: [UnifiedFoodSuggestion] = []
    @State private var restaurantSearchIndex = RestaurantFoodSearchIndex.bundled()
    @State private var ausnutSearchIndex = AUSNUTFoodSearchIndex.bundled()
    @State private var conceptRoute: FoodConceptSearchRoute?
    @State private var conceptChoiceState: FoodConceptChoiceState = .discovery
    @State private var currentCandidateSourceIDs: [String] = []
    @State private var currentClarificationPlan: FoodClarificationPlan?
    @State private var usedClarificationDimensions: Set<FoodClarificationPlan.Dimension> = []
    @State private var selectedClarificationPath: [FoodClarificationStopPolicy.Selection] = []
    @State private var clarificationContext: String?
    @State private var showingAllConceptChoices = false
    @FocusState private var isFocused: Bool
    @Environment(\.accessibilityReduceMotion) private var reduceMotion
    @Environment(\.dynamicTypeSize) private var dynamicTypeSize

    var onCancel: () -> Void
    var onSubmit: (String) -> Void
    var onEstimate: ((String) -> Void)? = nil
    var onSelectRestaurant: ((RestaurantFoodSelection, String) -> Void)? = nil
    var onSelectAUSNUT: ((AUSNUTFoodSelection) -> Void)? = nil

    var placeholders: [LocalizedStringResource] = [
        "2 eggs, toast with butter and a coffee",
        "Chipotle burrito bowl with chicken and rice",
        "Domino's pepperoni pizza, 2 slices",
        "Greek yogurt with granola and blueberries",
    ]

    private let timer = Timer.publish(every: 2, on: .main, in: .common).autoconnect()

    private var meaningfulQuery: String {
        foodDescription.trimmingCharacters(in: .whitespacesAndNewlines)
    }

    private var analyseLabel: LocalizedStringResource {
        meaningfulQuery.isEmpty ? "Analyse" : "Analyse \"\(meaningfulQuery)\""
    }

    private var searchPanelWidth: CGFloat { dynamicTypeSize.isAccessibilitySize ? 360 : 320 }
    private var searchPanelHeight: CGFloat { dynamicTypeSize.isAccessibilitySize ? 520 : 410 }
    private var suggestionAreaHeight: CGFloat { dynamicTypeSize.isAccessibilitySize ? 260 : 190 }

    private func updateSuggestions(for query: String) {
        conceptChoiceState = .discovery
        showingAllConceptChoices = false
        currentCandidateSourceIDs = []
        currentClarificationPlan = nil
        usedClarificationDimensions = []
        selectedClarificationPath = []
        clarificationContext = nil
        guard onSelectRestaurant != nil, !query.isEmpty else {
            suggestions = []
            conceptRoute = nil
            return
        }
        let index = UnifiedFoodSearchIndex(
            restaurants: restaurantSearchIndex,
            ausnut: onSelectAUSNUT == nil ? nil : ausnutSearchIndex
        )
        suggestions = index.search(query, limit: 5)
        conceptRoute = FoodConceptSearchRoute(index.assessIdentity(query), suggestions: suggestions)
    }

    private func selectSource(_ sourceID: String) -> Bool {
        if sourceID.hasPrefix("ausnut:"), let onSelectAUSNUT {
            let foodID = String(sourceID.dropFirst("ausnut:".count))
            guard AustralianNutritionService.identity(forID: foodID) != nil else { return false }
            onSelectAUSNUT(AUSNUTFoodSelection(foodID: foodID))
            return true
        }
        if sourceID.hasPrefix("restaurant:"), let onSelectRestaurant,
           let match = restaurantSearchIndex?.search(meaningfulQuery, limit: 500)
            .first(where: { "restaurant:\($0.id)" == sourceID }),
           let selection = match.restaurantSelection {
            onSelectRestaurant(selection, match.title)
            return true
        }
        return false
    }

    private func sourceTitle(_ sourceID: String) -> String {
        if sourceID.hasPrefix("ausnut:") {
            let foodID = String(sourceID.dropFirst("ausnut:".count))
            return AustralianNutritionService.identity(forID: foodID)?.name ?? sourceID
        }
        if sourceID.hasPrefix("restaurant:"),
           let match = restaurantSearchIndex?.search(meaningfulQuery, limit: 500)
            .first(where: { "restaurant:\($0.id)" == sourceID }) {
            return match.title
        }
        return sourceID
    }

    private var conceptLabels: [String: String] {
        FoodConsumerLabels.choices(currentCandidateSourceIDs.map {
            (id: $0, name: sourceTitle($0))
        })
    }

    private var discoveryLabels: [String: String] {
        FoodConsumerLabels.choices(suggestions.compactMap { result in
            guard case .ausnut(let food) = result else { return nil }
            return (id: food.id, name: food.title)
        })
    }

    private var conceptNeedsSourceBadge: Bool {
        let ids = currentCandidateSourceIDs
        return ids.contains(where: { $0.hasPrefix("ausnut:") })
            && ids.contains(where: { $0.hasPrefix("restaurant:") })
    }

    private func beginConceptChoices(_ route: FoodConceptSearchRoute) {
        currentCandidateSourceIDs = route.candidateSourceIDs
        usedClarificationDimensions = []
        selectedClarificationPath = []
        clarificationContext = nil
        currentClarificationPlan = clarificationPlan(for: currentCandidateSourceIDs)
        showingAllConceptChoices = false
        conceptChoiceState = .choosing
        isFocused = false
    }

    private func clarificationPlan(for sourceIDs: [String]) -> FoodClarificationPlan? {
        switch conceptRoute {
        case .clarification?, .unknownVariant?: break
        default: return nil
        }
        return FoodClarificationPlan.make(
            query: meaningfulQuery,
            sources: sourceIDs.map { (id: $0, name: sourceTitle($0)) },
            excluding: usedClarificationDimensions
        )
    }

    private func choose(_ option: FoodClarificationPlan.Option) {
        if let sourceID = option.resolvedSourceID {
            _ = selectSource(sourceID)
            return
        }
        if let dimension = currentClarificationPlan?.dimension {
            selectedClarificationPath.append(.init(dimension: dimension, key: option.key))
        }
        currentCandidateSourceIDs = option.sourceIDs
        if let dimension = currentClarificationPlan?.dimension {
            usedClarificationDimensions.insert(dimension)
        }
        let stop = FoodClarificationStopPolicy.decide(
            sources: option.sourceIDs.map { (id: $0, name: sourceTitle($0)) },
            selections: selectedClarificationPath
        )
        switch stop {
        case .stop(let sourceID), .optionalRefinement(let sourceID, _):
            if selectSource(sourceID) { return }
        case .required:
            break
        }
        clarificationContext = option.label
        currentClarificationPlan = clarificationPlan(for: option.sourceIDs)
        showingAllConceptChoices = false
    }

    private func handleAnalyse() {
        guard let conceptRoute else {
            onSubmit(meaningfulQuery)
            return
        }
        switch conceptRoute {
        case .sourced(let sourceID, _):
            if !selectSource(sourceID) { beginConceptChoices(conceptRoute) }
        case .clarification, .unknownVariant, .weakAlternatives:
            beginConceptChoices(conceptRoute)
        case .analyse(let query):
            onSubmit(query)
        }
    }

    private var isBrandOnlyQuery: Bool {
        if case .restaurant(let first)? = suggestions.first { return first.kind == .brand }
        return false
    }

    private var analyseButton: some View {
        Button {
            handleAnalyse()
        } label: {
            Text(analyseLabel)
                .font(suggestions.isEmpty ? .headline : .subheadline.weight(.medium))
                .lineLimit(1)
                .truncationMode(.tail)
                .frame(maxWidth: .infinity)
        }
        .tint(AppColors.calorie)
        .controlSize(.large)
        .frame(height: 50)
        .disabled(meaningfulQuery.isEmpty)
        .accessibilityIdentifier("searchFood.analyse")
    }

    private var conceptChoices: some View {
        let labels = conceptLabels
        let showSourceBadge = conceptNeedsSourceBadge
        return ScrollView {
            LazyVStack(alignment: .leading, spacing: 0) {
                if let unresolvedConcept = conceptChoiceState.explicitEstimateQuery {
                    Text("\(unresolvedConcept) — variety not specified")
                        .font(.subheadline.weight(.semibold))
                        .padding(12)
                    Text("No sourced nutrition is selected yet.")
                        .font(.caption)
                        .foregroundStyle(.secondary)
                        .padding(.horizontal, 12)
                    Button("Choose a variety") {
                        conceptChoiceState = .choosing
                    }
                    .padding(12)
                    Button("Estimate instead") {
                        (onEstimate ?? onSubmit)(unresolvedConcept)
                    }
                    .padding(12)
                } else {
                    if let plan = currentClarificationPlan {
                        Text(plan.question)
                            .font(.subheadline.weight(.semibold))
                            .padding(12)
                    } else if conceptRoute?.isWeakAlternative == true {
                        Text("Sourced alternatives")
                            .font(.subheadline.weight(.semibold))
                            .padding(12)
                    } else {
                        Text(clarificationContext.map { "Which \($0.lowercased())?" } ?? "Which one did you mean?")
                            .font(.subheadline.weight(.semibold))
                            .padding(12)
                    }
                    if let conceptRoute {
                        if let plan = currentClarificationPlan {
                            ForEach(plan.options) { option in
                                Button {
                                    choose(option)
                                } label: {
                                    Text(option.label)
                                        .font(.subheadline)
                                        .frame(maxWidth: .infinity, minHeight: 44, alignment: .leading)
                                        .padding(.horizontal, 12)
                                        .contentShape(Rectangle())
                                }
                                .buttonStyle(.plain)
                                .accessibilityIdentifier("searchFood.group.\(option.id)")
                                Divider()
                            }
                        } else {
                            ForEach(Array(currentCandidateSourceIDs.prefix(
                                showingAllConceptChoices ? currentCandidateSourceIDs.count : 8
                            )), id: \.self) { sourceID in
                                Button {
                                    _ = selectSource(sourceID)
                                } label: {
                                    VStack(alignment: .leading, spacing: 2) {
                                        Text(labels[sourceID] ?? sourceTitle(sourceID))
                                            .font(.subheadline)
                                            .multilineTextAlignment(.leading)
                                        if showSourceBadge {
                                            Text(sourceID.hasPrefix("ausnut:") ? "Australian food data" : "Verified restaurant")
                                                .font(.caption)
                                                .foregroundStyle(.secondary)
                                        }
                                    }
                                    .frame(maxWidth: .infinity, minHeight: 44, alignment: .leading)
                                    .padding(.horizontal, 12)
                                    .contentShape(Rectangle())
                                }
                                .buttonStyle(.plain)
                                .accessibilityIdentifier("searchFood.concept.\(sourceID)")
                                Divider()
                            }
                            if !showingAllConceptChoices && currentCandidateSourceIDs.count > 8 {
                                Button("Show all sourced choices") {
                                    showingAllConceptChoices = true
                                }
                                .frame(minHeight: 44)
                                .padding(.horizontal, 12)
                            }
                        }
                        if conceptRoute.allowsExplicitEstimate {
                            Button("Not sure") {
                                conceptChoiceState.notSure(about: conceptRoute)
                            }
                            .frame(minHeight: 44)
                            .padding(.horizontal, 12)
                            .accessibilityIdentifier("searchFood.concept.notSure")
                        }
                        if case .weakAlternatives(let query, _) = conceptRoute {
                            Button("Estimate instead") {
                                (onEstimate ?? onSubmit)(query)
                            }
                            .frame(minHeight: 44)
                            .padding(.horizontal, 12)
                        }
                    }
                }
            }
        }
        .frame(height: suggestionAreaHeight)
        .background(Color(.secondarySystemBackground), in: RoundedRectangle(cornerRadius: 12))
    }

    var body: some View {
        VStack(spacing: 12) {
            ZStack(alignment: .topLeading) {
                if foodDescription.isEmpty {
                    Text(placeholders[placeholderIndex])
                        .foregroundStyle(.tertiary)
                        .font(.body)
                        .padding(.horizontal, 6)
                        .padding(.vertical, 10)
                        .transition(.asymmetric(
                            insertion: .move(edge: .bottom).combined(with: .opacity),
                            removal: .move(edge: .top).combined(with: .opacity)
                        ))
                        .id(placeholderIndex)
                        .allowsHitTesting(false)
                        .accessibilityHidden(true)
                }

                TextField("", text: $foodDescription, axis: .vertical)
                    .font(.body)
                    .lineLimit(2...5)
                    .textFieldStyle(.plain)
                    .autocorrectionDisabled()
                    .focused($isFocused)
                    .accessibilityLabel("Search food")
                    .accessibilityHint("Search verified foods or describe a meal to analyse")
                    .accessibilityIdentifier("searchFood.query")
                    .padding(.horizontal, 6)
                    .padding(.vertical, 10)
            }
            .padding(12)
            .background(
                RoundedRectangle(cornerRadius: 12)
                    .fill(Color(.quaternarySystemFill))
            )

            if conceptChoiceState != .discovery {
                conceptChoices
            } else if onSelectRestaurant != nil {
                ScrollView {
                    VStack(spacing: 0) {
                        if suggestions.isEmpty {
                            Text("Search verified items or describe a meal")
                                .font(.subheadline)
                                .foregroundStyle(.secondary)
                                .frame(maxWidth: .infinity, alignment: .leading)
                                .padding(12)
                        }
                        ForEach(suggestions) { result in
                            switch result {
                            case .restaurant(let suggestion) where suggestion.kind == .brand:
                                HStack(spacing: 10) {
                                    Image(systemName: "storefront")
                                        .foregroundStyle(.secondary)
                                    VStack(alignment: .leading, spacing: 2) {
                                        Text(suggestion.title).font(.subheadline.weight(.semibold))
                                        Text(suggestion.subtitle).font(.caption).foregroundStyle(.secondary)
                                    }
                                    Spacer(minLength: 0)
                                }
                                .padding(.horizontal, 12)
                                .padding(.vertical, 10)
                                .accessibilityElement(children: .combine)
                                .accessibilityIdentifier("searchFood.brand.\(suggestion.restaurantID)")
                            case .restaurant(let suggestion):
                                if let selection = suggestion.restaurantSelection {
                                Button {
                                    onSelectRestaurant?(selection, suggestion.title)
                                } label: {
                                    HStack(spacing: 10) {
                                        Image(systemName: "checkmark.seal.fill")
                                            .foregroundStyle(AppColors.calorie)
                                        VStack(alignment: .leading, spacing: 2) {
                                            Text(suggestion.title)
                                                .font(.subheadline.weight(.medium))
                                                .foregroundStyle(.primary)
                                            Text(suggestion.subtitle)
                                                .font(.caption)
                                                .foregroundStyle(.secondary)
                                        }
                                        Spacer(minLength: 0)
                                    }
                                    .padding(.horizontal, 12)
                                    .padding(.vertical, 10)
                                    .contentShape(Rectangle())
                                }
                                .buttonStyle(.plain)
                                .accessibilityIdentifier("searchFood.\(suggestion.id)")
                                }
                            case .ausnut(let suggestion):
                                if let onSelectAUSNUT {
                                    Button {
                                        onSelectAUSNUT(suggestion.selection)
                                    } label: {
                                        HStack(spacing: 10) {
                                            Image(systemName: "leaf.circle")
                                                .foregroundStyle(.secondary)
                                            VStack(alignment: .leading, spacing: 2) {
                                                Text(discoveryLabels[suggestion.id] ?? suggestion.title)
                                                    .font(.subheadline.weight(.medium))
                                                    .foregroundStyle(.primary)
                                                    .lineLimit(dynamicTypeSize.isAccessibilitySize ? 3 : 2)
                                                    .frame(maxWidth: .infinity, alignment: .leading)
                                                Text("AUSNUT 2023 · Australian food data")
                                                    .font(.caption)
                                                    .foregroundStyle(.secondary)
                                            }
                                            Spacer(minLength: 0)
                                        }
                                        .padding(.horizontal, 12)
                                        .padding(.vertical, 10)
                                        .contentShape(Rectangle())
                                    }
                                    .buttonStyle(.plain)
                                    .accessibilityIdentifier("searchFood.\(suggestion.id)")
                                }
                            }
                            if result.id != suggestions.last?.id {
                                Divider().padding(.leading, 44)
                            }
                        }
                        if case .sourced(_, let refinements)? = conceptRoute,
                           !refinements.isEmpty {
                            Button("See other sourced varieties") {
                                if let conceptRoute { beginConceptChoices(conceptRoute) }
                            }
                            .frame(minHeight: 44)
                            .padding(.horizontal, 12)
                        }
                    }
                }
                // An anchored popover repositions when its intrinsic height changes.
                // Reserve the same scroll area as results appear and disappear.
                .frame(height: suggestionAreaHeight)
                .background(Color(.secondarySystemBackground), in: RoundedRectangle(cornerRadius: 12))
            }

            if conceptChoiceState.explicitEstimateQuery != nil {
                EmptyView()
            } else if isBrandOnlyQuery && conceptChoiceState == .discovery {
                Text("Choose a verified item above")
                    .font(.subheadline)
                    .foregroundStyle(.secondary)
                    .frame(maxWidth: .infinity)
                    .frame(height: 50)
            } else if conceptChoiceState == .discovery {
                if suggestions.isEmpty {
                    analyseButton.buttonStyle(.borderedProminent)
                } else {
                    analyseButton.buttonStyle(.bordered)
                }
            } else if case .sourced? = conceptRoute {
                analyseButton.buttonStyle(.borderedProminent)
            }

            Button("Cancel") {
                onCancel()
            }
            .foregroundStyle(.secondary)
        }
        .padding(20)
        .frame(width: searchPanelWidth, height: onSelectRestaurant == nil ? nil : searchPanelHeight,
               alignment: .top)
        .onAppear { isFocused = true }
        .onChange(of: meaningfulQuery, initial: true) { _, query in
            updateSuggestions(for: query)
        }
        .onReceive(timer) { _ in
            guard foodDescription.isEmpty, !reduceMotion else { return }
            withAnimation(.easeInOut(duration: 0.3)) {
                placeholderIndex = (placeholderIndex + 1) % placeholders.count
            }
        }
    }
}
