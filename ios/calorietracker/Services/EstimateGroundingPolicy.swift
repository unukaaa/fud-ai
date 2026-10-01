import Foundation

/// An evidence envelope, not a statistical confidence interval or a synthetic food.
/// Each nutrient extremum can come from a different source record. No midpoint is
/// asserted and no candidate is declared to be the food the user actually ate.
struct GroundedNutritionEnvelope: Equatable, Sendable {
    let lower: NutritionFacts
    let upper: NutritionFacts

    static func enclosing(_ values: [NutritionFacts]) -> Self? {
        guard !values.isEmpty, values.allSatisfy({ completeAndValid($0) }) else { return nil }
        func facts(_ select: ([Double]) -> Double) -> NutritionFacts {
            NutritionFacts(calories: select(values.map { $0.calories! }), kilojoules: nil,
                           proteinGrams: select(values.map { $0.proteinGrams! }),
                           carbohydrateGrams: select(values.map { $0.carbohydrateGrams! }),
                           fatGrams: select(values.map { $0.fatGrams! }))
        }
        return Self(lower: facts { $0.min()! }, upper: facts { $0.max()! })
    }

    static func adding(_ values: [Self]) -> Self? {
        guard !values.isEmpty,
              let lower = NutritionFacts.adding(values.map(\.lower)),
              let upper = NutritionFacts.adding(values.map(\.upper)),
              completeAndValid(lower), completeAndValid(upper) else { return nil }
        return Self(lower: lower, upper: upper)
    }

    private static func completeAndValid(_ value: NutritionFacts) -> Bool {
        let fields = [value.calories, value.proteinGrams, value.carbohydrateGrams, value.fatGrams]
        return fields.allSatisfy { $0.map { $0.isFinite && $0 >= 0 } ?? false }
    }
}

struct GroundedEstimateBasis: Sendable {
    enum Method: Equatable, Sendable { case scopedSourceEnvelope }
    let scopedQuery: String
    let method: Method
    /// Resolutions at this component's amount; not duplicated database records.
    let candidates: [GroundedSourceResolution]
    let envelope: GroundedNutritionEnvelope
    let assumptions: [String]
    let uncertainty: [String]

    var candidateSourceIDs: [GroundedSourceID] { candidates.map(\.sourceID) }
}

/// An explicitly interpreted scope, e.g. "banana raw", must be supplied by the
/// caller. Bare fruit is not automatically interpreted as raw by this policy.
enum EstimateGroundingPolicy {
    static let version = "scoped-source-envelope-v2.1"

    static func ausnutBasis(scopedQuery: String, amount: GroundedAmount,
                            index: AUSNUTFoodSearchIndex? = .bundled(),
                            identity: (String) -> AUSNUTFoodIdentity? = { AustralianNutritionService.identity(forID: $0) },
                            resolver: GroundedEstimateEngine.Resolver = { ExistingFoodGrounder.resolve($0, amount: $1) })
        -> GroundedEstimateBasis? {
        guard amount.isValid, amount.unit == .grams, let index else { return nil }
        let assessment = index.assessIdentity(scopedQuery)
        // A fitting NFD record supplies its own evidence, not a blend with variants.
        let ids = assessment.defaultSourceID.map { [$0] } ?? assessment.candidateSourceIDs
        guard !ids.isEmpty else { return nil }
        var records: [AUSNUTFoodIdentity] = []
        var sources: [GroundedSourceResolution] = []
        for id in ids.sorted() {
            guard id.hasPrefix("ausnut:"),
                  let record = identity(String(id.dropFirst(7))),
                  id == "ausnut:\(record.id)",
                  let source = resolver(.ausnut(record.id), amount),
                  source.sourceID == .ausnut(record.id), source.sourceType == .ausnut,
                  let version = source.sourceVersion, !version.isEmpty else { return nil }
            records.append(record)
            sources.append(source)
        }
        guard Set(sources.map(\.sourceID)).count == sources.count,
              Set(sources.map(\.sourceVersion)).count == 1,
              Set(records.map { family($0.name) }).count == 1,
              Set(records.map { preparation($0.name) }).count == 1,
              EstimateRetrievalBridge.compatibleSourceEvidence(records.map(\.name)),
              let envelope = GroundedNutritionEnvelope.enclosing(sources.map(\.nutrition)) else { return nil }
        return GroundedEstimateBasis(
            scopedQuery: scopedQuery, method: .scopedSourceEnvelope, candidates: sources,
            envelope: envelope,
            assumptions: ["Interpreted component scope: \(scopedQuery)",
                          "Amount: \(amount.value) g (\(amount.provenance))"],
            uncertainty: ["Exact variant is not asserted.",
                          "Bounds cover retrieved scoped records only; not every possible food or portion.",
                          "No averaging, probability or representative point value is implied."]
        )
    }

