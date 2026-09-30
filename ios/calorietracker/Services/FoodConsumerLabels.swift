import Foundation

/// English presentation only. Never use these labels to resolve, save, or identify food.
enum FoodConsumerLabels {
    static func food(_ authoritativeName: String) -> String {
        let parts = authoritativeName.split(separator: ",", omittingEmptySubsequences: false)
            .map { $0.trimmingCharacters(in: .whitespacesAndNewlines) }
        guard let family = parts.first else { return authoritativeName }

        if family.caseInsensitiveCompare("Milk") == .orderedSame,
           parts.count >= 4, parts[1] == "cow", parts[2] == "fluid",
           let milk = milkLabel(fatDescription: parts[3], modifiers: Array(parts.dropFirst(4))) {
            return milk
        }
        if family.caseInsensitiveCompare("Chocolate") == .orderedSame,
           let chocolate = chocolateLabel(Array(parts.dropFirst())) {
            return chocolate
        }
        if family.caseInsensitiveCompare("Banana") == .orderedSame {
            if parts.count == 4, parts[2] == "peeled", parts[3] == "raw" {
                if parts[1] == "cavendish" { return "Cavendish banana" }
                if parts[1] == "lady finger or sugar" { return "Lady Finger banana" }
            }
            if parts.count == 2, ["cooked", "frozen"].contains(parts[1]) {
                return "\(parts[1].capitalized) banana"
            }
        }
        if parts.count == 3, parts[1] == "raw", parts[2] == "not further defined" {
            return "Raw \(family.lowercased())"
        }
        return authoritativeName
    }

    /// Resolve collisions within the complete candidate set, before any visible-row limit.
    /// Authoritative names are the first fallback; source IDs are a last-resort tie breaker.
    static func choices(_ sources: [(id: String, name: String)]) -> [String: String] {
        var labels = Dictionary(uniqueKeysWithValues: sources.map { ($0.id, food($0.name)) })
        let simplifiedCounts = counts(labels.values)
        for source in sources where simplifiedCounts[fold(labels[source.id] ?? ""), default: 0] > 1 {
            labels[source.id] = source.name
        }
        let remainingCounts = counts(labels.values)
        for source in sources where remainingCounts[fold(labels[source.id] ?? ""), default: 0] > 1 {
            labels[source.id] = "\(source.name) · source \(source.id)"
        }
        return labels
    }

    static func portion(_ sourceTitle: String) -> String {
        var sections = sourceTitle.components(separatedBy: " · ")
        let sizes: Set<String> = ["regular", "medium", "large", "small", "mini"]
        for index in sections.indices {
            let words = sections[index].split(separator: " ").map(String.init)
            guard words.count == 2 else { continue }
            let qualifier = words[1].lowercased()
            let isPlural = qualifier.hasSuffix("s") && sizes.contains(String(qualifier.dropLast()))
            guard sizes.contains(qualifier) || isPlural else { continue }
            let size = isPlural ? String(words[1].dropLast()) : words[1]
            let noun = isPlural && !words[0].hasSuffix("s") ? "\(words[0])s" : words[0]
            sections[index] = "\(size.capitalized) \(noun)"
            return sections.joined(separator: " · ")
        }
        return sourceTitle
    }

    private static func milkLabel(fatDescription: String, modifiers: [String]) -> String? {
        let type: String
        switch fatDescription {
        case "rich or creamy (~4.5% fat)": type = "Extra creamy milk"
        case "regular fat (~3.5%)": type = "Full cream milk"
        case "reduced fat (~1%)": type = "Light milk"
        case "skim (~0.1% fat)": type = "Skim milk"
        case "lactose free":
            guard modifiers == ["not further defined"] else { return nil }
            return "Lactose-free milk"
        case "unflavoured":
            guard modifiers == ["not further defined"] else { return nil }
            return "Unflavoured milk"
        default: return nil
        }
        guard let modifier = modifiers.first else { return type }
        guard modifiers.count == 1 else { return nil }
        switch modifier {
        case "lactose free": return "Lactose-free \(type.lowercased())"
        case "organic": return "Organic \(type.lowercased())"
        case "raw": return "Raw \(type.lowercased())"
        case "increased protein": return "High-protein \(type.lowercased())"
        case "added phytosterols": return "\(type) · added phytosterols"
        case "added vitamins & minerals": return "\(type) · added vitamins & minerals"
        default: return nil
        }
    }

    private static func chocolateLabel(_ details: [String]) -> String? {
        guard let kind = details.first else { return nil }
        let base: String
        switch kind {
        case "milk": base = "Milk chocolate"
        case "dark": base = "Dark chocolate"
        case "white": base = "White chocolate"
        case "milk & white": base = "Milk & white chocolate"
        default: return nil
        }
        if details.count == 1 { return base }
        if details.count == 3, details[1] == "high cocoa solids" {
            if details[2] == ">60% cocoa solids" { return "Dark chocolate · over 60% cocoa" }
            if details[2] == "<60% cocoa solids" { return "Dark chocolate · under 60% cocoa" }
        }
        guard details.count == 2 else { return nil }
        let qualifier = details[1]
        if qualifier == "no added sugar" { return "\(base) · no added sugar" }
        if qualifier.hasPrefix("with ") || qualifier.hasSuffix(" filled") {
            return "\(base) · \(qualifier)"
        }
        return nil
    }

    private static func fold(_ label: String) -> String {
        label.folding(options: [.caseInsensitive, .diacriticInsensitive], locale: Locale(identifier: "en_AU"))
    }

    private static func counts<S: Sequence>(_ labels: S) -> [String: Int] where S.Element == String {
        Dictionary(labels.map { (fold($0), 1) }, uniquingKeysWith: +)
    }
}
