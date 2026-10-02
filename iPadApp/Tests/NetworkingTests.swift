import Testing
import Foundation
@testable import LivingPage

// MARK: - URLProtocol stub

final class StubURLProtocol: URLProtocol, @unchecked Sendable {
    struct Stub: Sendable {
        var statusCode: Int
        var body: Data
    }

    nonisolated(unsafe) static var stub: Stub?
    nonisolated(unsafe) static var capturedBody: Data?
    nonisolated(unsafe) static var capturedHeaders: [String: String]?
    nonisolated(unsafe) static var error: URLError?

    static func reset() {
        stub = nil
        capturedBody = nil
        capturedHeaders = nil
        error = nil
    }

    override class func canInit(with request: URLRequest) -> Bool { true }
    override class func canonicalRequest(for request: URLRequest) -> URLRequest { request }

    override func startLoading() {
        // URLSession may move the body into a stream; capture both forms.
        if let body = request.httpBody {
            StubURLProtocol.capturedBody = body
        } else if let stream = request.httpBodyStream {
            StubURLProtocol.capturedBody = StubURLProtocol.readStream(stream)
        }
        StubURLProtocol.capturedHeaders = request.allHTTPHeaderFields

        if let error = StubURLProtocol.error {
            client?.urlProtocol(self, didFailWithError: error)
            return
        }
        let stub = StubURLProtocol.stub ?? Stub(statusCode: 200, body: Data())
        let response = HTTPURLResponse(
            url: request.url!,
            statusCode: stub.statusCode,
            httpVersion: "HTTP/1.1",
            headerFields: ["Content-Type": "application/json"]
        )!
        client?.urlProtocol(self, didReceive: response, cacheStoragePolicy: .notAllowed)
        client?.urlProtocol(self, didLoad: stub.body)
        client?.urlProtocolDidFinishLoading(self)
    }

    override func stopLoading() {}

    private static func readStream(_ stream: InputStream) -> Data {
        stream.open()
        defer { stream.close() }
        var data = Data()
        let size = 4096
        var buffer = [UInt8](repeating: 0, count: size)
        while stream.hasBytesAvailable {
            let read = stream.read(&buffer, maxLength: size)
            if read <= 0 { break }
            data.append(buffer, count: read)
        }
        return data
    }
}

@MainActor
private func makeClient(token: String? = "device-token") -> HTTPAnswerClient {
    let config = URLSessionConfiguration.ephemeral
    config.protocolClasses = [StubURLProtocol.self]
    let session = URLSession(configuration: config)
    let store = InMemoryCredentialStore(token: token)
    return HTTPAnswerClient(baseURL: URL(string: "http://localhost:8080")!, credentials: store, session: session, timeout: 5)
}

/// Build a success body that satisfies the client's response validation for the
/// given request (matching requestId, locale, in-range words, known provider).
private func validResponseBody(for request: AnswerRequest, answer: String = "ok") throws -> Data {
    try JSONEncoder().encode(AnswerResponse(
        requestId: request.requestId.uuidString.lowercased(),
        answer: answer,
        words: max(1, min(request.maxWords, answer.split(separator: " ").count)),
        locale: request.locale.rawValue,
        provider: "mock"
    ))
}

@Suite("HTTP payload and wire contract", .serialized)
struct HTTPPayloadTests {

    @Test("Payload contains exactly the four allow-listed keys")
    func payloadAllowList() async throws {
        StubURLProtocol.reset()
        let request = AnswerRequest(question: "What is ink?", locale: .en, maxWords: 100)
        StubURLProtocol.stub = .init(statusCode: 200, body: try validResponseBody(for: request))
        let client = await makeClient()
        _ = try await client.requestAnswer(request)

        let body = try #require(StubURLProtocol.capturedBody)
        let json = try #require(try JSONSerialization.jsonObject(with: body) as? [String: Any])
        #expect(Set(json.keys) == ["requestId", "question", "locale", "maxWords"])
        #expect(json["question"] as? String == "What is ink?")
        #expect(json["locale"] as? String == "en")
        #expect(json["maxWords"] as? Int == 100)
    }

