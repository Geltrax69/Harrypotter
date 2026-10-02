import Foundation
import PencilKit
import SwiftUI

/// Orchestrates a single question-to-answer interaction. All mutable state is
/// isolated to the main actor. Long-running work (recognition, network) runs in
/// child tasks that are cancelled whenever the drawing changes, the page is
/// cleared, or a newer revision supersedes them.
@MainActor
@Observable
public final class PageViewModel {
    // MARK: - Observable state

    public private(set) var phase: InteractionPhase = .blank
    /// All of the user's ink on the page (every question asked so far).
    public private(set) var questionDrawing = PKDrawing()
    /// True while a question is being asked/answered; the view disables the
    /// drawing gesture (but not scrolling) while this holds.
    public private(set) var isDrawingLocked = false
    /// Every answer written on this page, oldest first.
    public private(set) var answers: [PageAnswer] = []
    /// Characters of the LAST answer revealed so far (`.max` once complete).
    public private(set) var revealedCharacters = Int.max

    /// Backwards-compatible accessor: existing call sites/tests use `drawing`.
    public var drawing: PKDrawing { questionDrawing }

    // MARK: - Dependencies

    private let recognizer: HandwritingRecognizing
    private let answerClient: AnswerRequesting
    private let locale: SupportedLocale
    private let debounce: Duration
    private var reduceMotion: Bool

    /// Page width in points used for answer layout; updated by the view.
    private var pageWidth: CGFloat = 500

    // MARK: - Concurrency control

    /// Monotonic revision. Any async result carrying a stale revision is dropped.
    private var revision: UInt64 = 0
    private var pipelineTask: Task<Void, Never>?
    /// When true, a successful recognition asks immediately instead of waiting
    /// on the confirmation slip. Tests keep the explicit confirm step.
    private let autoAsk: Bool
    /// Identities of strokes that belong to already-asked questions.
    private var askedStrokeKeys: Set<String> = []
    /// Stroke identities of the question currently being answered.
    private var currentQuestionKeys: Set<String> = []
    private var currentQuestionBounds = CGRect.null

    /// Strokes written since the last asked question.
    private var newQuestionInk: PKDrawing {
        PKDrawing(strokes: questionDrawing.strokes.filter { !askedStrokeKeys.contains(Self.key(for: $0)) })
    }

    /// A stable identity for a stroke that survives other strokes being erased.
    nonisolated static func key(for stroke: PKStroke) -> String {
        let b = stroke.renderBounds
        return "\(stroke.path.creationDate.timeIntervalSinceReferenceDate)|\(b.minX)|\(b.minY)|\(stroke.path.count)"
    }

    public init(
        recognizer: HandwritingRecognizing,
        answerClient: AnswerRequesting,
        locale: SupportedLocale = .resolved(),
        debounce: Duration = .milliseconds(1500),
        reduceMotion: Bool = false,
        autoAsk: Bool = false
    ) {
        self.autoAsk = autoAsk
        self.recognizer = recognizer
        self.answerClient = answerClient
        self.locale = locale
        self.debounce = debounce
        self.reduceMotion = reduceMotion
    }

    /// The view reports the system Reduce Motion setting so reveals honor it.
    public func setReduceMotion(_ value: Bool) { reduceMotion = value }

    /// Whether the page currently has any ink (used to gate the
    /// clear-confirmation dialog for nonblank pages).
    public var isPageNonblank: Bool {
        !DrawingHeuristics.isBlank(questionDrawing) || !answers.isEmpty
    }

    /// The view reports its usable content width so answers wrap correctly.
    public func updatePageWidth(_ width: CGFloat) {
        guard width > 0 else { return }
        pageWidth = width
    }

    // MARK: - Drawing input

    /// Called whenever the canvas reports a drawing change. Restarts the
    /// debounce/recognition pipeline for the new (not yet asked) content.
    public func drawingChanged(_ new: PKDrawing) {
        let erased = new.strokes.count < questionDrawing.strokes.count
        questionDrawing = new

        if erased {
            // An answer goes with its question: once every stroke of a question
            // is erased, its answer leaves the page too.
            let remaining = Set(new.strokes.map(Self.key(for:)))
            askedStrokeKeys.formIntersection(remaining)
            answers.removeAll { $0.questionKeys.isDisjoint(with: remaining) }
        }

        // While a question is being asked or answered, keep writing freely;
        // the new ink is picked up when that answer finishes.
        switch phase {
        case .sending, .rendering: return
        default: break
        }
        cancelPipeline()
        restartPipelineIfNeeded()
    }

