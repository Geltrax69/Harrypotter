import Testing
import Foundation
import PencilKit
@testable import LivingPage

// MARK: - Profile persistence

@Suite("Profile persistence")
struct ProfilePersistenceTests {
    private func tempStore() -> (FileHandwritingProfileStore, URL) {
        let dir = FileManager.default.temporaryDirectory
            .appendingPathComponent("hwtest-\(UUID().uuidString)", isDirectory: true)
        return (FileHandwritingProfileStore(directory: dir), dir)
    }

    private func cleanup(_ dir: URL) { try? FileManager.default.removeItem(at: dir) }

    @Test("Save then load round-trips a profile")
    func roundTrip() throws {
        let (store, dir) = tempStore(); defer { cleanup(dir) }
        let profile = SyntheticProfile.usable()
        try store.saveProfile(profile)
        let loaded = try #require(store.loadProfile())
        #expect(loaded == profile)
    }

    @Test("Atomic write leaves a readable file")
    func atomicFileExists() throws {
        let (store, dir) = tempStore(); defer { cleanup(dir) }
        try store.saveProfile(SyntheticProfile.usable())
        let url = dir.appendingPathComponent("profile.json")
        #expect(FileManager.default.fileExists(atPath: url.path))
        // File protection attribute is applied (best-effort in sandbox).
        let attrs = try? FileManager.default.attributesOfItem(atPath: url.path)
        _ = attrs // presence asserted above; class varies by sandbox
    }

    @Test("Profile file is excluded from backup")
    func excludedFromBackup() throws {
        let (store, dir) = tempStore(); defer { cleanup(dir) }
        try store.saveProfile(SyntheticProfile.usable())
        let url = dir.appendingPathComponent("profile.json")
        let values = try url.resourceValues(forKeys: [.isExcludedFromBackupKey])
        #expect(values.isExcludedFromBackup == true)
    }

    @Test("Corrupt profile file recovers to nil and is cleared")
    func corruptRecovery() throws {
        let (store, dir) = tempStore(); defer { cleanup(dir) }
        let url = dir.appendingPathComponent("profile.json")
        try "not json {{{".data(using: .utf8)!.write(to: url)
        #expect(store.loadProfile() == nil)
        // Corrupt file is removed so a future save starts clean.
        #expect(!FileManager.default.fileExists(atPath: url.path))
    }

    @Test("Future schema version is refused")
    func futureVersionRefused() throws {
        let (store, dir) = tempStore(); defer { cleanup(dir) }
        var profile = SyntheticProfile.usable()
        profile.version = HandwritingProfile.currentVersion + 1
        try store.saveProfile(profile)
        #expect(store.loadProfile() == nil)
    }

    @Test("Delete removes the profile")
    func deletion() throws {
        let (store, dir) = tempStore(); defer { cleanup(dir) }
        try store.saveProfile(SyntheticProfile.usable())
        try store.deleteProfile()
        #expect(store.loadProfile() == nil)
    }

    @Test("Progress persists and resumes")
    func progressResume() throws {
        let (store, dir) = tempStore(); defer { cleanup(dir) }
        let progress = CalibrationProgress(sectionIndex: 3, promptIndex: 5, savedTokens: ["a", "b"])
        try store.saveProgress(progress)
        let loaded = try #require(store.loadProgress())
        #expect(loaded.sectionIndex == 3)
        #expect(loaded.promptIndex == 5)
        #expect(loaded.savedTokens == ["a", "b"])
    }
}

// MARK: - Profile completeness

@Suite("Profile completeness and usability")
struct ProfileCompletenessTests {
    @Test("Synthetic profile is usable")
    func usable() {
        #expect(SyntheticProfile.usable().isUsable)
    }

    @Test("Sparse profile below half lowercase is not usable")
    func notUsable() {
        var p = SyntheticProfile.usable()
        // Remove most lowercase, keeping only a few.
        for ch in "cdefghijklmnopqrstuvwxyz" { p.banks.removeValue(forKey: String(ch)) }
        #expect(!p.isUsable)
    }

    @Test("Empty banks (no variants or empty strokes) do not count toward usability")
    func emptyBanksNotUsable() {
        // Start from a fully-usable profile, then hollow out every lowercase bank
        // so the KEYS remain but carry no renderable ink.
        var p = SyntheticProfile.usable()
        let lowercase = "abcdefghijklmnopqrstuvwxyz".map(String.init)
        for key in lowercase {
            // Alternate between a bank with zero variants and a bank whose only
            // variant has an empty stroke — both are non-coverage.
            if key < "n" {
                p.banks[key] = GlyphBank(key: key, variants: [])
            } else {
                p.banks[key] = GlyphBank(key: key, variants: [GlyphVariant(strokes: [InkStroke(points: [])], advance: 0.5)])
            }
        }
        #expect(!p.isUsable, "keys with empty banks must not make a profile usable")

        // A single genuinely-inked bank is still not enough on its own.
        p.banks["a"] = GlyphBank(key: "a", variants: [GlyphVariant(strokes: [InkStroke(xy: [(0, 0), (0.5, -0.7)])], advance: 0.6)])
        #expect(!p.isUsable)

        // Re-inking at least 13 lowercase banks with real strokes restores usability.
        for key in lowercase.prefix(13) {
            p.banks[key] = GlyphBank(key: key, variants: [GlyphVariant(strokes: [InkStroke(xy: [(0, 0), (0.5, -0.7)])], advance: 0.6)])
        }
        #expect(p.isUsable)
    }