    @Test("No stroke, drawing, or profile data leaks into the payload")
    func noStrokeLeakage() async throws {
        StubURLProtocol.reset()
        let request = AnswerRequest(question: "hello", locale: .en)
        StubURLProtocol.stub = .init(statusCode: 200, body: try validResponseBody(for: request))
        let client = await makeClient()
        _ = try await client.requestAnswer(request)

        let body = try #require(StubURLProtocol.capturedBody)
        let text = String(data: body, encoding: .utf8)!.lowercased()
        for forbidden in ["stroke", "drawing", "pkdrawing", "profile", "path", "point", "force", "azimuth", "altitude", "ink"] {
            #expect(!text.contains(forbidden), "payload leaked \(forbidden)")
        }
    }

    @Test("Sets Content-Type and Bearer authorization header")
    func setsHeaders() async throws {
        StubURLProtocol.reset()
        let request = AnswerRequest(question: "hi", locale: .en)
        StubURLProtocol.stub = .init(statusCode: 200, body: try validResponseBody(for: request))
        let client = await makeClient(token: "secret-abc")
        _ = try await client.requestAnswer(request)
        let headers = try #require(StubURLProtocol.capturedHeaders)
        #expect(headers["Content-Type"] == "application/json")
        #expect(headers["Authorization"] == "Bearer secret-abc")
    }

    @Test("requestId is a lowercase UUID string")
    func requestIdIsLowercaseUUID() async throws {
        StubURLProtocol.reset()
        let id = UUID()
        let request = AnswerRequest(requestId: id, question: "hi", locale: .en)
        StubURLProtocol.stub = .init(statusCode: 200, body: try validResponseBody(for: request))
        let client = await makeClient()
        _ = try await client.requestAnswer(request)
        let body = try #require(StubURLProtocol.capturedBody)
        let json = try #require(try JSONSerialization.jsonObject(with: body) as? [String: Any])
        #expect(json["requestId"] as? String == id.uuidString.lowercased())
    }
}

@Suite("Auth and error mapping", .serialized)
struct ErrorMappingTests {

    private func errorBody(_ code: String, _ message: String) -> Data {
        try! JSONEncoder().encode(AnswerErrorBody(error: .init(code: code, message: message)))
    }

    @Test("No credential yields notConfigured")
    func notConfigured() async throws {
        StubURLProtocol.reset()
        let client = await makeClient(token: nil)
        await #expect(throws: AnswerClientError.notConfigured) {
            _ = try await client.requestAnswer(AnswerRequest(question: "hi", locale: .en))
        }
    }

    @Test("401 maps to unauthorized")
    func unauthorized() async throws {
        StubURLProtocol.reset()
        StubURLProtocol.stub = .init(statusCode: 401, body: errorBody("unauthorized", "no"))
        let client = await makeClient()
        await #expect(throws: AnswerClientError.unauthorized) {
            _ = try await client.requestAnswer(AnswerRequest(question: "hi", locale: .en))
        }
    }

    @Test("429 maps to rateLimited")
    func rateLimited() async throws {
        StubURLProtocol.reset()
        StubURLProtocol.stub = .init(statusCode: 429, body: errorBody("rate_limited", "slow"))
        let client = await makeClient()
        await #expect(throws: AnswerClientError.rateLimited) {
            _ = try await client.requestAnswer(AnswerRequest(question: "hi", locale: .en))
        }
    }

    @Test("400 maps to validationRejected with message")
    func validation() async throws {
        StubURLProtocol.reset()
        StubURLProtocol.stub = .init(statusCode: 400, body: errorBody("validation_error", "bad"))
        let client = await makeClient()
        do {
            _ = try await client.requestAnswer(AnswerRequest(question: "hi", locale: .en))
            Issue.record("expected throw")
        } catch let e as AnswerClientError {
            #expect(e == .validationRejected("bad"))
        }
    }

    @Test("502 maps to serverUnavailable and is retryable")
    func serverError() async throws {
        StubURLProtocol.reset()
        StubURLProtocol.stub = .init(statusCode: 502, body: errorBody("provider_failed", "boom"))
        let client = await makeClient()
        await #expect(throws: AnswerClientError.serverUnavailable) {
            _ = try await client.requestAnswer(AnswerRequest(question: "hi", locale: .en))
        }
        #expect(AnswerClientError.serverUnavailable.isRetryable)
    }

    @Test("URL timeout maps to timedOut")
    func timeout() async throws {
        StubURLProtocol.reset()
        StubURLProtocol.error = URLError(.timedOut)
        let client = await makeClient()
        await #expect(throws: AnswerClientError.timedOut) {
            _ = try await client.requestAnswer(AnswerRequest(question: "hi", locale: .en))
        }
    }

    @Test("Offline maps to offline")
    func offline() async throws {
        StubURLProtocol.reset()
        StubURLProtocol.error = URLError(.notConnectedToInternet)
        let client = await makeClient()
        await #expect(throws: AnswerClientError.offline) {
            _ = try await client.requestAnswer(AnswerRequest(question: "hi", locale: .en))
        }
    }
}

