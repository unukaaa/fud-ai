#if DEBUG && targetEnvironment(simulator)
import Foundation
import Testing
@testable import calorietracker

struct FoodAIDevWorkerClientTests {
    private let fixture = ["CF_ACCESS_CLIENT_ID": "fixture-id", "CF_ACCESS_CLIENT_SECRET": "fixture-secret"]

    @Test func headersAreRestrictedToExactWorker() throws {
        let request = try FoodAIDevWorkerClient.request(
            path: "/api/grounded-estimate/v1/proposal", body: Data("{}".utf8), environment: fixture)
        #expect(request.url?.absoluteString == "https://food-ai-dev-api-20261002.unukabrandon.workers.dev/api/grounded-estimate/v1/proposal")
        #expect(request.value(forHTTPHeaderField: "CF-Access-Client-Id") == "fixture-id")
        #expect(request.value(forHTTPHeaderField: "CF-Access-Client-Secret") == "fixture-secret")
        #expect(throws: FoodAIDevWorkerClient.Failure.self) {
            try FoodAIDevWorkerClient.request(path: "//other.example/api/grounded-estimate/v1/proposal", environment: fixture)
        }
        #expect(throws: FoodAIDevWorkerClient.Failure.self) {
            try FoodAIDevWorkerClient.request(path: "/unrelated", environment: fixture)
        }
    }

    @Test func absentRuntimeCredentialsFailClosed() {
        #expect(throws: FoodAIDevWorkerClient.Failure.self) {
            try FoodAIDevWorkerClient.request(path: "/", method: "GET", environment: [:])
        }
        #expect(throws: FoodAIDevWorkerClient.Failure.self) {
            try FoodAIDevWorkerClient.request(path: "/", method: "GET", environment: ["CF_ACCESS_CLIENT_ID": "fixture-id"])
        }
    }

    @Test func redirectedRequestCannotBeResentThroughClient() async throws {
        let request = try FoodAIDevWorkerClient.request(path: "/", method: "GET", environment: fixture)
        var redirected = request
        redirected.url = URL(string: "https://other.example/")
        do {
            _ = try await FoodAIDevWorkerClient.send(redirected)
            Issue.record("Cross-origin request was sent")
        } catch FoodAIDevWorkerClient.Failure.disallowedDestination {
            // No network request was made.
        }
    }
}
#endif