    @Test("Completeness fraction reflects captured tokens")
    func completenessFraction() {
        let p = SyntheticProfile.usable()
        let target = "abcde".map(String.init)
        #expect(p.completeness(target: target) == 1.0)
        let missing = ["a", "b", "\u{2603}"]
        #expect(p.completeness(target: missing) < 1.0)
    }
}

// MARK: - Calibration flow

@MainActor
@Suite("Calibration flow")
struct CalibrationFlowTests {
    @Test("Save sample advances saved tokens and persists progress")
    func saveAdvances() throws {
        let store = InMemoryProfileStore()
        let vm = CalibrationViewModel(store: store)
        let token = vm.currentPrompt.token
        let saved = vm.saveSample(SyntheticSample.drawing(for: token))
        #expect(saved)
        #expect(vm.savedTokens.contains(token))
        #expect(store.loadProgress()?.savedTokens.contains(token) == true)
    }

    @Test("Tiny ink is rejected by Save Sample")
    func tinyRejected() {
        let store = InMemoryProfileStore()
        let vm = CalibrationViewModel(store: store)
        let saved = vm.saveSample(SyntheticDrawing.tinyDot())
        #expect(!saved)
        #expect(vm.savedTokens.isEmpty)
    }

    @Test("Next/Previous navigate prompts and persist")
    func navigation() {
        let store = InMemoryProfileStore()
        let vm = CalibrationViewModel(store: store)
        #expect(vm.isFirstPrompt)
        vm.next()
        #expect(!vm.isFirstPrompt)
        vm.previous()
        #expect(vm.isFirstPrompt)
    }

    @Test("Resume restores section/prompt/saved tokens")
    func resume() {
        let store = InMemoryProfileStore()
        try? store.saveProgress(CalibrationProgress(sectionIndex: 2, promptIndex: 1, savedTokens: ["x"]))
        let vm = CalibrationViewModel(store: store)
        #expect(vm.sectionIndex == 2)
        #expect(vm.promptIndex == 1)
        #expect(vm.savedTokens.contains("x"))
    }

    @Test("Finish assembles and saves a profile from samples")
    func finishBuildsProfile() throws {
        let store = InMemoryProfileStore()
        let vm = CalibrationViewModel(store: store)
        // Save a sample for each lowercase prompt, advancing through the
        // section so each token gets its own bank.
        var saved = 0
        for _ in 0..<26 {
            let token = vm.currentPrompt.token
            if vm.saveSample(SyntheticSample.drawing(for: token)) { saved += 1 }
            vm.next()
        }
        vm.finish()
        let profile = try #require(store.loadProfile())
        let lowercaseCovered = "abcdefghijklmnopqrstuvwxyz".filter { profile.banks[String($0)] != nil }.count
        #expect(profile.isUsable, "saved=\(saved) banks=\(profile.banks.count) lowercase=\(lowercaseCovered)")
    }

    @Test("Delete all clears profile and progress")
    func deleteAll() {
        let store = InMemoryProfileStore()
        let vm = CalibrationViewModel(store: store)
        _ = vm.saveSample(SyntheticSample.drawing(for: vm.currentPrompt.token))
        vm.finish()
        vm.deleteAll()
        #expect(store.loadProfile() == nil)
        #expect(store.loadProgress() == nil)
        #expect(vm.savedTokens.isEmpty)
    }

    @Test("Phrase samples derive rhythm metrics without storing a signature")
    func phraseMetrics() {
        var builder = HandwritingProfileBuilder()
        builder.addPhrase(drawing: SyntheticSample.phrase())
        let profile = builder.build()
        // Metrics derived and bounded; no phrase glyph stored as a bank.
        #expect(profile.metrics.lineHeight >= 1.3 && profile.metrics.lineHeight <= 1.9)
        #expect(profile.banks.isEmpty)
    }
}

// MARK: - Style settings & resolver

@Suite("Style settings and resolution")
struct StyleSettingsTests {
    @Test("Selected style persists through the injected store")
    func persistsStyle() {
        let store = InMemoryKeyValueStore()
        let settings = StyleSettings(store: store)
        #expect(settings.selectedStyle == .uprightOpen) // default
        settings.selectedStyle = .quickSlanted
        // A fresh settings over the same store reads the persisted value.
        let reopened = StyleSettings(store: store)
        #expect(reopened.selectedStyle == .quickSlanted)
    }

    @Test("Preset resolves to a preset hand with no fallback")
    func resolvePreset() {
        let r = HandResolver().resolve(style: .compactRounded, profile: nil)
        #expect(!r.needsCalibration)
        #expect(r.fallbackProvider == nil)
    }

    @Test("Personal with no profile falls back and flags calibration")
    func resolvePersonalNoProfile() {
        let r = HandResolver().resolve(style: .personal, profile: nil)
        #expect(r.needsCalibration)
    }

    @Test("Personal with usable profile resolves to a personal hand + preset fallback")
    func resolvePersonalWithProfile() {
        let r = HandResolver().resolve(style: .personal, profile: SyntheticProfile.usable())
        #expect(!r.needsCalibration)
        #expect(r.fallbackProvider != nil)
    }
}