    /// Starts reading whatever has been written since the last question.
    private func restartPipelineIfNeeded() {
        let fresh = newQuestionInk
        if DrawingHeuristics.isBlank(fresh) {
            phase = .blank
            return
        }
        if DrawingHeuristics.isTooSmall(fresh) {
            // Something is on the page but not enough to recognize yet.
            phase = .writing
            return
        }

        phase = .writing
        startPipeline(for: fresh)
    }

    /// Clears the page and resets to blank, cancelling all in-flight work,
    /// including any answer reveal.
    public func clear() {
        cancelPipeline()
        revision &+= 1
        questionDrawing = PKDrawing()
        answers = []
        revealedCharacters = .max
        askedStrokeKeys = []
        currentQuestionKeys = []
        currentQuestionBounds = .null
        isDrawingLocked = false
        phase = .blank
    }

    // MARK: - Confirmation actions

    /// User confirms the recognized text and asks.
    public func askKiro() {
        guard case let .confirming(text) = phase else { return }
        cancelPipeline()
        consumeNewQuestionInk()
        let myRevision = bumpRevision()
        phase = .sending(question: text)

        pipelineTask = Task { [weak self] in
            guard let self else { return }
            await self.performSend(question: text, revision: myRevision)
        }
    }

    /// User wants to keep writing: unlock, discard the confirmation, and let the
    /// next drawing change restart recognition. The ink is preserved.
    public func keepWriting() {
        cancelPipeline()
        isDrawingLocked = false
        phase = .writing
    }

    /// User starts over: same as clear, exposed with intent-revealing name.
    public func startOver() {
        clear()
    }

    /// Retry a failed send (only valid from a network error state).
    public func retry() {
        guard case let .error(err) = phase, case .network = err.kind,
              let text = err.recognizedText else { return }
        cancelPipeline()
        let myRevision = bumpRevision()
        phase = .sending(question: text)
        pipelineTask = Task { [weak self] in
            guard let self else { return }
            await self.performSend(question: text, revision: myRevision)
        }
    }

    // MARK: - Pipeline

    private func startPipeline(for drawing: PKDrawing) {
        let myRevision = bumpRevision()
        pipelineTask = Task { [weak self] in
            guard let self else { return }
            // The debounce is a meaningful "waiting to read" beat: after a short
            // settle, reflect that recognition is imminent so the status line
            // reads "Reading soon…" rather than staying on "Writing…".
            let settle = self.debounce / 3
            do {
                try await Task.sleep(for: settle)
            } catch { return }
            guard !Task.isCancelled, self.isCurrent(myRevision) else { return }
            self.phase = .waiting
            do {
                try await Task.sleep(for: self.debounce - settle)
            } catch {
                return // cancelled during debounce
            }
            guard !Task.isCancelled else { return }
            await self.runRecognition(drawing: drawing, revision: myRevision)
        }
    }

    private func runRecognition(drawing: PKDrawing, revision myRevision: UInt64) async {
        guard isCurrent(myRevision) else { return }
        phase = .recognizing

        let recognized = await recognizer.recognize(drawing: drawing)

        // Stale-revision rejection: a newer drawing/clear happened meanwhile.
        guard isCurrent(myRevision), !Task.isCancelled else { return }

        guard let text = RecognitionText.normalize(recognized), !text.isEmpty else {
            if autoAsk {
                // Say so on the page, under the unreadable writing.
                consumeNewQuestionInk()
                await presentAnswer(question: "", answer: Self.notUnderstood, revision: myRevision)
            } else {
                phase = .error(RecoverableError(kind: .recognitionFoundNothing, recognizedText: nil))
            }
            return
        }
        phase = .confirming(recognizedText: text)
        if autoAsk { askKiro() }
    }

    /// Marks everything written since the last question as the question now
    /// being answered.
    private func consumeNewQuestionInk() {
        let fresh = newQuestionInk
        currentQuestionBounds = fresh.bounds
        currentQuestionKeys = Set(fresh.strokes.map(Self.key(for:)))
        askedStrokeKeys.formUnion(currentQuestionKeys)
    }

