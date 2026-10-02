import Foundation
import PencilKit

/// Deterministic recognizer for UI/unit tests: returns a fixed string for any
/// non-empty drawing, regardless of stroke content.
public struct DeterministicRecognizer: HandwritingRecognizing {
    private let text: String?
    public init(text: String? = "What lives on a living page?") {
        self.text = text
    }
    public func recognize(drawing: PKDrawing) async -> String? {
        if drawing.strokes.isEmpty { return nil }
        return RecognitionText.normalize(text)
    }
}

/// Deterministic answer client for UI/unit tests. Never touches the network.
public struct DeterministicAnswerClient: AnswerRequesting {
    private let answer: String
    private let failure: AnswerClientError?
    public init(answer: String = "A living page answers in the ink you gave it.", failure: AnswerClientError? = nil) {
        self.answer = answer
        self.failure = failure
    }
    public func requestAnswer(_ request: AnswerRequest) async throws -> AnswerResponse {
        if let failure { throw failure }
        return AnswerResponse(
            requestId: request.requestId.uuidString.lowercased(),
            answer: answer,
            words: answer.split(separator: " ").count,
            locale: request.locale.rawValue,
            provider: "mock"
        )
    }
}

/// Assembles the object graph for the app. Chooses production or deterministic
/// dependencies based on launch arguments and the process environment.
@MainActor
public enum AppEnvironment {
    public static let uiTestingFlag = "--ui-testing"
    public static let bootstrapTokenEnvKey = "LIVINGPAGE_BOOTSTRAP_TOKEN"
    public static let baseURLEnvKey = "LIVINGPAGE_BASE_URL"
    public static let resetCredentialEnvKey = "LIVINGPAGE_RESET_DEVICE_CREDENTIAL"

    /// Minimum device bearer-token length. Mirrors the backend requirement of
    /// `DEVICE_AUTH_TOKEN` being at least 16 characters (see
    /// `Backend/src/config.ts`), so a token that would be rejected at the
    /// server is never persisted on the device in the first place.
    public static let minTokenLength = 16

    /// The safe default backend origin for Simulator development.
    public static let defaultBaseURL = URL(string: "http://localhost:8080")!

    public static var isUITesting: Bool {
        ProcessInfo.processInfo.arguments.contains(uiTestingFlag)
    }

    /// The outcome of resolving `LIVINGPAGE_BASE_URL`, so callers (and tests)
    /// can distinguish an accepted URL from a rejected one that fell back to the
    /// safe default. There is deliberately no interactive typing UI: an
    /// unusable value produces a documented fallback rather than a prompt.
    public enum BaseURLResolution: Equatable, Sendable {
        /// The environment value was accepted as-is.
        case accepted(URL)
        /// The environment value was rejected for the given reason and the
        /// caller should use `defaultBaseURL` instead.
        case rejected(reason: Reason, fallback: URL)

        public enum Reason: Equatable, Sendable {
            case malformed              // not parseable as a URL
            case unsupportedScheme      // scheme other than http/https
            case containsCredentials    // user:password@ present in the URL
            case cleartextRemoteHost    // http:// to a non-loopback host
            case missingHost            // no host component
        }

        public var url: URL {
            switch self {
            case .accepted(let url): return url
            case .rejected(_, let fallback): return fallback
            }
        }
    }

    private static let loopbackHosts: Set<String> = ["localhost", "127.0.0.1", "::1"]

    /// Resolve and validate the configured base URL.
    ///
    /// Policy:
    /// - Accept any well-formed `https://` URL (with a host, no embedded
    ///   credentials).
    /// - Accept `http://` ONLY for loopback hosts (`localhost`, `127.0.0.1`,
    ///   `::1`) to support Simulator development against a local backend.
    /// - Reject URLs that embed credentials (`user:password@host`).
    /// - Reject non-`http(s)` schemes and cleartext `http://` to any remote
    ///   host. Rejected values fall back to `defaultBaseURL`; the reason is
    ///   returned so callers can log/document it. No typing UI is introduced.
    public static func resolveBaseURL(
        environment: [String: String] = ProcessInfo.processInfo.environment
    ) -> BaseURLResolution {
        guard let raw = environment[baseURLEnvKey], !raw.isEmpty else {
            return .accepted(defaultBaseURL)
        }
        guard let components = URLComponents(string: raw), let url = URL(string: raw) else {
            return .rejected(reason: .malformed, fallback: defaultBaseURL)
        }
        // Reject embedded credentials regardless of scheme.
        if components.user != nil || components.password != nil {
            return .rejected(reason: .containsCredentials, fallback: defaultBaseURL)
        }
        guard let scheme = components.scheme?.lowercased() else {
            return .rejected(reason: .unsupportedScheme, fallback: defaultBaseURL)
        }
        guard let host = components.host, !host.isEmpty else {
            return .rejected(reason: .missingHost, fallback: defaultBaseURL)
        }
        switch scheme {
        case "https":
            return .accepted(url)
        case "http":
            if loopbackHosts.contains(host.lowercased()) {
                return .accepted(url)
            }
            return .rejected(reason: .cleartextRemoteHost, fallback: defaultBaseURL)
        default:
            return .rejected(reason: .unsupportedScheme, fallback: defaultBaseURL)
        }
    }

