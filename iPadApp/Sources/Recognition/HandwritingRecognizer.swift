import Foundation
import PencilKit

/// Abstraction over on-device handwriting recognition. Implementations must be
/// safe to call from a concurrent context. There is deliberately no raster or
/// network fallback: recognition is on-device only.
public protocol HandwritingRecognizing: Sendable {
    /// Recognize the text of a vector drawing. Returns a trimmed, normalized
    /// string, or nil when nothing legible was found.
    func recognize(drawing: PKDrawing) async -> String?
}

/// Normalizes recognizer output the same way the backend normalizes text, so
/// what the user confirms is what will be sent.
public enum RecognitionText {
    public static func normalize(_ raw: String?) -> String? {
        guard let raw else { return nil }
        // Convert newlines/tabs to spaces, collapse runs of whitespace, trim.
        let spaced = raw
            .replacingOccurrences(of: "\n", with: " ")
            .replacingOccurrences(of: "\t", with: " ")
            .replacingOccurrences(of: "\r", with: " ")
        let collapsed = spaced.split(whereSeparator: { $0.isWhitespace }).joined(separator: " ")
        let trimmed = collapsed.trimmingCharacters(in: .whitespacesAndNewlines)
        return trimmed.isEmpty ? nil : trimmed
    }
}

/// Production recognizer backed by iPadOS 27 `PKStrokeRecognizer`.
public actor PencilKitHandwritingRecognizer: HandwritingRecognizing {
    private let preferredLanguages: [Locale.Language]

    public init(preferredLanguages: [Locale.Language] = [Locale.Language(identifier: "en")]) {
        self.preferredLanguages = preferredLanguages
    }

    public func recognize(drawing: PKDrawing) async -> String? {
        // A fresh recognizer per call keeps state isolated to this drawing.
        let recognizer = PKStrokeRecognizer(preferredLanguages: preferredLanguages)
        await recognizer.updateDrawing(drawing)
        let raw = await recognizer.recognizedText()
        return RecognitionText.normalize(raw)
    }
}
