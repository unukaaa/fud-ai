import SwiftUI
import Combine

struct TextFoodInputView: View {
    @State private var foodDescription = ""
    @State private var placeholderIndex = 0
    @State private var suggestions: [UnifiedFoodSuggestion] = []
    @State private var restaurantSearchIndex = RestaurantFoodSearchIndex.bundled()
    @State private var ausnutSearchIndex = AUSNUTFoodSearchIndex.bundled()
    @FocusState private var isFocused: Bool
    @Environment(\.accessibilityReduceMotion) private var reduceMotion
    @Environment(\.dynamicTypeSize) private var dynamicTypeSize

    var onCancel: () -> Void
    var onSubmit: (String) -> Void
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
        guard onSelectRestaurant != nil, !query.isEmpty else {
            suggestions = []
            return
        }
        suggestions = UnifiedFoodSearchIndex(
            restaurants: restaurantSearchIndex,
            ausnut: onSelectAUSNUT == nil ? nil : ausnutSearchIndex
        ).search(query, limit: 5)
    }

    private var isBrandOnlyQuery: Bool {
        if case .restaurant(let first)? = suggestions.first { return first.kind == .brand }
        return false
    }

    private var analyseButton: some View {
        Button {
            onSubmit(meaningfulQuery)
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

            if onSelectRestaurant != nil {
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
                                                Text(suggestion.title)
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
                    }
                }
                // An anchored popover repositions when its intrinsic height changes.
                // Reserve the same scroll area as results appear and disappear.
                .frame(height: suggestionAreaHeight)
                .background(Color(.secondarySystemBackground), in: RoundedRectangle(cornerRadius: 12))
            }

            if isBrandOnlyQuery {
                Text("Choose a verified item above")
                    .font(.subheadline)
                    .foregroundStyle(.secondary)
                    .frame(maxWidth: .infinity)
                    .frame(height: 50)
            } else {
                if suggestions.isEmpty {
                    analyseButton.buttonStyle(.borderedProminent)
                } else {
                    analyseButton.buttonStyle(.bordered)
                }
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