    /// Base URL from the environment, defaulting safely to localhost for local
    /// dev. Rejected values (see `resolveBaseURL`) fall back to the default.
    public static func baseURL(environment: [String: String] = ProcessInfo.processInfo.environment) -> URL {
        resolveBaseURL(environment: environment).url
    }

    /// The result of bootstrapping/rotating the device credential.
    public enum CredentialBootstrapOutcome: Equatable, Sendable {
        /// A new token was saved (fresh bootstrap or explicit rotation).
        case saved
        /// An existing credential was left untouched (ordinary launch).
        case preservedExisting
        /// No usable token was supplied and nothing was saved.
        case noToken
        /// A token was supplied but was shorter than `minTokenLength`.
        case tokenTooShort
        /// Persisting the token to the store failed.
        case saveFailed
        /// Reset was requested and the existing credential was cleared, but no
        /// new token was supplied, so the device is left unconfigured.
        case clearedWithoutNewToken
    }

    /// Bootstrap or rotate the device credential.
    ///
    /// Ordinary launch: if the store already holds a credential it is NEVER
    /// overwritten. A token is taken from the process environment
    /// (`LIVINGPAGE_BOOTSTRAP_TOKEN`) only when the store is empty.
    ///
    /// Explicit one-shot rotation/reset: when `LIVINGPAGE_RESET_DEVICE_CREDENTIAL`
    /// is `1`, any existing credential is cleared first, then the new bootstrap
    /// token is persisted. This is the ONLY path that overwrites an existing
    /// credential and must be triggered deliberately (a single launch with the
    /// env var set), then removed.
    ///
    /// A token shorter than `minTokenLength` (16, matching the backend) is
    /// rejected before saving. The token value is never logged or returned.
    @discardableResult
    public static func bootstrapCredentialIfNeeded(
        store: DeviceCredentialStoring,
        environment: [String: String] = ProcessInfo.processInfo.environment
    ) -> CredentialBootstrapOutcome {
        let resetRequested = environment[resetCredentialEnvKey] == "1"
        let suppliedToken = environment[bootstrapTokenEnvKey]

        if resetRequested {
            // Explicit one-shot rotation: clear first, then require a valid new token.
            do {
                try store.clear()
            } catch {
                return .saveFailed
            }
            guard let token = suppliedToken, !token.isEmpty else {
                return .clearedWithoutNewToken
            }
            guard token.count >= minTokenLength else {
                return .tokenTooShort
            }
            return persist(token, to: store)
        }

        // Ordinary launch: never overwrite an existing credential.
        if store.bearerToken() != nil {
            return .preservedExisting
        }
        guard let token = suppliedToken, !token.isEmpty else {
            return .noToken
        }
        guard token.count >= minTokenLength else {
            return .tokenTooShort
        }
        return persist(token, to: store)
    }

    /// Persist a token, verifying it landed. Never logs the token value.
    private static func persist(_ token: String, to store: DeviceCredentialStoring) -> CredentialBootstrapOutcome {
        do {
            try store.save(bearerToken: token)
        } catch {
            return .saveFailed
        }
        return store.bearerToken() != nil ? .saved : .saveFailed
    }

    public static func makeViewModel() -> PageViewModel {
        if isUITesting {
            // UI tests get deterministic recognizer/answer plus an isolated,
            // in-memory profile store and key-value store so runs don't touch
            // real Application Support or UserDefaults.
            return PageViewModel(
                recognizer: DeterministicRecognizer(),
                answerClient: DeterministicAnswerClient(),
                locale: .en,
                // Short debounce keeps UI tests fast but still exercises the phase.
                debounce: .milliseconds(150)
            )
        }

        let store = KeychainCredentialStore()
        bootstrapCredentialIfNeeded(store: store)
        let client = HTTPAnswerClient(baseURL: baseURL(), credentials: store)
        return PageViewModel(
            recognizer: PencilKitHandwritingRecognizer(),
            answerClient: client,
            locale: .resolved(),
            // Long enough not to read a half-written question at a word gap.
            debounce: .milliseconds(1600),
            autoAsk: true
        )
    }

    /// A UI-testing profile store, optionally pre-seeded with a synthetic usable
    /// Personal profile when the harness passes `--seed-profile`.
    private static func uiTestingProfileStore() -> HandwritingProfileStoring {
        let store = InMemoryProfileStore()
        if ProcessInfo.processInfo.arguments.contains("--seed-profile") {
            try? store.saveProfile(SyntheticProfile.usable())
        }
        return store
    }

    /// A synthetic drawing the UI test harness can inject via launch argument to
    /// drive the flow without an Apple Pencil.
    public static var uiTestingInjectedDrawing: PKDrawing? {
        guard isUITesting else { return nil }
        return SyntheticDrawing.line()
    }
}
