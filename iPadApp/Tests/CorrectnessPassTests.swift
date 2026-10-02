import Testing
import Foundation
import CoreGraphics
import PencilKit
@testable import LivingPage

// MARK: - Correction 1: Calibration prompt IDs, variant slots, 100% reachable

@MainActor
@Suite("Calibration prompt IDs and variant slots")
struct CalibrationIDVariantTests {

    /// Advances the view model to the first prompt of a given section kind.
    private func advance(_ vm: CalibrationViewModel, toSection kind: CalibrationSectionKind) {
        while vm.currentSection.kind != kind { vm.next() }
    }

    @Test("Every plan prompt has a stable, unique promptID")
    func promptIDsUnique() {
        let ids = CalibrationPlan.allPromptIDs
        #expect(ids.count == Set(ids).count, "prompt IDs must be unique across the whole plan")
        // The same visible token in primary and variation has DISTINCT IDs.
        let lowerA = CalibrationPlan.sections
            .flatMap(\.prompts)
            .filter { $0.token == "a" }
        #expect(lowerA.count == 2, "token 'a' is prompted in primary and variation")
        #expect(Set(lowerA.map(\.promptID)).count == 2)
    }

    @Test("Primary occupies variant slot 0, variation occupies slot 1")
    func primaryAndVariationSlots() {
        let primary = CalibrationPlan.sections.first { $0.kind == .lowercasePrimary }!
        let variation = CalibrationPlan.sections.first { $0.kind == .lowercaseVariation }!
        #expect(primary.prompts.allSatisfy { $0.variantSlot == 0 })
        #expect(variation.prompts.allSatisfy { $0.variantSlot == 1 })
    }

    @Test("Primary + variation capture produce exactly two variants for a token")
    func twoVariantsExactly() {
        let store = InMemoryProfileStore()
        let vm = CalibrationViewModel(store: store)

        // Capture 'a' in the primary section (slot 0).
        advance(vm, toSection: .lowercasePrimary)
        #expect(vm.currentPrompt.token == "a")
        #expect(vm.saveSample(SyntheticSample.drawing(for: "a")))

        // Capture 'a' again in the variation section (slot 1).
        advance(vm, toSection: .lowercaseVariation)
        #expect(vm.currentPrompt.token == "a")
        #expect(vm.currentPrompt.variantSlot == 1)
        #expect(vm.saveSample(SyntheticSample.drawing(for: "a")))

        vm.finish()
        let profile = store.loadProfile()!
        let bank = profile.banks["a"]!
        #expect(bank.variants.count == 2, "primary + variation => exactly two variants")
    }