@Suite("Credential bootstrap and rotation")
struct CredentialBootstrapTests {

    private let validToken = "0123456789abcdef"       // exactly 16 chars
    private let anotherValidToken = "fedcba9876543210xyz" // >=16 chars

    @Test("Bootstrap token from env is saved to store when empty")
    @MainActor
    func bootstrapFromEnv() {
        let store = InMemoryCredentialStore(token: nil)
        let outcome = AppEnvironment.bootstrapCredentialIfNeeded(
            store: store,
            environment: [AppEnvironment.bootstrapTokenEnvKey: validToken]
        )
        #expect(outcome == .saved)
        #expect(store.bearerToken() == validToken)
    }

    @Test("Existing credential is not overwritten on ordinary launch")
    @MainActor
    func doesNotOverwrite() {
        let store = InMemoryCredentialStore(token: "existing-credential-value")
        let outcome = AppEnvironment.bootstrapCredentialIfNeeded(
            store: store,
            environment: [AppEnvironment.bootstrapTokenEnvKey: validToken]
        )
        #expect(outcome == .preservedExisting)
        #expect(store.bearerToken() == "existing-credential-value")
    }

    @Test("No env token leaves store empty")
    @MainActor
    func noEnvToken() {
        let store = InMemoryCredentialStore(token: nil)
        let outcome = AppEnvironment.bootstrapCredentialIfNeeded(store: store, environment: [:])
        #expect(outcome == .noToken)
        #expect(store.bearerToken() == nil)
    }

    @Test("Token shorter than the minimum is rejected and not saved")
    @MainActor
    func shortTokenRejected() {
        let store = InMemoryCredentialStore(token: nil)
        let outcome = AppEnvironment.bootstrapCredentialIfNeeded(
            store: store,
            environment: [AppEnvironment.bootstrapTokenEnvKey: "too-short"] // 9 chars
        )
        #expect(outcome == .tokenTooShort)
        #expect(store.bearerToken() == nil)
    }

    @Test("Explicit reset rotates: clears existing then saves the new token")
    @MainActor
    func explicitRotation() {
        let store = InMemoryCredentialStore(token: "old-existing-credential")
        let outcome = AppEnvironment.bootstrapCredentialIfNeeded(
            store: store,
            environment: [
                AppEnvironment.resetCredentialEnvKey: "1",
                AppEnvironment.bootstrapTokenEnvKey: anotherValidToken,
            ]
        )
        #expect(outcome == .saved)
        #expect(store.bearerToken() == anotherValidToken)
    }

    @Test("Reset without a new token clears the existing credential and reports it")
    @MainActor
    func resetWithoutNewToken() {
        let store = InMemoryCredentialStore(token: "old-existing-credential")
        let outcome = AppEnvironment.bootstrapCredentialIfNeeded(
            store: store,
            environment: [AppEnvironment.resetCredentialEnvKey: "1"]
        )
        #expect(outcome == .clearedWithoutNewToken)
        #expect(store.bearerToken() == nil)
    }

    @Test("Reset with a short new token clears but does not save the short token")
    @MainActor
    func resetWithShortToken() {
        let store = InMemoryCredentialStore(token: "old-existing-credential")
        let outcome = AppEnvironment.bootstrapCredentialIfNeeded(
            store: store,
            environment: [
                AppEnvironment.resetCredentialEnvKey: "1",
                AppEnvironment.bootstrapTokenEnvKey: "short",
            ]
        )
        #expect(outcome == .tokenTooShort)
        #expect(store.bearerToken() == nil)
    }

    @Test("Clear failure surfaces as saveFailed and preserves nothing new")
    @MainActor
    func clearFailure() {
        let store = FailingClearCredentialStore(token: "old-existing-credential")
        let outcome = AppEnvironment.bootstrapCredentialIfNeeded(
            store: store,
            environment: [
                AppEnvironment.resetCredentialEnvKey: "1",
                AppEnvironment.bootstrapTokenEnvKey: anotherValidToken,
            ]
        )
        #expect(outcome == .saveFailed)
    }
}

