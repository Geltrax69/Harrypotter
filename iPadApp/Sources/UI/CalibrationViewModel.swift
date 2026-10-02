import Foundation
import PencilKit
import SwiftUI

/// Drives the resumable calibration flow. Captures one prompted token at a time,
/// validates non-tiny ink on Save, tracks section/overall progress, and persists
/// both progress (for resume) and the assembled profile. Signatures are never
/// requested or stored.
@MainActor
@Observable
public final class CalibrationViewModel {
    public private(set) var sectionIndex: Int
    public private(set) var promptIndex: Int
    /// Stable prompt IDs that have a saved sample this/prior session.
    public private(set) var savedPromptIDs: Set<String>
    /// The most recent saved glyph, normalized, for the live vector preview.
    public private(set) var previewStrokes: [InkStroke] = []
    /// True when the current pad has ink big enough to save.
    public private(set) var canSaveCurrent = false
    /// A user-readable secure-storage error, set when protected persistence of
    /// the profile fails. Nil when storage is healthy. Never contains filesystem
    /// paths or low-level details — only actionable, human copy.
    public private(set) var storageError: String?

    /// The user-readable message shown when secure storage fails. Deliberately
    /// generic about the cause (no filesystem details) but actionable.
    public static let secureStorageErrorMessage =
        "Couldn’t save your handwriting securely on this device. Your last sample wasn’t kept. Try again."

    private let store: HandwritingProfileStoring
    private var builder: HandwritingProfileBuilder

    public init(store: HandwritingProfileStoring) {
        self.store = store
        let resumed = store.loadProgress() ?? CalibrationProgress()
        self.sectionIndex = min(resumed.sectionIndex, CalibrationPlan.sections.count - 1)
        self.promptIndex = resumed.promptIndex
        self.savedPromptIDs = resumed.savedPromptIDs
        self.builder = HandwritingProfileBuilder(existing: store.loadProfile())
    }

    // MARK: - Derived state

    public var sections: [CalibrationSection] { CalibrationPlan.sections }
    public var currentSection: CalibrationSection { CalibrationPlan.sections[sectionIndex] }
    public var currentPrompt: CalibrationPrompt {
        let prompts = currentSection.prompts
        return prompts[min(promptIndex, prompts.count - 1)]
    }
    /// Backwards-compatible token view for existing call sites/tests.
    public var savedTokens: Set<String> { progress.savedTokens }
    public var overallFraction: Double { progress.overallFraction }
    public var sectionFraction: Double { progress.sectionFraction() }
    public var isLastPrompt: Bool {
        sectionIndex == CalibrationPlan.sections.count - 1 &&
        promptIndex == currentSection.prompts.count - 1
    }
    public var isFirstPrompt: Bool { sectionIndex == 0 && promptIndex == 0 }

    private var progress: CalibrationProgress {
        CalibrationProgress(sectionIndex: sectionIndex, promptIndex: promptIndex, savedPromptIDs: savedPromptIDs)
    }

    // MARK: - Capture

    /// Reports the current pad drawing so Save can be gated on non-tiny ink.
    public func padChanged(_ drawing: PKDrawing) {
        canSaveCurrent = CalibrationSampleProcessor.isValidSample(drawing)
    }

    /// The outcome of attempting to save the current sample, so the view can
    /// distinguish "too small to save" from "couldn't save securely".
    public enum SaveOutcome: Equatable {
        case saved
        case tooSmall
        case storageFailed
    }

    /// Validates and saves the current token's sample, then advances.
    /// Returns false when the ink was too small OR when secure storage failed;
    /// use `saveSampleDetailed(_:)` to distinguish the two.
    @discardableResult
    public func saveSample(_ drawing: PKDrawing) -> Bool {
        saveSampleDetailed(drawing) == .saved
    }