    @Test("Redoing a prompt replaces only its slot, never appends without bound")
    func redoReplacesOwnSlot() {
        let store = InMemoryProfileStore()
        let vm = CalibrationViewModel(store: store)
        advance(vm, toSection: .lowercasePrimary)
        #expect(vm.saveSample(SyntheticSample.drawing(for: "a")))
        // Redo the SAME primary prompt three more times.
        for _ in 0..<3 { #expect(vm.saveSample(SyntheticSample.drawing(for: "a"))) }
        vm.finish()
        let bank = store.loadProfile()!.banks["a"]!
        #expect(bank.variants.count == 1, "redoing slot 0 must not append; stays one variant")
    }

    @Test("Progress distinguishes primary and variation prompts of the same token")
    func progressDistinguishesSections() {
        let store = InMemoryProfileStore()
        let vm = CalibrationViewModel(store: store)
        advance(vm, toSection: .lowercasePrimary)
        _ = vm.saveSample(SyntheticSample.drawing(for: "a"))
        // Only the primary prompt is saved; the variation prompt of 'a' is not.
        let primaryID = "lowercasePrimary#0"
        let variationID = "lowercaseVariation#0"
        let saved = store.loadProgress()!.savedPromptIDs
        #expect(saved.contains(primaryID))
        #expect(!saved.contains(variationID))
    }

    @Test("Each section starts at zero fraction until its own prompts are saved")
    func sectionStartsCorrectly() {
        let store = InMemoryProfileStore()
        // Save all primary lowercase, then land the resume at the variation section.
        let vm = CalibrationViewModel(store: store)
        advance(vm, toSection: .lowercaseVariation)
        // At the start of the variation section nothing there is saved yet, even
        // if the same tokens exist in primary.
        #expect(vm.sectionFraction == 0)
    }

    @Test("100% overall is reachable by covering every prompt (primary+variation)")
    func fullProgressReachable() {
        let store = InMemoryProfileStore()
        let vm = CalibrationViewModel(store: store)
        // Walk the entire plan, saving a sample for every prompt exactly once.
        // Use a guaranteed-valid (non-tiny) drawing for every glyph prompt so the
        // test measures progress reachability, not glyph fidelity — some tokens
        // (e.g. ".") have intrinsically tiny authored ink.
        var guardCount = 0
        while guardCount < 500 {
            guardCount += 1
            let prompt = vm.currentPrompt
            let drawing = prompt.isPhrase ? SyntheticSample.phrase() : SyntheticDrawing.line(length: 200)
            _ = vm.saveSample(drawing)
            if vm.isLastPrompt { break }
            vm.next()
        }
        #expect(abs(vm.overallFraction - 1.0) < 1e-9, "overall=\(vm.overallFraction) saved=\(vm.savedPromptIDs.count) total=\(CalibrationPlan.allPromptIDs.count) missing=\(Set(CalibrationPlan.allPromptIDs).subtracting(vm.savedPromptIDs).sorted())")
    }

    @Test("Legacy v1 savedTokens migrate to ONLY primary prompt IDs (safe)")
    func v1Migration() throws {
        // Encode a v1-style progress payload with savedTokens and no savedPromptIDs.
        let legacy = """
        {"version":1,"sectionIndex":0,"promptIndex":0,"savedTokens":["a","b"]}
        """.data(using: .utf8)!
        let migrated = try JSONDecoder().decode(CalibrationProgress.self, from: legacy)
        #expect(migrated.version == CalibrationProgress.currentVersion)
        // SAFE migration: each legacy token credits ONLY its primary prompt, not
        // the variation prompt. 'a' and 'b' => exactly 2 prompt IDs, both primary.
        #expect(migrated.savedPromptIDs.count == 2)
        #expect(migrated.savedPromptIDs.contains("lowercasePrimary#0"))   // 'a'
        #expect(migrated.savedPromptIDs.contains("lowercasePrimary#1"))   // 'b'
        #expect(!migrated.savedPromptIDs.contains("lowercaseVariation#0")) // 'a' variation NOT claimed
        #expect(!migrated.savedPromptIDs.contains("lowercaseVariation#1")) // 'b' variation NOT claimed
        // The token view still reports the visible tokens.
        #expect(migrated.savedTokens == ["a", "b"])
    }

    @Test("Legacy 'a' marks lowercasePrimary saved, lowercaseVariation unsaved, progress not inflated")
    func v1MigrationDoesNotInflateVariation() throws {
        // An old one-variant profile: exactly one token captured, no pass info.
        let legacy = """
        {"version":1,"sectionIndex":0,"promptIndex":0,"savedTokens":["a"]}
        """.data(using: .utf8)!
        let migrated = try JSONDecoder().decode(CalibrationProgress.self, from: legacy)
        // Primary 'a' is credited; the variation 'a' is NOT — the user must still
        // complete the natural-variation pass.
        #expect(migrated.savedPromptIDs.contains("lowercasePrimary#0"))
        #expect(!migrated.savedPromptIDs.contains("lowercaseVariation#0"))
        // Exactly one prompt credited; overall progress reflects one of N prompts,
        // never doubled by a phantom variation credit.
        #expect(migrated.savedPromptIDs.count == 1)
        let total = CalibrationPlan.allPromptIDs.count
        #expect(abs(migrated.overallFraction - 1.0 / Double(total)) < 1e-9,
                "overall must be exactly 1/\(total), not inflated to 2/\(total)")
    }
}

