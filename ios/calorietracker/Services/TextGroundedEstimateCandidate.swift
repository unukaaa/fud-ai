import Foundation

/// Local TEXT-only orchestration seam. The app has not supplied a production
/// provider transport or independent quantity-extraction adapter yet.
enum TextGroundedEstimateCandidate {
    enum Outcome {
        case selectSource(String)
        case chooseSource([String])
        case unresolvedVariant(String, [String])
        case clarification(FoodSemanticAssessment)
        case blocked(FoodSemanticAssessment)
        case complete(AINutritionFallbackMeal)
        case incomplete(AINutritionFallbackMeal)
        case providerUnavailable(AINutritionFallbackMeal?)
    }

    typealias ProposalProvider = (FoodQuantityInterpretationContract) async throws -> FoodMealProposal
    typealias NutritionProvider = ([AIComponentNutritionRequest]) async throws -> [AIComponentNutritionResponse]

    /// `permissions` are an independent reviewed blocker classification, never
    /// supplied by the provider. No permission means no AI nutrition fallback.
    static func run(
        route: FoodConceptSearchRoute,
        context: FoodSemanticContext,
        explicitEstimate: Bool = false,
        permissions: [String: AINutritionFallbackReason] = [:],
        propose: ProposalProvider,
        estimateNutrition: NutritionProvider
    ) async -> Outcome {
        switch route {
        case .sourced(let id, _): return .selectSource(id)
        case .clarification(let ids), .weakAlternatives(_, let ids): return .chooseSource(ids)
        case .unknownVariant(let query, let ids):
            guard explicitEstimate else { return .unresolvedVariant(query, ids) }
        case .analyse: break
        }

        let proposal: FoodMealProposal
        do {
            proposal = try await propose(FoodQuantityInterpretationContract(context: context))
        } catch {
            return .providerUnavailable(nil)
        }
        let assessment = FoodAmountSemanticFirewall.assess(proposal, context: context)
        guard assessment.accepted != nil else {
            return assessment.outcome == .clarificationRequired ? .clarification(assessment) : .blocked(assessment)
        }

        let first = AINutritionFallbackPrototype.evaluate(proposal, context: context, permissions: permissions)
        if first.loggable { return .complete(first) }
        guard !first.requests.isEmpty else { return .incomplete(first) }

        // Collect eligible component requests first. One transport call can
        // return independently bound responses for all of them.
        let responses: [AIComponentNutritionResponse]
        do { responses = try await estimateNutrition(first.requests) }
        catch { return .providerUnavailable(first) }

        let expected = Set(first.requests.map(\.requestID))
        let received = responses.map { $0.proposal.requestID }
        guard received.count == Set(received).count, Set(received) == expected else {
            return .incomplete(first)
        }
        let byID = Dictionary(uniqueKeysWithValues: responses.map { ($0.proposal.requestID, $0) })
        let final = AINutritionFallbackPrototype.evaluate(proposal, context: context, permissions: permissions, fallback: {
            byID[$0.requestID]
        })
        return final.loggable ? .complete(final) : .incomplete(final)
    }
}
