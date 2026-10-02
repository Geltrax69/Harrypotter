import Foundation
import CoreGraphics

/// The user-selectable handwriting styles: three preset hands plus the locally
/// calibrated Personal hand. Raw values are the persisted identifiers.
public enum HandwritingStyle: String, CaseIterable, Sendable, Codable, Identifiable {
    case uprightOpen        // preset 1: vertical, open, generous
    case quickSlanted       // preset 2: fast rightward slant, tighter
    case compactRounded     // preset 3: small, rounded, dense
    case personal           // locally calibrated

    public var id: String { rawValue }

    /// Short, human-facing name for the picker.
    public var displayName: String {
        switch self {
        case .uprightOpen: return "Upright"
        case .quickSlanted: return "Slanted"
        case .compactRounded: return "Rounded"
        case .personal: return "Personal"
        }
    }

    /// The three built-in presets (excludes Personal).
    public static var presets: [HandwritingStyle] { [.uprightOpen, .quickSlanted, .compactRounded] }
}

/// A source of glyph banks and style metrics for a hand. Both preset hands and
/// the Personal-profile compositor conform to this so the layout engine treats
/// them uniformly.
public protocol GlyphProviding: Sendable {
    var metrics: StyleMetrics { get }
    /// Ordered longest-match keys this provider can render as a single unit
    /// (multi-character ligatures first). Used by the layout engine to prefer
    /// ligatures deterministically.
    var ligatureKeys: [String] { get }
    /// Returns the glyph bank for a key, or nil when this provider cannot render
    /// it (the caller then falls back to a preset).
    func bank(for key: String) -> GlyphBank?
}

/// Materially different geometry transforms that turn the shared base alphabet
/// into three distinct preset hands. Each transform is bounded and deterministic.
public struct PresetHand: GlyphProviding {
    public let style: HandwritingStyle
    public let metrics: StyleMetrics
    private let scaleX: Double
    private let scaleY: Double
    private let shear: Double          // horizontal shear applied per unit height
    private let roundness: Double      // corner-softening amount, em units
    private let variantCount: Int
    private let variantJitter: Double  // per-variant control-point jitter, em units

    public var ligatureKeys: [String] { [] } // presets have no multi-char ligatures

    public init(style: HandwritingStyle) {
        self.style = style
        switch style {
        case .uprightOpen:
            // Tall, vertical, generous spacing, minimal shear.
            metrics = StyleMetrics(emHeight: 40, spaceAdvance: 0.34, letterSpacing: 0.10,
                                   lineHeight: 1.65, slant: 0.04, slantJitter: 0.05,
                                   baselineJitter: 0.035, spacingJitter: 0.08)
            scaleX = 1.02; scaleY = 1.05; shear = 0.02; roundness = 0.02
            variantCount = 4; variantJitter = 0.025
        case .quickSlanted:
            // Fast rightward slant, tighter tracking, more variation.
            metrics = StyleMetrics(emHeight: 38, spaceAdvance: 0.30, letterSpacing: 0.04,
                                   lineHeight: 1.55, slant: 0.22, slantJitter: 0.08,
                                   baselineJitter: 0.045, spacingJitter: 0.10)
            scaleX = 0.94; scaleY = 1.0; shear = 0.22; roundness = 0.0
            variantCount = 4; variantJitter = 0.035
        case .compactRounded:
            // Small, rounded, dense.
            metrics = StyleMetrics(emHeight: 34, spaceAdvance: 0.28, letterSpacing: 0.02,
                                   lineHeight: 1.42, slant: 0.10, slantJitter: 0.05,
                                   baselineJitter: 0.04, spacingJitter: 0.09)
            scaleX = 0.90; scaleY = 0.88; shear = 0.05; roundness = 0.05
            variantCount = 4; variantJitter = 0.028
        case .personal:
            // Not a preset; provide a neutral default so the type stays total.
            metrics = StyleMetrics(emHeight: 38, spaceAdvance: 0.32, letterSpacing: 0.06,
                                   lineHeight: 1.55, slant: 0.08, slantJitter: 0.03,
                                   baselineJitter: 0.02, spacingJitter: 0.05)
            scaleX = 1.0; scaleY = 1.0; shear = 0.08; roundness = 0.02
            variantCount = 3; variantJitter = 0.015
        }
    }

    public func bank(for key: String) -> GlyphBank? {
        guard let first = key.first, key.count == 1 else { return nil }
        // The '?' fallback key is always available (it is how the composer
        // materializes a visible fallback glyph). All other keys must be
        // genuinely authored; unsupported characters return nil so the composer
        // can substitute a counted '?' rather than silently rendering it here.
        if key != BaseAlphabet.fallbackKey, !BaseAlphabet.hasGlyph(for: first) {
            return nil
        }
        let (base, _) = BaseAlphabet.strokes(for: first)
        guard !base.isEmpty else { return nil }
        let advance = BaseAlphabet.advance(for: key)
        var variants: [GlyphVariant] = []
        for v in 0..<variantCount {
            let transformed = transform(base, key: key, variantIndex: v)
            variants.append(GlyphVariant(strokes: transformed, advance: advance * scaleX))
        }
        return GlyphBank(key: key, variants: variants)
    }

    /// Applies the hand's bounded geometry to base strokes, deterministically
    /// per (key, variant). Never introduces unbounded randomness.
    private func transform(_ strokes: [InkStroke], key: String, variantIndex: Int) -> [InkStroke] {
        let seed = DeterministicRandom.seed(for: key) ^ UInt64(variantIndex &+ 1) &* 0x9E3779B1
        return strokes.enumerated().map { strokeIdx, stroke in
            let pts = stroke.points.enumerated().map { ptIdx, p -> InkPoint in
                // Shear scales with height above baseline (negative y is up).
                let sheared = p.x + shear * (-p.y)
                var nx = sheared * scaleX
                var ny = p.y * scaleY
                // Bounded, deterministic per-point jitter for a human wobble.
                let salt = UInt64(strokeIdx * 131 + ptIdx * 17 + variantIndex * 7)
                nx += DeterministicRandom.signedUnit(seed: seed, salt: salt) * variantJitter
                ny += DeterministicRandom.signedUnit(seed: seed, salt: salt &+ 1) * variantJitter
                // Roundness nudges points toward the stroke's local midpoint.
                if roundness > 0 {
                    nx += (0.31 - nx) * roundness * 0.15
                }
                var np = p
                np.x = nx
                np.y = ny
                return np
            }
            return InkStroke(
                points: pts,
                randomSeed: stroke.randomSeed,
                renderGroupID: stroke.renderGroupID,
                renderStateGrainOffset: stroke.renderStateGrainOffset
            )
        }
    }
}
