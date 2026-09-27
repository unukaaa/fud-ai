import SwiftUI
import Combine

struct TextFoodInputView: View {
    @State private var foodDescription = ""
    @State private var placeholderIndex = 0
    @State private var restaurantSearchIndex = RestaurantFoodSearchIndex.bundled()
    @State private var ausnutSearchIndex = AUSNUTFoodSearchIndex.bundled()
    @FocusState private var isFocused: Bool

    var onCancel: () -> Void
    var onSubmit: (String) -> Void
    var onSelectRestaurant: ((RestaurantFoodSelection, String) -> Void)? = nil
    var onSelectAUSNUT: ((AUSNUTFoodSelection) -> Void)? = nil

    var placeholders = [
        "2 eggs, toast with butter and a coffee",
        "Chipotle burrito bowl with chicken and rice",
        "Domino's pepperoni pizza, 2 slices",
        "Greek yogurt with granola and blueberries",
    ]

    private let timer = Timer.publish(every: 2, on: .main, in: .common).autoconnect()

    private var suggestions: [UnifiedFoodSuggestion] {
        guard onSelectRestaurant != nil else { return [] }
        return UnifiedFoodSearchIndex(restaurants: restaurantSearchIndex, ausnut: ausnutSearchIndex)
            .search(foodDescription, limit: 5)
    }

    private var isBrandOnlyQuery: Bool {
        if case .restaurant(let first)? = suggestions.first { return first.kind == .brand }
        return false
    }

    private var analyseButton: some View {
        Button {
            onSubmit(foodDescription)
        } label: {
            Text(foodDescription.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty
                 ? "Analyze" : "Analyse \"\(foodDescription.trimmingCharacters(in: .whitespacesAndNewlines))\"")
                .font(suggestions.isEmpty ? .headline : .subheadline.weight(.medium))
                .lineLimit(1)
                .truncationMode(.tail)
                .frame(maxWidth: .infinity)
        }
        .tint(AppColors.calorie)
        .controlSize(.large)
        .frame(height: 50)
        .disabled(foodDescription.trimmingCharacters(in: .whitespaces).isEmpty)
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
                }

                TextField("", text: $foodDescription, axis: .vertical)
                    .font(.body)
                    .lineLimit(2...5)
                    .textFieldStyle(.plain)
                    .autocorrectionDisabled()
                    .focused($isFocused)
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
                                Button {
                                    onSelectAUSNUT?(suggestion.selection)
                                } label: {
                                    HStack(spacing: 10) {
                                        Image(systemName: "leaf.circle")
                                            .foregroundStyle(.secondary)
                                        VStack(alignment: .leading, spacing: 2) {
                                            Text(suggestion.title)
                                                .font(.subheadline.weight(.medium))
                                                .foregroundStyle(.primary)
                                                .lineLimit(2)
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
                            if result.id != suggestions.last?.id {
                                Divider().padding(.leading, 44)
                            }
                        }
                    }
                }
                // An anchored popover repositions when its intrinsic height changes.
                // Reserve the same scroll area as results appear and disappear.
                .frame(height: 190)
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
        .frame(width: 320, height: onSelectRestaurant == nil ? nil : 410, alignment: .top)
        .onAppear { isFocused = true }
        .onReceive(timer) { _ in
            guard foodDescription.isEmpty else { return }
            withAnimation(.easeInOut(duration: 0.3)) {
                placeholderIndex = (placeholderIndex + 1) % placeholders.count
            }
        }
    }
}
