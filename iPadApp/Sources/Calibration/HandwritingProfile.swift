import Foundation
import CoreGraphics

/// A locally calibrated handwriting profile, stored on-device only.
///
/// IMPORTANT: This container is deliberately Codable for LOCAL JSON persistence
/// but is NEVER placed on the network. There is no code path that encodes a
/// `HandwritingProfile` into `AnswerRequest`; the wire contract remains four
/// scalar fields. Local coordinates retain stroke order and pen dynamics.
public struct HandwritingProfile: Codable, Sendable, Equatable {
    /// Schema version for forward/backward compatibility and migration.
    public static let currentVersion = 1
    public var version: Int

    /// Captured glyph banks keyed by token (single chars, ligatures, etc.).
    public var banks: [String: GlyphBank]

    /// Metrics derived from rhythm-phrase samples (line-height/spacing/slant).
    public var metrics: StyleMetrics

    public init(version: Int = HandwritingProfile.currentVersion, banks: [String: GlyphBank], metrics: StyleMetrics) {
        self.version = version
        self.banks = banks
        self.metrics = metrics
    }

    /// A usable profile has at least a minimal set of lowercase coverage.
    /// Below this bar, Personal gracefully falls back to a preset.
    ///
    /// A bank only counts when it actually carries renderable ink: at least one
    /// variant that has at least one non-empty stroke. A key mapped to an empty
    /// bank (no variants, or variants whose strokes are all empty) is NOT
    /// coverage and must not make a profile look usable.
    public var isUsable: Bool {
        let lowercase = Set("abcdefghijklmnopqrstuvwxyz".map(String.init))
        let covered = lowercase.filter { key in
            guard let bank = banks[key] else { return false }
            return bank.variants.contains { variant in
                variant.strokes.contains { !$0.points.isEmpty }
            }
        }
        return covered.count >= 13 // at least half the lowercase alphabet
    }

    /// Fraction of the full target token set that has been captured (0...1).
    public func completeness(target: [String]) -> Double {
        guard !target.isEmpty else { return 0 }
        let have = target.filter { banks[$0] != nil }.count
        return Double(have) / Double(target.count)
    }
}

/// A `GlyphProviding` backed by a captured profile. Missing glyphs are reported
/// as `nil` so the composer can fall back to the selected preset. The compositor
/// prefers the longest captured ligature and selects variants deterministically.
public struct PersonalHand: GlyphProviding {
    public let metrics: StyleMetrics
    private let banks: [String: GlyphBank]

    public init(profile: HandwritingProfile) {
        self.metrics = profile.metrics
        self.banks = profile.banks
    }

    public var ligatureKeys: [String] {
        banks.keys.filter { $0.count > 1 }
    }

    public func bank(for key: String) -> GlyphBank? {
        banks[key]
    }
}