// MARK: - Correction 2: Durable resume

@MainActor
@Suite("Durable resume")
struct DurableResumeTests {

    @Test("A single saved sample persists the partial profile immediately")
    func profileSavedAfterEverySample() {
        let store = InMemoryProfileStore()
        let vm = CalibrationViewModel(store: store)
        let token = vm.currentPrompt.token
        #expect(store.loadProfile() == nil)
        _ = vm.saveSample(SyntheticSample.drawing(for: token))
        // Durable: the profile exists WITHOUT calling finish()/Close/Done.
        let profile = store.loadProfile()
        #expect(profile != nil)
        #expect(profile?.banks[token] != nil)
    }

    @Test("A fresh view model resumes geometry, variants, and progress from the store")
    func resumeSurvivesRelaunch() {
        let store = InMemoryProfileStore()
        do {
            let vm = CalibrationViewModel(store: store)
            let token = vm.currentPrompt.token
            _ = vm.saveSample(SyntheticSample.drawing(for: token))
            // Simulate swipe-dismiss/crash: no finish() call.
        }
        // Relaunch: a brand-new view model over the SAME store.
        let resumed = CalibrationViewModel(store: store)
        #expect(!resumed.savedPromptIDs.isEmpty, "progress survived")
        let profile = store.loadProfile()
        #expect(profile != nil, "captured bank survived")
        // Geometry survived: the resumed builder can rebuild the same bank.
        let firstToken = CalibrationPlan.sections[0].prompts[0].token
        #expect(profile?.banks[firstToken]?.variants.first?.strokes.isEmpty == false)
    }

    @Test("Resuming and saving a glyph does not overwrite existing metrics with defaults")
    func metricsPreservedOnResume() throws {
        let store = InMemoryProfileStore()
        // Seed a profile with distinctive, non-default metrics.
        var seeded = SyntheticProfile.usable()
        seeded.metrics.slant = 0.33
        seeded.metrics.lineHeight = 1.77
        try store.saveProfile(seeded)

        // Resume and save one more (non-phrase) glyph, then finalize.
        let vm = CalibrationViewModel(store: store)
        _ = vm.saveSample(SyntheticSample.drawing(for: vm.currentPrompt.token))
        vm.finish()

        let after = store.loadProfile()!
        #expect(abs(after.metrics.slant - 0.33) < 1e-9, "slant must be preserved, got \(after.metrics.slant)")
        #expect(abs(after.metrics.lineHeight - 1.77) < 1e-9, "lineHeight must be preserved")
    }

    @Test("A throwing profile store makes Save fail, leaves the prompt unsaved, and surfaces secure-storage copy")
    func throwingProfileStoreFailsTransactionally() {
        let store = ThrowingProfileStore(failProfileSaves: true, profileError: .protectedWriteUnavailable)
        let vm = CalibrationViewModel(store: store)
        let prompt = vm.currentPrompt
        // Valid, non-tiny ink — the failure is storage, not "too small".
        let outcome = vm.saveSampleDetailed(SyntheticSample.drawing(for: prompt.token))
        #expect(outcome == .storageFailed, "protected profile write must return failure")
        // The prompt is NOT marked saved when profile persistence failed.
        #expect(!vm.savedPromptIDs.contains(prompt.promptID))
        #expect(vm.savedTokens.isEmpty)
        // No durable profile was written.
        #expect(store.loadProfile() == nil)
        // A user-readable secure-storage message is exposed (no filesystem detail).
        let message = try! #require(vm.storageError)
        #expect(message == CalibrationViewModel.secureStorageErrorMessage)
        #expect(!message.lowercased().contains("/"), "must not expose filesystem paths")
        #expect(!message.lowercased().contains("file"), "must not expose filesystem details")
    }

