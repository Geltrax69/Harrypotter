import Foundation

/// Abstraction for asking the backend a question. Lets tests and UI-testing
/// mode substitute a deterministic client.
public protocol AnswerRequesting: Sendable {
    func requestAnswer(_ request: AnswerRequest) async throws -> AnswerResponse
}

/// User-facing, understandable network errors. Recovery UI maps these to
/// actionable copy.
public enum AnswerClientError: Error, Equatable, Sendable {
    case notConfigured          // no bearer credential available
    case invalidRequest         // failed local structural validation
    case unauthorized           // 401 / 403
    case rateLimited            // 429
    case validationRejected(String)  // 400 from server
    case serverUnavailable      // 5xx / 502 provider failure
    case timedOut               // request exceeded timeout
    case offline                // no connectivity
    case malformedResponse      // could not decode a success body
    case unexpectedStatus(Int)

    /// Short, human-understandable message for recovery UI.
    public var userMessage: String {
        switch self {
        case .notConfigured:
            return "This device isn't set up to reach Living Page yet."
        case .invalidRequest:
            return "That question can't be sent as written."
        case .unauthorized:
            return "This device isn't allowed to ask right now."
        case .rateLimited:
            return "Too many questions just now. Give it a moment."
        case .validationRejected:
            return "The question wasn't accepted. Try rewording it."
        case .serverUnavailable:
            return "Living Page couldn't answer. Try again shortly."
        case .timedOut:
            return "The answer took too long to arrive."
        case .offline:
            return "You appear to be offline."
        case .malformedResponse:
            return "The answer came back in a form we couldn't read."
        case .unexpectedStatus:
            return "Something unexpected happened. Try again."
        }
    }

    /// Whether retrying the same request is sensible.
    public var isRetryable: Bool {
        switch self {
        case .serverUnavailable, .timedOut, .offline, .rateLimited, .unexpectedStatus:
            return true
        case .notConfigured, .invalidRequest, .unauthorized, .validationRejected, .malformedResponse:
            return false
        }
    }
}

/// Production HTTP client for POST /v1/answers.
public struct HTTPAnswerClient: AnswerRequesting {
    private let baseURL: URL
    private let session: URLSession
    private let credentials: DeviceCredentialStoring
    private let timeout: TimeInterval

    public init(
        baseURL: URL,
        credentials: DeviceCredentialStoring,
        session: URLSession = .shared,
        timeout: TimeInterval = 30
    ) {
        self.baseURL = baseURL
        self.credentials = credentials
        self.session = session
        self.timeout = timeout
    }

    public func requestAnswer(_ request: AnswerRequest) async throws -> AnswerResponse {
        guard request.isStructurallyValid else { throw AnswerClientError.invalidRequest }
        guard let token = credentials.bearerToken(), !token.isEmpty else {
            throw AnswerClientError.notConfigured
        }

        let url = baseURL.appendingPathComponent("v1/answers")
        var urlRequest = URLRequest(url: url, timeoutInterval: timeout)
        urlRequest.httpMethod = "POST"
        urlRequest.setValue("application/json", forHTTPHeaderField: "Content-Type")
        urlRequest.setValue("application/json", forHTTPHeaderField: "Accept")
        urlRequest.setValue("Bearer \(token)", forHTTPHeaderField: "Authorization")

        let encoder = JSONEncoder()
        // Deterministic key order aids auditing; the payload is closed anyway.
        encoder.outputFormatting = [.sortedKeys]
        urlRequest.httpBody = try encoder.encode(request)

        let data: Data
        let response: URLResponse
        do {
            (data, response) = try await session.data(for: urlRequest)
        } catch let error as URLError {
            switch error.code {
            case .timedOut: throw AnswerClientError.timedOut
            case .notConnectedToInternet, .networkConnectionLost, .cannotConnectToHost, .cannotFindHost:
                throw AnswerClientError.offline
            default: throw AnswerClientError.serverUnavailable
            }
        }

        guard let http = response as? HTTPURLResponse else {
            throw AnswerClientError.malformedResponse
        }

        switch http.statusCode {
        case 200:
            let decoded: AnswerResponse
            do {
                decoded = try JSONDecoder().decode(AnswerResponse.self, from: data)
            } catch {
                throw AnswerClientError.malformedResponse
            }
            // Validate the success body against the request we sent before
            // accepting it. Any violation is treated as a malformed response
            // rather than surfaced as a real answer.
            guard Self.isValidResponse(decoded, for: request) else {
                throw AnswerClientError.malformedResponse
            }
            return decoded
        case 400:
            let message = (try? JSONDecoder().decode(AnswerErrorBody.self, from: data))?.error.message ?? "Invalid request"
            throw AnswerClientError.validationRejected(message)
        case 401, 403:
            throw AnswerClientError.unauthorized
        case 429:
            throw AnswerClientError.rateLimited
        case 500...599:
            throw AnswerClientError.serverUnavailable
        default:
            throw AnswerClientError.unexpectedStatus(http.statusCode)
        }
    }

    /// Validate a decoded success body against the request that produced it.
    ///
    /// Accepts only a response whose:
    /// - `requestId` exactly matches the request's lowercase UUID string,
    /// - `locale` equals the requested locale,
    /// - `answer` is non-empty after normalization,
    /// - `words` is within `1...request.maxWords`,
    /// - `provider` is one of the known kinds (`mock`, `openrouter`).
    ///
    /// Any deviation is a violation, mapped by the caller to `.malformedResponse`.
    static func isValidResponse(_ response: AnswerResponse, for request: AnswerRequest) -> Bool {
        guard response.requestId == request.requestId.uuidString.lowercased() else { return false }
        guard response.locale == request.locale.rawValue else { return false }
        let normalized = response.answer.trimmingCharacters(in: .whitespacesAndNewlines)
        guard !normalized.isEmpty else { return false }
        guard (1...request.maxWords).contains(response.words) else { return false }
        guard response.provider == "mock" || response.provider == "openrouter" else { return false }
        return true
    }
}