    private static func tokens(_ text: String) -> [String] {
        text.lowercased().replacingOccurrences(of: "[^a-z0-9]+", with: " ", options: .regularExpression)
            .split(separator: " ").map(String.init)
    }

    private static func family(_ name: String) -> String {
        tokens(String(name.split(separator: ",", maxSplits: 1).first ?? "")).joined(separator: " ")
    }

    private static func preparation(_ name: String) -> Set<String> {
        Set(tokens(name)).intersection(["raw", "uncooked", "cooked", "boiled", "baked", "fried",
            "grilled", "roasted", "steamed", "poached", "stewed", "frozen", "dried", "canned"])
    }
}

struct EstimateGroundedComponent: Sendable {
    let exactInput: GroundedComponentInput
    let scopedEstimateQuery: String?
}

struct EstimateGroundedComponentResult: Sendable {
    let exactResult: GroundedComponentResult
    let estimateBasis: GroundedEstimateBasis?
    var envelope: GroundedNutritionEnvelope? {
        estimateBasis?.envelope ?? exactResult.nutrition.flatMap {
            GroundedNutritionEnvelope.enclosing([$0])
        }
    }
}

struct EstimateGroundedMealResult: Sendable {
    let components: [EstimateGroundedComponentResult]
    /// Partial envelope when complete is false. Never expose a partial sum as a meal.
    let availableEnvelope: GroundedNutritionEnvelope?
    let complete: Bool
    let evidence: GroundedMealResult.Evidence
    var exactGroundedCount: Int { components.filter { $0.exactResult.source != nil }.count }
    var estimateGroundedCount: Int { components.filter { $0.estimateBasis != nil }.count }
    var unresolvedCount: Int { components.filter { $0.envelope == nil }.count }
}

enum EstimateGroundedMealEngine {
    typealias BasisResolver = (String, GroundedAmount) -> GroundedEstimateBasis?

    static func evaluate(_ input: [EstimateGroundedComponent],
                         resolver: GroundedEstimateEngine.Resolver = { ExistingFoodGrounder.resolve($0, amount: $1) },
                         basisResolver: BasisResolver = {
                             EstimateGroundingPolicy.ausnutBasis(scopedQuery: $0, amount: $1)
                                 ?? EstimateRetrievalBridge.basis(scopedQuery: $0, amount: $1)
                         })
        -> EstimateGroundedMealResult {
        let components = input.map { component in
            let exact = GroundedEstimateEngine.evaluate(
                GroundedMealInput(description: component.exactInput.description, inputKind: .text,
                                  components: [component.exactInput]), resolver: resolver
            ).components[0]
            var basis: GroundedEstimateBasis?
            // Never replace an explicit but invalid source ID with a convenient estimate.
            if exact.evidence == .unresolved, component.exactInput.sourceID == nil,
               let query = component.scopedEstimateQuery, let amount = component.exactInput.amount {
                basis = basisResolver(query, amount)
            }
            return EstimateGroundedComponentResult(exactResult: exact, estimateBasis: basis)
        }
        let aggregate = GroundedNutritionEnvelope.adding(components.compactMap(\.envelope))
        let complete = aggregate != nil && !components.isEmpty && components.allSatisfy { $0.envelope != nil }
        let evidence: GroundedMealResult.Evidence
        if !complete || components.contains(where: { $0.exactResult.evidence == .estimated }) {
            evidence = .estimate
        } else if components.contains(where: { $0.estimateBasis != nil || $0.exactResult.evidence == .sourcedAmountEstimated }) {
            evidence = .sourcedEstimate
        } else {
            evidence = .sourced
        }
        return EstimateGroundedMealResult(
            components: components,
            availableEnvelope: aggregate,
            complete: complete, evidence: evidence
        )
    }
}