    @Test("Save returns false and the too-small path is distinct from storage failure")
    func tooSmallIsDistinctFromStorageFailure() {
        let store = ThrowingProfileStore(failProfileSaves: true)
        let vm = CalibrationViewModel(store: store)
        // Tiny ink: too small, NOT a storage failure — no storage error surfaced.
        #expect(vm.saveSampleDetailed(SyntheticDrawing.tinyDot()) == .tooSmall)
        #expect(vm.storageError == nil)
    }

    @Test("The successful path remains durable and clears any prior storage error")
    func successfulPathDurable() {
        // Start failing, prove failure, then recover and prove durability.
        let store = ThrowingProfileStore(failProfileSaves: true)
        let vm = CalibrationViewModel(store: store)
        let prompt = vm.currentPrompt
        #expect(vm.saveSampleDetailed(SyntheticSample.drawing(for: prompt.token)) == .storageFailed)
        #expect(vm.storageError != nil)

        // Storage recovers.
        store.failProfileSaves = false
        #expect(vm.saveSampleDetailed(SyntheticSample.drawing(for: prompt.token)) == .saved)
        #expect(vm.storageError == nil, "a successful save clears the prior error")
        #expect(vm.savedPromptIDs.contains(prompt.promptID))
        // Durable: the profile is persisted and carries the captured bank.
        let profile = try! #require(store.loadProfile())
        #expect(profile.banks[prompt.token] != nil)
    }

    @Test("finish() surfaces a material protected-write failure without crashing")
    func finishSurfacesFailure() {
        let store = ThrowingProfileStore(failProfileSaves: true)
        let vm = CalibrationViewModel(store: store)
        vm.finish() // must not crash
        #expect(vm.storageError == CalibrationViewModel.secureStorageErrorMessage)
    }

    @Test("next()/previous() never crash on a throwing store and do not surface progress-only failures")
    func navigationDoesNotCrashOrSurface() {
        // A store that also fails progress writes.
        let store = ThrowingProfileStore(failProfileSaves: false)
        let vm = CalibrationViewModel(store: store)
        vm.next()      // must not crash
        vm.previous()  // must not crash
        // Progress-only churn is not surfaced as a secure-storage error here.
        #expect(vm.storageError == nil)
    }
}

// MARK: - Correction 3: Full PencilKit metadata round-trip

@Suite("PencilKit metadata round-trip")
struct PencilKitMetadataTests {

    @Test("InkStroke retains randomSeed, renderGroupID, and grain offset through Codable")
    func codableRoundTrip() throws {
        let group = UUID()
        let stroke = InkStroke(
            points: [InkPoint(x: 0, y: 0), InkPoint(x: 1, y: -1)],
            randomSeed: 0xDEAD_BEEF,
            renderGroupID: group,
            renderStateGrainOffset: CGPoint(x: 3.5, y: -2.25)
        )
        let data = try JSONEncoder().encode(stroke)
        let decoded = try JSONDecoder().decode(InkStroke.self, from: data)
        #expect(decoded.randomSeed == 0xDEAD_BEEF)
        #expect(decoded.renderGroupID == group)
        #expect(decoded.renderStateGrainOffset == CGPoint(x: 3.5, y: -2.25))
        #expect(decoded == stroke)
    }

    @Test("Old encoded strokes without metadata decode with safe defaults")
    func backwardDecoding() throws {
        // A legacy encoding: only "points", no metadata keys.
        let legacy = """
        {"points":[{"x":0,"y":0,"timeOffset":0,"force":1,"azimuth":0,"altitude":1.5707963267948966,"opacity":1,"size":1,"secondaryScale":1,"threshold":0,"lateralJitter":0}]}
        """.data(using: .utf8)!
        let decoded = try JSONDecoder().decode(InkStroke.self, from: legacy)
        #expect(decoded.randomSeed == 0)
        #expect(decoded.renderGroupID == nil)
        #expect(decoded.renderStateGrainOffset == nil)
    }