/// A credential store whose `clear()` always throws, to exercise the reset
/// failure path without touching the Keychain.
final class FailingClearCredentialStore: DeviceCredentialStoring, @unchecked Sendable {
    private let lock = NSLock()
    private var token: String?
    init(token: String?) { self.token = token }
    func bearerToken() -> String? { lock.lock(); defer { lock.unlock() }; return token }
    func save(bearerToken: String) throws { lock.lock(); defer { lock.unlock() }; token = bearerToken }
    func clear() throws { throw KeychainError.unexpectedStatus(-1) }
}

@Suite("Base URL resolution")
struct BaseURLResolutionTests {
    @MainActor
    private func resolve(_ raw: String?) -> AppEnvironment.BaseURLResolution {
        var env: [String: String] = [:]
        if let raw { env[AppEnvironment.baseURLEnvKey] = raw }
        return AppEnvironment.resolveBaseURL(environment: env)
    }

    @Test("Absent env falls back to localhost default")
    @MainActor
    func absentDefaults() {
        #expect(resolve(nil) == .accepted(AppEnvironment.defaultBaseURL))
        #expect(AppEnvironment.baseURL(environment: [:]).absoluteString == "http://localhost:8080")
    }

    @Test("HTTPS URL is accepted")
    @MainActor
    func httpsAccepted() {
        let r = resolve("https://api.example.com")
        #expect(r == .accepted(URL(string: "https://api.example.com")!))
    }

    @Test("Loopback HTTP is accepted (localhost, 127.0.0.1)")
    @MainActor
    func loopbackHTTPAccepted() {
        #expect(resolve("http://localhost:8080") == .accepted(URL(string: "http://localhost:8080")!))
        #expect(resolve("http://127.0.0.1:8080") == .accepted(URL(string: "http://127.0.0.1:8080")!))
    }

    @Test("Remote HTTP is rejected and falls back")
    @MainActor
    func remoteHTTPRejected() {
        let r = resolve("http://api.example.com")
        #expect(r == .rejected(reason: .cleartextRemoteHost, fallback: AppEnvironment.defaultBaseURL))
        #expect(r.url == AppEnvironment.defaultBaseURL)
    }

    @Test("Malformed URL is rejected and falls back")
    @MainActor
    func malformedRejected() {
        let r = resolve("http://a b c::::not a url")
        if case .rejected = r {} else { Issue.record("expected rejected, got \(r)") }
        #expect(r.url == AppEnvironment.defaultBaseURL)
    }

    @Test("Credential-bearing URL is rejected and falls back")
    @MainActor
    func credentialsRejected() {
        let r = resolve("https://user:password@api.example.com")
        #expect(r == .rejected(reason: .containsCredentials, fallback: AppEnvironment.defaultBaseURL))
        #expect(r.url == AppEnvironment.defaultBaseURL)
    }

    @Test("Non-http(s) scheme is rejected and falls back")
    @MainActor
    func unsupportedSchemeRejected() {
        let r = resolve("ftp://api.example.com")
        #expect(r == .rejected(reason: .unsupportedScheme, fallback: AppEnvironment.defaultBaseURL))
    }
}

@Suite("Wire model validation")
struct WireModelTests {
    @Test("maxWords is clamped to backend limits")
    func maxWordsClamped() {
        #expect(AnswerRequest(question: "x", locale: .en, maxWords: 9999).maxWords == 120)
        #expect(AnswerRequest(question: "x", locale: .en, maxWords: 0).maxWords == 1)
    }

    @Test("Blank question is structurally invalid")
    func blankInvalid() {
        #expect(!AnswerRequest(question: "   ", locale: .en).isStructurallyValid)
        #expect(AnswerRequest(question: "hi", locale: .en).isStructurallyValid)
    }

    @Test("Locale resolves to allow-list")
    func localeResolves() {
        #expect(SupportedLocale.allCases.contains(SupportedLocale.resolved(from: Locale(identifier: "en_US"))))
    }
}

@Suite("Response validation against the request", .serialized)
struct ResponseValidationTests {

    private func stubbedResponse(
        requestId: String,
        answer: String,
        words: Int,
        locale: String,
        provider: String
    ) throws -> Data {
        try JSONEncoder().encode(AnswerResponse(
            requestId: requestId, answer: answer, words: words, locale: locale, provider: provider
        ))
    }