    /// Transactional save. Stages the builder/progress changes, writes the
    /// PROFILE FIRST, and only commits in-memory success (marking the prompt
    /// saved, updating preview, persisting progress) AFTER the profile save
    /// succeeds. If protected profile persistence fails, nothing is committed:
    /// the prompt stays unsaved and a user-readable secure-storage error is
    /// surfaced. This guarantees a prompt is never marked saved when its
    /// protected profile write failed.
    @discardableResult
    public func saveSampleDetailed(_ drawing: PKDrawing) -> SaveOutcome {
        guard CalibrationSampleProcessor.isValidSample(drawing) else { return .tooSmall }
        let prompt = currentPrompt

        // Stage changes on a COPY of the builder so a failed persist leaves the
        // committed in-memory state untouched.
        var stagedBuilder = builder
        var stagedPreview: [InkStroke]? = nil
        if prompt.isPhrase {
            stagedBuilder.addPhrase(drawing: drawing)
        } else {
            stagedBuilder.setGlyph(token: prompt.token, slot: prompt.variantSlot, drawing: drawing)
            stagedPreview = CalibrationSampleProcessor.normalizeGlyph(drawing)
        }

        // PROFILE FIRST: persist protected profile before touching progress or
        // any in-memory success signal.
        do {
            try store.saveProfile(stagedBuilder.build())
        } catch {
            // Protected persistence failed: commit nothing, surface the error.
            storageError = CalibrationViewModel.secureStorageErrorMessage
            return .storageFailed
        }

        // Commit in-memory success only after the profile is durably saved.
        builder = stagedBuilder
        if let stagedPreview { previewStrokes = stagedPreview }
        savedPromptIDs.insert(prompt.promptID)
        storageError = nil
        // Progress is written after the profile; a progress failure is not
        // material to the captured ink (the profile is already durable) but is
        // surfaced so the user knows resume state may be stale.
        persist(surfaceFailure: true)
        return .saved
    }

    /// Clears any surfaced storage error (e.g. after the user acknowledges the
    /// alert), so stale error copy does not linger.
    public func clearStorageError() { storageError = nil }

    // MARK: - Navigation

    public func next() {
        let prompts = currentSection.prompts
        if promptIndex < prompts.count - 1 {
            promptIndex += 1
        } else if sectionIndex < CalibrationPlan.sections.count - 1 {
            sectionIndex += 1
            promptIndex = 0
        }
        canSaveCurrent = false
        // A progress-only persistence failure here is not material to captured
        // ink (the profile is already durable), so it must not crash or block
        // navigation; it is swallowed rather than surfaced as a secure-storage
        // error.
        persist(surfaceFailure: false)
    }

    public func previous() {
        if promptIndex > 0 {
            promptIndex -= 1
        } else if sectionIndex > 0 {
            sectionIndex -= 1
            promptIndex = currentSection.prompts.count - 1
        }
        canSaveCurrent = false
        persist(surfaceFailure: false)
    }

    /// Finalizes calibration: assembles and saves the profile. Progress is kept
    /// so the user can return and refine. A protected-write failure here is
    /// MATERIAL (the assembled profile may not be durable), so it is surfaced as
    /// a secure-storage error rather than silently swallowed — but never crashes.
    public func finish() {
        let profile = builder.build()
        do {
            try store.saveProfile(profile)
            storageError = nil
        } catch {
            storageError = CalibrationViewModel.secureStorageErrorMessage
        }
        persist(surfaceFailure: false)
    }

    /// Deletes the profile and all progress (privacy control).
    public func deleteAll() {
        try? store.deleteProfile()
        try? store.deleteProgress()
        builder = HandwritingProfileBuilder(existing: nil)
        savedPromptIDs = []
        sectionIndex = 0
        promptIndex = 0
        previewStrokes = []
        canSaveCurrent = false
        storageError = nil
    }

    /// Persists resume progress. When `surfaceFailure` is true, a failure updates
    /// `storageError` (used after a Save, where stale resume state is material);
    /// otherwise the failure is swallowed so navigation never crashes.
    private func persist(surfaceFailure: Bool) {
        do {
            try store.saveProgress(progress)
        } catch {
            if surfaceFailure && storageError == nil {
                storageError = CalibrationViewModel.secureStorageErrorMessage
            }
        }
    }
}