    static let notUnderstood = "I didn't understand. Could you write it again?"
    static let unreachable = "I couldn't reach an answer just now. Please ask again."

    private func performSend(question: String, revision myRevision: UInt64) async {
        // In auto mode a failed request is retried once, then explained on the
        // page in the answer script instead of a pop-up.
        let attempts = autoAsk ? 2 : 1
        var lastError: AnswerClientError = .serverUnavailable
        for _ in 0..<attempts {
            do {
                let response = try await answerClient.requestAnswer(AnswerRequest(question: question, locale: locale))
                guard isCurrent(myRevision), !Task.isCancelled else { return }
                await presentAnswer(question: question, answer: response.answer, revision: myRevision)
                return
            } catch let err as AnswerClientError {
                lastError = err
            } catch {
                lastError = .serverUnavailable
            }
            guard isCurrent(myRevision), !Task.isCancelled else { return }
        }
        if autoAsk {
            await presentAnswer(question: question, answer: Self.unreachable, revision: myRevision)
        } else {
            phase = .error(RecoverableError(kind: .network(lastError), recognizedText: question))
        }
    }

    /// Writes the answer onto the page under its question, revealing it
    /// character by character (about 3 s at most). The phase stays
    /// `.rendering` until the reveal completes; a newer revision abandons it.
    private func presentAnswer(question: String, answer: String, revision myRevision: UInt64) async {
        phase = .rendering(question: question, answer: answer)

        let q = currentQuestionBounds
        let layout = PageViewModel.answerLayout(pageWidth: pageWidth, questionMinX: q.isNull ? nil : q.minX)
        answers.append(PageAnswer(
            text: answer,
            origin: CGPoint(x: layout.originX, y: q.isNull ? 0 : q.maxY + 12),
            questionKeys: currentQuestionKeys
        ))

        if !reduceMotion {
            // ~30 updates/s over at most ~3 s keeps the main thread free for ink.
            let total = answer.count
            let perFrame = max(1, Int((Double(total) / 90).rounded(.up)))
            revealedCharacters = 0
            while revealedCharacters < total {
                try? await Task.sleep(for: .milliseconds(33))
                guard isCurrent(myRevision), !Task.isCancelled else { return }
                revealedCharacters += perFrame
            }
        }
        guard isCurrent(myRevision), !Task.isCancelled else { return }
        revealedCharacters = .max
        phase = .answered(question: question, answer: answer)
        // Anything written meanwhile is the next question.
        restartPipelineIfNeeded()
    }

    /// Pure, testable clamp for the answer block's horizontal layout. Ensures a
    /// question written near the right edge can never push answer ink offscreen:
    /// the origin is clamped into `[leftInset, pageWidth - rightInset -
    /// minUsableWidth]` and the width is floored at `minUsableWidth`.
    static func answerLayout(
        pageWidth: CGFloat,
        questionMinX: CGFloat?,
        leftInset: CGFloat = PageGrid.marginX + 16,
        rightInset: CGFloat = 24,
        minUsableWidth: CGFloat = 120
    ) -> (originX: CGFloat, width: CGFloat) {
        let rawOriginX = questionMinX ?? leftInset
        let maxOriginX = max(leftInset, pageWidth - rightInset - minUsableWidth)
        let originX = min(max(rawOriginX, leftInset), maxOriginX)
        let availableWidth = max(pageWidth - originX - rightInset, minUsableWidth)
        return (originX, availableWidth)
    }

    // MARK: - Revision helpers

    private func bumpRevision() -> UInt64 {
        revision &+= 1
        return revision
    }

    private func isCurrent(_ candidate: UInt64) -> Bool {
        candidate == revision
    }

    private func cancelPipeline() {
        pipelineTask?.cancel()
        pipelineTask = nil
    }
}

/// One answer written on the page.
public struct PageAnswer: Identifiable, Equatable, Sendable {
    public let id = UUID()
    public let text: String
    /// Left edge and the y just below its question (layout snaps to rules).
    public let origin: CGPoint
    /// Stroke identities of the question it answers.
    public let questionKeys: Set<String>
}
