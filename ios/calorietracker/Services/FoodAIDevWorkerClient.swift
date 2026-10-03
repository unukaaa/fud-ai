#if DEBUG && targetEnvironment(simulator)
import Foundation

/// Simulator-only transport. Credentials come from the launch environment and
/// are never stored by the app. This file is absent from Release compilation.
enum FoodAIDevWorkerClient {
    static let origin = URL(string: "https://food-ai-dev-api-20261002.unukabrandon.workers.dev")!

    enum Failure: Error {
        case missingRuntimeCredentials
        case disallowedDestination
        case invalidResponse
    }

    struct Result {
        let status: Int
        let body: Data
    }

    private static let noRedirects = NoRedirects()
    private static let session: URLSession = {
        let configuration = URLSessionConfiguration.ephemeral
        configuration.httpShouldSetCookies = false
        configuration.urlCache = nil
        configuration.requestCachePolicy = .reloadIgnoringLocalCacheData
        return URLSession(configuration: configuration)
    }()

    static func request(
        path: String,
        method: String = "POST",
        body: Data? = nil,
        environment: [String: String] = ProcessInfo.processInfo.environment
    ) throws -> URLRequest {
        guard let clientID = environment["CF_ACCESS_CLIENT_ID"], !clientID.isEmpty,
              let clientSecret = environment["CF_ACCESS_CLIENT_SECRET"], !clientSecret.isEmpty else {
            throw Failure.missingRuntimeCredentials
        }
        guard path == "/" || path == "/api/grounded-estimate/v1/proposal"
                || path == "/api/grounded-estimate/v1/fallback-batch",
              let url = URL(string: path, relativeTo: origin)?.absoluteURL,
              isAllowed(url) else { throw Failure.disallowedDestination }

        var result = URLRequest(url: url)
        result.httpMethod = method
        result.setValue(clientID, forHTTPHeaderField: "CF-Access-Client-Id")
        result.setValue(clientSecret, forHTTPHeaderField: "CF-Access-Client-Secret")
        result.setValue("application/json", forHTTPHeaderField: "Accept")
        if let body {
            result.setValue("application/json", forHTTPHeaderField: "Content-Type")
            result.httpBody = body
        }
        return result
    }

    static func send(_ request: URLRequest) async throws -> Result {
        guard let url = request.url, isAllowed(url),
              ["/", "/api/grounded-estimate/v1/proposal", "/api/grounded-estimate/v1/fallback-batch"].contains(url.path)
        else { throw Failure.disallowedDestination }
        let (data, response) = try await session.data(for: request, delegate: noRedirects)
        guard let http = response as? HTTPURLResponse else { throw Failure.invalidResponse }
        return Result(status: http.statusCode, body: data)
    }

    private static func isAllowed(_ url: URL) -> Bool {
        url.scheme == "https" && url.host == origin.host && url.port == nil
            && url.user == nil && url.password == nil && url.query == nil && url.fragment == nil
    }
}

/// An opt-in, status-only runtime proof. No request body, response body,
/// credential, or user text is written to a log or file.
@MainActor
enum FoodAIDevWorkerProbe {
    private static var started = false

    static func runIfRequested() async {
        guard CommandLine.arguments.contains("--food-ai-dev-auth-probe"), !started else { return }
        started = true
        do {
            let diagnostic = try await FoodAIDevWorkerClient.send(
                FoodAIDevWorkerClient.request(path: "/", method: "GET"))
            guard diagnostic.status == 404 else {
                print("FOOD_AI_DEV_AUTH_PROBE diagnostic=\(diagnostic.status) proposal=not_sent")
                return
            }
            let body = try JSONSerialization.data(withJSONObject: [
                "version": "checked-quantity-binding-v1",
                "description": "banana",
                "quantities": []
            ])
            let response = try await FoodAIDevWorkerClient.send(
                FoodAIDevWorkerClient.request(path: "/api/grounded-estimate/v1/proposal", body: body))
            let json = (try? JSONSerialization.jsonObject(with: response.body)) as? [String: Any]
            let proposal = json?["proposal"] as? [String: Any]
            let valid = json?["version"] as? String == "grounded-estimate-proposal-v1"
                && proposal?["components"] is [[String: Any]]
                && proposal?["question"] != nil
                && proposal?["assumptions"] is [String]
            print("FOOD_AI_DEV_AUTH_PROBE diagnostic=404 proposal=\(response.status) schema=\(valid)")
        } catch {
            print("FOOD_AI_DEV_AUTH_PROBE failed_safely")
        }
    }
}

private final class NoRedirects: NSObject, URLSessionTaskDelegate {
    func urlSession(_ session: URLSession, task: URLSessionTask,
                    willPerformHTTPRedirection response: HTTPURLResponse,
                    newRequest request: URLRequest,
                    completionHandler: @escaping (URLRequest?) -> Void) {
        completionHandler(nil)
    }
}
#endif
