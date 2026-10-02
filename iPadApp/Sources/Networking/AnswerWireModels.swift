import Foundation

// Wire contract for POST /v1/answers.
//
// This file defines the ONLY data allowed to cross the network: a request id,
// the confirmed recognized text, a locale from a fixed allow-list, and an
// answer-length limit. There is deliberately no way to place PKDrawing,
// stroke geometry, or a handwriting profile into `AnswerRequest`: it is a
// plain struct with fixed scalar fields and a hand-written `Encodable` that
// only emits those four keys.

/// Locales the backend accepts (mirrors Backend `SUPPORTED_LOCALES`).
public enum SupportedLocale: String, CaseIterable, Sendable, Codable {
    case en
    case enUS = "en-US"
    case enGB = "en-GB"
    case enAU = "en-AU"
    case enCA = "en-CA"

    /// Best-effort mapping from the device locale onto the allow-list, falling
    /// back to plain English when the region is not supported.
    public static func resolved(from locale: Locale = .current) -> SupportedLocale {
        let identifier = locale.identifier.replacingOccurrences(of: "_", with: "-")
        if let exact = SupportedLocale(rawValue: identifier) { return exact }
        let region = locale.region?.identifier
        switch region {
        case "US": return .enUS
        case "GB": return .enGB
        case "AU": return .enAU
        case "CA": return .enCA
        default: return .en
        }
    }
}

/// Backend limits mirrored from `Backend/src/schema.ts`.
public enum AnswerWire {
    public static let maxWordsLimit = 120
    public static let minWordsLimit = 1
    public static let maxQuestionChars = 2000
    public static let defaultMaxWords = 40
}

/// The request body for POST /v1/answers.
///
/// `Encodable` is hand-written so the on-wire shape is auditable and closed:
/// exactly `requestId`, `question`, `locale`, `maxWords`. No synthesized keys.
public struct AnswerRequest: Equatable, Sendable, Encodable {
    public let requestId: UUID
    public let question: String
    public let locale: SupportedLocale
    public let maxWords: Int

    public init(requestId: UUID = UUID(), question: String, locale: SupportedLocale, maxWords: Int = AnswerWire.defaultMaxWords) {
        self.requestId = requestId
        self.question = question
        self.locale = locale
        self.maxWords = min(max(maxWords, AnswerWire.minWordsLimit), AnswerWire.maxWordsLimit)
    }

    private enum CodingKeys: String, CodingKey {
        case requestId, question, locale, maxWords
    }

    public func encode(to encoder: Encoder) throws {
        var c = encoder.container(keyedBy: CodingKeys.self)
        // requestId is a lowercase UUID string on the wire.
        try c.encode(requestId.uuidString.lowercased(), forKey: .requestId)
        try c.encode(question, forKey: .question)
        try c.encode(locale.rawValue, forKey: .locale)
        try c.encode(maxWords, forKey: .maxWords)
    }

    /// Whether the request satisfies the backend's structural rules before we
    /// bother making a network call.
    public var isStructurallyValid: Bool {
        let trimmed = question.trimmingCharacters(in: .whitespacesAndNewlines)
        return !trimmed.isEmpty
            && trimmed.count <= AnswerWire.maxQuestionChars
            && (AnswerWire.minWordsLimit...AnswerWire.maxWordsLimit).contains(maxWords)
    }
}

/// The success body from POST /v1/answers.
public struct AnswerResponse: Equatable, Sendable, Codable {
    public let requestId: String
    public let answer: String
    public let words: Int
    public let locale: String
    public let provider: String

    public init(requestId: String, answer: String, words: Int, locale: String, provider: String) {
        self.requestId = requestId
        self.answer = answer
        self.words = words
        self.locale = locale
        self.provider = provider
    }
}

/// The structured error body the backend returns on failure.
public struct AnswerErrorBody: Equatable, Sendable, Codable {
    public struct Payload: Equatable, Sendable, Codable {
        public let code: String
        public let message: String
        public init(code: String, message: String) {
            self.code = code
            self.message = message
        }
    }
    public let error: Payload
    public init(error: Payload) {
        self.error = error
    }
}