    @Test("A matching, in-range response is accepted")
    func acceptsValid() async throws {
        StubURLProtocol.reset()
        let request = AnswerRequest(question: "hi", locale: .en, maxWords: 40)
        StubURLProtocol.stub = .init(statusCode: 200, body: try validResponseBody(for: request, answer: "a fine answer"))
        let client = await makeClient()
        let response = try await client.requestAnswer(request)
        #expect(response.requestId == request.requestId.uuidString.lowercased())
        #expect(response.words <= request.maxWords)
    }

    @Test("Mismatched requestId maps to malformedResponse")
    func rejectsRequestIdMismatch() async throws {
        StubURLProtocol.reset()
        let request = AnswerRequest(question: "hi", locale: .en, maxWords: 40)
        StubURLProtocol.stub = .init(statusCode: 200, body: try stubbedResponse(
            requestId: UUID().uuidString.lowercased(), answer: "ok", words: 1, locale: "en", provider: "mock"
        ))
        let client = await makeClient()
        await #expect(throws: AnswerClientError.malformedResponse) {
            _ = try await client.requestAnswer(request)
        }
    }

    @Test("Wrong locale maps to malformedResponse")
    func rejectsLocaleMismatch() async throws {
        StubURLProtocol.reset()
        let request = AnswerRequest(question: "hi", locale: .en, maxWords: 40)
        StubURLProtocol.stub = .init(statusCode: 200, body: try stubbedResponse(
            requestId: request.requestId.uuidString.lowercased(), answer: "ok", words: 1, locale: "en-GB", provider: "mock"
        ))
        let client = await makeClient()
        await #expect(throws: AnswerClientError.malformedResponse) {
            _ = try await client.requestAnswer(request)
        }
    }

    @Test("Empty/whitespace answer maps to malformedResponse")
    func rejectsEmptyAnswer() async throws {
        StubURLProtocol.reset()
        let request = AnswerRequest(question: "hi", locale: .en, maxWords: 40)
        StubURLProtocol.stub = .init(statusCode: 200, body: try stubbedResponse(
            requestId: request.requestId.uuidString.lowercased(), answer: "   ", words: 1, locale: "en", provider: "mock"
        ))
        let client = await makeClient()
        await #expect(throws: AnswerClientError.malformedResponse) {
            _ = try await client.requestAnswer(request)
        }
    }

    @Test("words above request.maxWords maps to malformedResponse")
    func rejectsTooManyWords() async throws {
        StubURLProtocol.reset()
        let request = AnswerRequest(question: "hi", locale: .en, maxWords: 10)
        StubURLProtocol.stub = .init(statusCode: 200, body: try stubbedResponse(
            requestId: request.requestId.uuidString.lowercased(), answer: "ok", words: 11, locale: "en", provider: "mock"
        ))
        let client = await makeClient()
        await #expect(throws: AnswerClientError.malformedResponse) {
            _ = try await client.requestAnswer(request)
        }
    }

    @Test("words below 1 maps to malformedResponse")
    func rejectsZeroWords() async throws {
        StubURLProtocol.reset()
        let request = AnswerRequest(question: "hi", locale: .en, maxWords: 10)
        StubURLProtocol.stub = .init(statusCode: 200, body: try stubbedResponse(
            requestId: request.requestId.uuidString.lowercased(), answer: "ok", words: 0, locale: "en", provider: "mock"
        ))
        let client = await makeClient()
        await #expect(throws: AnswerClientError.malformedResponse) {
            _ = try await client.requestAnswer(request)
        }
    }

    @Test("Unknown provider maps to malformedResponse")
    func rejectsUnknownProvider() async throws {
        StubURLProtocol.reset()
        let request = AnswerRequest(question: "hi", locale: .en, maxWords: 40)
        StubURLProtocol.stub = .init(statusCode: 200, body: try stubbedResponse(
            requestId: request.requestId.uuidString.lowercased(), answer: "ok", words: 1, locale: "en", provider: "wat"
        ))
        let client = await makeClient()
        await #expect(throws: AnswerClientError.malformedResponse) {
            _ = try await client.requestAnswer(request)
        }
    }

    @Test("openrouter provider is accepted")
    func acceptsOpenRouterProvider() async throws {
        StubURLProtocol.reset()
        let request = AnswerRequest(question: "hi", locale: .en, maxWords: 40)
        StubURLProtocol.stub = .init(statusCode: 200, body: try stubbedResponse(
            requestId: request.requestId.uuidString.lowercased(), answer: "ok", words: 1, locale: "en", provider: "openrouter"
        ))
        let client = await makeClient()
        let response = try await client.requestAnswer(request)
        #expect(response.provider == "openrouter")
    }
}
