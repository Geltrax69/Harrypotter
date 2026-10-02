import Testing
import Foundation
import CoreGraphics
import PencilKit
@testable import LivingPage

// MARK: - Scroll sync (Material Issue 1: answer must track the question)

@MainActor
@Suite("Scroll sync coordinator")
struct ScrollSyncCoordinatorTests {

    @Test("Answer offset mirrors the question scroll offset exactly")
    func mirrorsQuestionOffset() {
        let sync = ScrollSyncCoordinator()
        #expect(sync.offset == .zero)

        sync.questionDidScroll(to: CGPoint(x: 0, y: 420))
        // The answer canvas consumes `sync.offset`; mirroring is 1:1 so answer
        // strokes at absolute page coords stay pinned below the question.
        #expect(sync.offset == CGPoint(x: 0, y: 420))

        sync.questionDidScroll(to: CGPoint(x: 0, y: 0))
        #expect(sync.offset == .zero)
    }

    @Test("Content height grows to fit a long answer and never shrinks below question")
    func contentHeightGrows() {
        let sync = ScrollSyncCoordinator()
        sync.updateContentHeight(1200)
        #expect(sync.contentHeight == 1200)

        sync.updateContentHeight(3400)
        #expect(sync.contentHeight == 3400)

        // Negative/degenerate heights clamp to zero rather than corrupting layout.
        sync.updateContentHeight(-50)
        #expect(sync.contentHeight == 0)
    }

    @Test("Repeated identical offsets do not thrash published state")
    func idempotentOffset() {
        let sync = ScrollSyncCoordinator()
        sync.questionDidScroll(to: CGPoint(x: 0, y: 100))
        let first = sync.offset
        sync.questionDidScroll(to: CGPoint(x: 0, y: 100))
        #expect(sync.offset == first)
    }
}

// MARK: - Delete handwriting (Material Issue 2: user-reachable profile delete)

@MainActor
@Suite("Delete handwriting")
struct DeleteHandwritingTests {

    private func makeModel(store: HandwritingProfileStoring) -> PageViewModel {
        PageViewModel(
            recognizer: DeterministicRecognizer(text: "hello"),
            answerClient: DeterministicAnswerClient(),
            locale: .en,
            debounce: .milliseconds(10),
            styleSettings: StyleSettings(store: InMemoryKeyValueStore()),
            profileStore: store
        )
    }

    @Test("hasPersonalProfile reflects a stored profile")
    func hasProfileFlag() throws {
        let store = InMemoryProfileStore()
        let empty = makeModel(store: store)
        #expect(empty.hasPersonalProfile == false)

        try store.saveProfile(SyntheticProfile.usable())
        let seeded = makeModel(store: store)
        #expect(seeded.hasPersonalProfile == true)
    }

    @Test("deletePersonalHandwriting removes the profile and progress and updates flags")
    func deleteRemovesProfile() throws {
        let store = InMemoryProfileStore()
        try store.saveProfile(SyntheticProfile.usable())
        try store.saveProgress(CalibrationProgress(sectionIndex: 1, promptIndex: 2, savedTokens: ["a"]))

        let model = makeModel(store: store)
        #expect(model.hasPersonalProfile == true)

        model.deletePersonalHandwriting()

        // Store is cleared and the model no longer advertises a profile.
        #expect(store.loadProfile() == nil)
        #expect(store.loadProgress() == nil)
        #expect(model.hasPersonalProfile == false)
        // Personal now requires calibration again (graceful fallback).
        #expect(model.personalNeedsCalibration == true)
    }

    @Test("Deleting while Personal is selected leaves the app usable via preset fallback")
    func deleteWhileSelectedFallsBack() throws {
        let store = InMemoryProfileStore()
        try store.saveProfile(SyntheticProfile.usable())
        let model = makeModel(store: store)
        model.selectStyle(.personal)
        #expect(model.selectedStyle == .personal)

        model.deletePersonalHandwriting()
        // Selection is preserved but now flagged as needing calibration; the
        // resolver falls back to a preset so composition still works.
        #expect(model.personalNeedsCalibration == true)
        #expect(model.hasPersonalProfile == false)
    }
}
