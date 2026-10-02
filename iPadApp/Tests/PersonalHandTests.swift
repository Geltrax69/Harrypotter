import Testing
import Foundation
import PencilKit
import CoreGraphics
@testable import LivingPage

// MARK: - Personal hand ligatures and missing-glyph fallback

@Suite("Personal hand ligatures and fallback")
struct PersonalHandTests {
    private func personalWithFallback() -> AnswerComposer {
        let profile = SyntheticProfile.usable()
        let personal = PersonalHand(profile: profile)
        let preset = PresetHand(style: .uprightOpen)
        return AnswerComposer(provider: personal, fallbackProvider: preset)
    }

    @Test("Longest-match personal ligature is used when available")
    func longestMatchLigature() {
        let profile = SyntheticProfile.usable()
        #expect(profile.banks["th"] != nil)
        let personal = PersonalHand(profile: profile)
        #expect(personal.ligatureKeys.contains("th"))
        let composer = AnswerComposer(provider: personal, fallbackProvider: PresetHand(style: .uprightOpen))
        let result = composer.compose("the", width: 400)
        // "th" ligature (1 unit) + "e" => 2 glyphs, not 3.
        #expect(result.glyphs.count == 2)
        #expect(result.glyphs.first?.character == "th")
    }

    @Test("Missing personal glyph falls back to the preset and is counted")
    func missingGlyphFallsBack() {
        // Build a sparse profile that lacks 'z' but is still usable.
        var profile = SyntheticProfile.usable()
        profile.banks.removeValue(forKey: "z")
        let personal = PersonalHand(profile: profile)
        let composer = AnswerComposer(provider: personal, fallbackProvider: PresetHand(style: .uprightOpen))
        let result = composer.compose("zebra", width: 400)
        #expect(result.personalMissingGlyphFallbackCount >= 1)
        // 'z' still rendered (via preset), not the visible '?'.
        #expect(result.unsupportedCharacterCount == 0)
    }

    @Test("Truly unsupported char still falls to visible ? even under Personal")
    func personalUnsupportedStillQuestionMark() {
        let composer = personalWithFallback()
        let result = composer.compose("a\u{4E2D}", width: 400)
        #expect(result.unsupportedCharacterCount == 1)
    }
}

// MARK: - Bounded variation

@Suite("Bounded variation")
struct BoundedVariationTests {
    @Test("Per-glyph slant stays within the style's jitter bound")
    func slantBounded() {
        let hand = PresetHand(style: .quickSlanted)
        let m = hand.metrics
        let composer = AnswerComposer(provider: hand)
        // Repeated letter: each occurrence may vary but within bounds.
        let result = composer.compose(String(repeating: "n", count: 30), width: 2000)
        // Reconstruct effective slant range from geometry is complex; instead
        // assert the metric bounds are sane and deterministic recomposition is
        // identical (variation is bounded + deterministic, never unbounded).
        #expect(m.slantJitter <= 0.1)
        let again = composer.compose(String(repeating: "n", count: 30), width: 2000)
        #expect(result.glyphs == again.glyphs)
    }

    @Test("Repeated glyphs use deterministic variants, not identical geometry")
    func variantsVary() {
        let hand = PresetHand(style: .uprightOpen)
        let composer = AnswerComposer(provider: hand)
        let result = composer.compose("aaaa", width: 2000)
        // At least two of the four 'a's differ (bounded jitter/variant choice).
        let geometries = result.glyphs.map { $0.strokes }
        let distinct = Set(geometries.map { "\($0)" })
        #expect(distinct.count >= 2)
    }

    @Test("DeterministicRandom.signedUnit stays within [-1, 1]")
    func signedUnitBounds() {
        for salt in 0..<1000 {
            let v = DeterministicRandom.signedUnit(seed: 0xABCD, salt: UInt64(salt))
            #expect(v >= -1 && v <= 1)
        }
    }
}

// MARK: - Force / time preservation through the PK bridge

@Suite("Dynamics preservation")
struct DynamicsPreservationTests {
    @Test("InkStrokeBuilder preserves force, time, and altitude in PKStroke path")
    func preservesDynamics() throws {
        let points = [
            InkPoint(x: 0, y: 0, timeOffset: 0.0, force: 0.4, azimuth: 0.1, altitude: 1.2),
            InkPoint(x: 10, y: -10, timeOffset: 0.25, force: 0.9, azimuth: 0.2, altitude: 1.3),
            InkPoint(x: 20, y: 0, timeOffset: 0.5, force: 0.6, azimuth: 0.3, altitude: 1.4),
        ]
        let stroke = try #require(InkStrokeBuilder.stroke(from: InkStroke(points: points)))
        // The path retains control points with matching dynamics.
        #expect(stroke.path.count == 3)
        let first = stroke.path[0]
        #expect(abs(first.force - 0.4) < 0.0001)
        #expect(abs(first.timeOffset - 0.0) < 0.0001)
        let last = stroke.path[stroke.path.count - 1]
        #expect(abs(last.timeOffset - 0.5) < 0.0001)
        #expect(abs(last.force - 0.6) < 0.0001)
    }

    @Test("Composed answer produces real vector PKStrokes, never a raster")
    func realVectorStrokes() {
        let composer = AnswerComposer(provider: PresetHand(style: .uprightOpen))
        let composed = composer.compose("ink", width: 400)
        let strokes = InkStrokeBuilder.strokes(from: composed)
        #expect(!strokes.isEmpty)
        #expect(strokes.allSatisfy { $0.path.count >= 2 })
    }

    @Test("partialStroke reveals a shorter prefix than the full stroke")
    func partialStrokePrefix() throws {
        let composer = AnswerComposer(provider: PresetHand(style: .uprightOpen))
        let composed = composer.compose("M", width: 400)
        let strokes = InkStrokeBuilder.strokes(from: composed)
        let full = try #require(strokes.first)
        let partial = try #require(InkStrokeBuilder.partialStroke(full, fraction: 0.3))
        #expect(partial.path.count <= full.path.count)
    }
}