    @Test("randomSeed round-trips to the reconstructed PKStroke")
    func pkStrokeRandomSeed() throws {
        let stroke = InkStroke(
            points: [InkPoint(x: 0, y: 0, timeOffset: 0), InkPoint(x: 10, y: -10, timeOffset: 0.1)],
            randomSeed: 12345
        )
        let pk = try #require(InkStrokeBuilder.stroke(from: stroke))
        #expect(pk.randomSeed == 12345)
    }

    @Test("renderGroupID and renderState grain offset round-trip through PKStroke")
    func pkStrokeRenderGroupAndState() throws {
        guard #available(iOS 27.0, *) else { return }
        let group = UUID()
        let stroke = InkStroke(
            points: [InkPoint(x: 0, y: 0), InkPoint(x: 5, y: -5)],
            randomSeed: 7,
            renderGroupID: group,
            renderStateGrainOffset: CGPoint(x: 2, y: 4)
        )
        let pk = try #require(InkStrokeBuilder.stroke(from: stroke))
        #expect(pk.renderGroupID == group)
        #expect(pk.renderState?.grainOffset == CGPoint(x: 2, y: 4))
    }

    @Test("InkStroke preserves the FULL PKStroke.RenderState through Codable round-trip")
    func fullRenderStateCodableRoundTrip() throws {
        guard #available(iOS 27.0, *) else { return }
        let group = UUID()
        // A full render state value (observable grain offset + whatever opaque
        // state the type carries) is stored whole, not reduced to a grain pair.
        let state = PKStroke.RenderState(grainOffset: CGPoint(x: 9.5, y: -4.25))
        let stroke = InkStroke(
            points: [InkPoint(x: 0, y: 0, force: 0.4), InkPoint(x: 2, y: -3, force: 0.9)],
            randomSeed: 0xCAFE_BABE,
            renderGroupID: group,
            renderState: state
        )
        let data = try JSONEncoder().encode(stroke)
        let decoded = try JSONDecoder().decode(InkStroke.self, from: data)
        // The full render state survives verbatim (Equatable over the whole type).
        #expect(decoded.renderState == state)
        #expect(decoded.renderState?.grainOffset == CGPoint(x: 9.5, y: -4.25))
        #expect(decoded.randomSeed == 0xCAFE_BABE)
        #expect(decoded.renderGroupID == group)
        #expect(decoded == stroke, "the whole InkStroke, including full render state, round-trips")
    }

    @Test("Reconstructed PKStroke carries the exact FULL render state value")
    func pkStrokeFullRenderStateEquality() throws {
        guard #available(iOS 27.0, *) else { return }
        let group = UUID()
        let state = PKStroke.RenderState(grainOffset: CGPoint(x: 3.5, y: 6))
        let stroke = InkStroke(
            points: [InkPoint(x: 0, y: 0), InkPoint(x: 8, y: -2)],
            randomSeed: 4242,
            renderGroupID: group,
            renderState: state
        )
        let pk = try #require(InkStrokeBuilder.stroke(from: stroke))
        // The reconstructed PKStroke's render state equals the exact source value.
        #expect(pk.renderState == state)
        #expect(pk.renderGroupID == group)
        #expect(pk.randomSeed == 4242)
        // And a nil render state reconstructs as nil (default rendering).
        let plain = InkStroke(points: [InkPoint(x: 0, y: 0), InkPoint(x: 1, y: -1)], randomSeed: 1)
        let pkPlain = try #require(InkStrokeBuilder.stroke(from: plain))
        #expect(pkPlain.renderState == nil)
    }

