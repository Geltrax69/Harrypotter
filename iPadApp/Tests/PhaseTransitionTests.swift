import Testing
import Foundation
import PencilKit
@testable import LivingPage

// MARK: - Phase / state transitions

@MainActor
@Suite("Phase transitions")
struct PhaseTransitionTests {

    private func makeModel(
        recognizer: HandwritingRecognizing = DeterministicRecognizer(text: "hello there"),
        answer: AnswerRequesting = DeterministicAnswerClient(),
        debounce: Duration = .milliseconds(20)
    ) -> PageViewModel {
        PageViewModel(
            recognizer: recognizer,
            answerClient: answer,
            locale: .en,
            debounce: debounce,
            animator: AnswerInkAnimator(
                frameInterval: .microseconds(250),
                pointsPerFrame: 64,
                pacing: AnswerPacing(
                    basePointsPerFrame: 64,
                    targetMaxDuration: .milliseconds(100),
                    maxPointsPerFrame: 256
                )
            )
        )
    }

    @Test("Starts blank")
    func startsBlank() {
        let m = makeModel()
        #expect(m.phase == .blank)
        #expect(!m.isDrawingLocked)
    }

    @Test("Blank drawing keeps phase blank")
    func blankDrawingStaysBlank() {
        let m = makeModel()
        m.drawingChanged(PKDrawing())
        #expect(m.phase == .blank)
    }

    @Test("Tiny drawing is rejected to writing, never recognized")
    func tinyDrawingRejected() async throws {
        let m = makeModel(debounce: .milliseconds(10))
        m.drawingChanged(SyntheticDrawing.tinyDot())
        #expect(m.phase == .writing)
        // Wait longer than the debounce; it must NOT advance to recognizing.
        try await Task.sleep(for: .milliseconds(80))
        #expect(m.phase == .writing)
    }

    @Test("Real drawing flows writing -> confirming with recognized text")
    func fullRecognitionFlow() async throws {
        let m = makeModel()
        m.drawingChanged(SyntheticDrawing.line())
        #expect(m.phase == .writing)
        try await waitUntil { if case .confirming = m.phase { return true }; return false }
        #expect(m.phase == .confirming(recognizedText: "hello there"))
    }

    @Test("Empty recognition result surfaces recoverable error")
    func emptyRecognitionErrors() async throws {
        let m = makeModel(recognizer: DeterministicRecognizer(text: "   "))
        m.drawingChanged(SyntheticDrawing.line())
        try await waitUntil { if case .error = m.phase { return true }; return false }
        if case .error(let e) = m.phase {
            #expect(e.kind == .recognitionFoundNothing)
        } else {
            Issue.record("expected error phase")
        }
    }

    @Test("Ask Kiro sends and reaches answered; drawing locks")
    func askKiroAnswers() async throws {
        let m = makeModel()
        m.drawingChanged(SyntheticDrawing.line())
        try await waitUntil { if case .confirming = m.phase { return true }; return false }
        m.askKiro()
        #expect(m.isDrawingLocked)
        try await waitUntil { if case .answered = m.phase { return true }; return false }
        if case .answered(let q, let a) = m.phase {
            #expect(q == "hello there")
            #expect(!a.isEmpty)
        } else {
            Issue.record("expected answered")
        }
    }

    @Test("Keep Writing unlocks and returns to writing")
    func keepWritingUnlocks() async throws {
        let m = makeModel()
        m.drawingChanged(SyntheticDrawing.line())
        try await waitUntil { if case .confirming = m.phase { return true }; return false }
        m.keepWriting()
        #expect(!m.isDrawingLocked)
        #expect(m.phase == .writing)
    }

    @Test("Clear resets to blank and unlocks")
    func clearResets() async throws {
        let m = makeModel()
        m.drawingChanged(SyntheticDrawing.line())
        try await waitUntil { if case .confirming = m.phase { return true }; return false }
        m.askKiro()
        m.clear()
        #expect(m.phase == .blank)
        #expect(!m.isDrawingLocked)
        #expect(m.drawing.strokes.isEmpty)
    }
}

// MARK: - Debounce / cancellation / stale results

@MainActor
@Suite("Debounce and cancellation")
struct DebounceTests {

    @Test("New drawing before debounce cancels the prior recognition")
    func debounceCancelledByNewDrawing() async throws {
        let counter = CallCounter()
        let m = PageViewModel(
            recognizer: CountingRecognizer(counter: counter, text: "final"),
            answerClient: DeterministicAnswerClient(),
            locale: .en,
            debounce: .milliseconds(60)
        )
        m.drawingChanged(SyntheticDrawing.line(length: 300))
        try await Task.sleep(for: .milliseconds(20)) // before debounce fires
        m.drawingChanged(SyntheticDrawing.line(length: 340)) // supersedes
        try await waitUntil { if case .confirming = m.phase { return true }; return false }
        // Recognition should have run only once (for the surviving drawing).
        #expect(await counter.value == 1)
    }

    @Test("Clear during debounce prevents recognition entirely")
    func clearDuringDebounce() async throws {
        let counter = CallCounter()
        let m = PageViewModel(
            recognizer: CountingRecognizer(counter: counter, text: "x"),
            answerClient: DeterministicAnswerClient(),
            locale: .en,
            debounce: .milliseconds(60)
        )
        m.drawingChanged(SyntheticDrawing.line())
        try await Task.sleep(for: .milliseconds(15))
        m.clear()
        try await Task.sleep(for: .milliseconds(120))
        #expect(m.phase == .blank)
        #expect(await counter.value == 0)
    }

    @Test("Stale recognition result is dropped when revision advances")
    func staleResultDropped() async throws {
        // Slow recognizer: first call sleeps, letting a newer revision land.
        let m = PageViewModel(
            recognizer: SlowThenFastRecognizer(),
            answerClient: DeterministicAnswerClient(),
            locale: .en,
            debounce: .milliseconds(10)
        )
        m.drawingChanged(SyntheticDrawing.line(length: 300))
        try await Task.sleep(for: .milliseconds(30)) // recognition in-flight (slow)
        m.clear() // advance revision; stale result must not resurrect a phase
        try await Task.sleep(for: .milliseconds(120))
        #expect(m.phase == .blank)
    }
}

// MARK: - Test helpers

actor CallCounter {
    private(set) var value = 0
    func increment() { value += 1 }
}

struct CountingRecognizer: HandwritingRecognizing {
    let counter: CallCounter
    let text: String?
    func recognize(drawing: PKDrawing) async -> String? {
        await counter.increment()
        return RecognitionText.normalize(text)
    }
}

struct SlowThenFastRecognizer: HandwritingRecognizing {
    func recognize(drawing: PKDrawing) async -> String? {
        try? await Task.sleep(for: .milliseconds(60))
        return "late result"
    }
}

/// Polls a condition on the main actor until true or a timeout elapses.
@MainActor
func waitUntil(timeout: Duration = .seconds(2), _ condition: () -> Bool) async throws {
    let deadline = ContinuousClock.now.advanced(by: timeout)
    while ContinuousClock.now < deadline {
        if condition() { return }
        try await Task.sleep(for: .milliseconds(10))
    }
    #expect(condition(), "condition not met before timeout")
}
