import Foundation

/// The explicit, testable phases of a single question-to-answer interaction.
///
/// blank -> writing -> waiting -> recognizing -> confirming -> sending -> answered
/// with `error` reachable from recognizing/sending, and a return to any phase on
/// new drawing or clear.
public enum InteractionPhase: Equatable, Sendable {
    /// Empty page, nothing written.
    case blank
    /// Ink is on the page; the idle debounce has not yet elapsed.
    case writing
    /// Debounce elapsed conceptually; waiting to begin recognition.
    case waiting
    /// On-device recognition is running.
    case recognizing
    /// Recognition produced text; awaiting the user's confirmation.
    case confirming(recognizedText: String)
    /// A confirmed question is in flight to the backend.
    case sending(question: String)
    /// HTTP succeeded; the answer is being composed/animated as vector ink.
    case rendering(question: String, answer: String)
    /// The backend returned an answer and its ink reveal has completed.
    case answered(question: String, answer: String)
    /// A recoverable failure. The drawing and recognized text are preserved.
    case error(RecoverableError)

    public var isTerminalForDrawing: Bool {
        switch self {
        case .confirming, .sending, .rendering, .answered: return true
        default: return false
        }
    }
}

/// A recoverable error surfaced to the user with enough context to retry.
public struct RecoverableError: Equatable, Sendable {
    public enum Kind: Equatable, Sendable {
        case recognitionFoundNothing
        case network(AnswerClientError)
    }
    public let kind: Kind
    /// Preserved recognized text (if any) so recovery UI can keep it.
    public let recognizedText: String?

    public init(kind: Kind, recognizedText: String?) {
        self.kind = kind
        self.recognizedText = recognizedText
    }

    public var message: String {
        switch kind {
        case .recognitionFoundNothing:
            return "I couldn't read anything yet. Keep writing, or start over."
        case .network(let e):
            return e.userMessage
        }
    }
}