    @Test("normalizeGlyph preserves per-point dynamics: force, timing, tilt, size variation")
    func normalizePreservesDynamics() throws {
        // Build a PKDrawing whose points carry varied force/timing/tilt/size.
        let ink = PKInk(.pen, color: .black)
        let pts = (0..<6).map { i -> PKStrokePoint in
            PKStrokePoint(
                location: CGPoint(x: 40 + CGFloat(i) * 20, y: 200 - CGFloat(i) * 15),
                timeOffset: TimeInterval(i) * 0.05,
                size: CGSize(width: 3 + CGFloat(i), height: 3 + CGFloat(i)), // varied size
                opacity: 0.8,
                force: 0.2 + CGFloat(i) * 0.1,
                azimuth: 0.3,
                altitude: 1.1
            )
        }
        let drawing = PKDrawing(strokes: [PKStroke(ink: ink, path: PKStrokePath(controlPoints: pts, creationDate: Date()))])
        let strokes = CalibrationSampleProcessor.normalizeGlyph(drawing)
        let stroke = try #require(strokes.first)
        // Timing is preserved verbatim.
        #expect(abs(stroke.points.first!.timeOffset - 0.0) < 1e-9)
        #expect(stroke.points.last!.timeOffset > stroke.points.first!.timeOffset)
        // Force preserved (not flattened to a constant).
        let forces = Set(stroke.points.map { ($0.force * 1000).rounded() })
        #expect(forces.count > 1, "force must vary across points, not be constant")
        // Tilt preserved.
        #expect(abs(stroke.points.first!.altitude - 1.1) < 0.05)
        // Size is meaningful/varies, not a flat 1 for every point.
        let sizes = Set(stroke.points.map { ($0.size * 1000).rounded() })
        #expect(sizes.count > 1, "size must vary across points, not all be 1")
    }
}

// MARK: - Correction 4: Phase truth

@MainActor
@Suite("Phase truth: rendering until complete")
struct PhaseTruthTests {

    private func makeModel(pointsPerFrame: Double) -> PageViewModel {
        PageViewModel(
            recognizer: DeterministicRecognizer(text: "hello"),
            answerClient: DeterministicAnswerClient(answer: "a living page answers in ink over several strokes"),
            locale: .en,
            debounce: .milliseconds(10),
            styleSettings: StyleSettings(store: InMemoryKeyValueStore()),
            profileStore: InMemoryProfileStore(),
            // A slow reveal so we can observe the .rendering window.
            animator: AnswerInkAnimator(frameInterval: .milliseconds(12), pointsPerFrame: pointsPerFrame)
        )
    }

    @Test("Phase stays .rendering while the reveal is incomplete")
    func rendersWhileIncomplete() async throws {
        let m = makeModel(pointsPerFrame: 0.4) // slow
        m.updatePageWidth(500)
        m.drawingChanged(SyntheticDrawing.line())
        try await waitUntil { if case .confirming = m.phase { return true }; return false }
        m.askKiro()
        // Wait until ink begins to appear (reveal started).
        try await waitUntil { !m.animator.drawing.strokes.isEmpty }
        // While incomplete, the phase must NOT be .answered yet.
        #expect(!m.animator.isComplete)
        if case .answered = m.phase {
            Issue.record("phase reached .answered before the reveal completed")
        }
    }

    @Test("Phase becomes .answered only after the reveal completes")
    func answeredOnlyAfterComplete() async throws {
        let m = makeModel(pointsPerFrame: 6)
        m.updatePageWidth(500)
        m.drawingChanged(SyntheticDrawing.line())
        try await waitUntil { if case .confirming = m.phase { return true }; return false }
        m.askKiro()
        try await waitUntil { if case .answered = m.phase { return true }; return false }
        // On reaching .answered, the animator must actually be complete.
        #expect(m.animator.isComplete)
    }

    @Test("Clear during render stays blank and never flips to answered")
    func clearDuringRenderStaysBlank() async throws {
        let m = makeModel(pointsPerFrame: 0.4) // slow so we can clear mid-reveal
        m.updatePageWidth(500)
        m.drawingChanged(SyntheticDrawing.line())
        try await waitUntil { if case .confirming = m.phase { return true }; return false }
        m.askKiro()
        try await waitUntil { !m.animator.drawing.strokes.isEmpty }
        m.clear()
        #expect(m.phase == .blank)
        #expect(m.animator.drawing.strokes.isEmpty)
        // Give any stale completion a chance to (wrongly) fire; it must not.
        try await Task.sleep(for: .milliseconds(120))
        #expect(m.phase == .blank)
        #expect(m.animator.drawing.strokes.isEmpty)
    }
}

// MARK: - Correction 5: Answer layout clamping

@MainActor
@Suite("Answer layout clamping")
struct AnswerLayoutTests {

    @Test("A question near the right edge cannot push the answer offscreen")
    func rightEdgeQuestionClamped() {
        let pageWidth: CGFloat = 500
        // Question ink starts far to the right.
        let layout = PageViewModel.answerLayout(pageWidth: pageWidth, questionMinX: 460)
        // Origin is clamped so at least the minimum usable width remains.
        #expect(layout.originX <= pageWidth - 24 - 120 + 0.001)
        #expect(layout.width >= 120)
        // Answer stays within the page.
        #expect(layout.originX + layout.width <= pageWidth - 24 + 0.001)
    }

    @Test("A left-edge question uses the full available width")
    func leftEdgeQuestion() {
        let layout = PageViewModel.answerLayout(pageWidth: 500, questionMinX: 24)
        #expect(abs(layout.originX - 24) < 0.001)
        #expect(abs(layout.width - 452) < 0.001) // 500 - 24 (left) - 24 (right)
    }

    @Test("A blank question defaults to the left inset")
    func blankQuestion() {
        let layout = PageViewModel.answerLayout(pageWidth: 500, questionMinX: nil)
        #expect(layout.originX == 24)
    }

    @Test("Content width tracked by the scroll coordinator so offsets are not clamped")
    func coordinatorContentWidth() {
        let sync = ScrollSyncCoordinator()
        #expect(sync.contentWidth > 0) // sensible default before layout
        sync.updateContentWidth(834)
        #expect(sync.contentWidth == 834)
    }
}

// MARK: - Correction 6: Profile protection fallback policy

@Suite("Profile protection policy")
struct ProfileProtectionTests {

    @Test("An injected test directory permits writes (documented fallback)")
    func injectedDirectoryWrites() throws {
        let dir = FileManager.default.temporaryDirectory
            .appendingPathComponent("prot-\(UUID().uuidString)", isDirectory: true)
        defer { try? FileManager.default.removeItem(at: dir) }
        let store = FileHandwritingProfileStore(directory: dir)
        // Writing succeeds in a test directory (fallback allowed here).
        try store.saveProfile(SyntheticProfile.usable())
        #expect(store.loadProfile() != nil)
    }

    @Test("The profile directory itself is excluded from backup and protected")
    func directoryProtected() throws {
        let dir = FileManager.default.temporaryDirectory
            .appendingPathComponent("prot-\(UUID().uuidString)", isDirectory: true)
        defer { try? FileManager.default.removeItem(at: dir) }
        let store = FileHandwritingProfileStore(directory: dir)
        try store.saveProfile(SyntheticProfile.usable())
        // The directory exists and is excluded from backup.
        let values = try dir.resourceValues(forKeys: [.isExcludedFromBackupKey])
        #expect(values.isExcludedFromBackup == true)
    }

    @Test("protectedWriteUnavailable is a distinct, documented error case")
    func distinctErrorCase() {
        #expect(ProfileStoreError.protectedWriteUnavailable != ProfileStoreError.writeFailed)
        #expect(ProfileStoreError.protectedWriteUnavailable != ProfileStoreError.encodingFailed)
    }
}
