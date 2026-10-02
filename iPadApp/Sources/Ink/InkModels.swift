import Foundation
import CoreGraphics
import PencilKit

// Normalized, transport-free vector ink models.
//
// These types are the internal, Codable/Sendable representation of centerline
// stroke geometry for both the authored preset alphabet and captured personal
// samples. They are deliberately NOT part of the network wire contract: nothing
// here is ever placed into `AnswerRequest`. Coordinates are normalized to a
// glyph-local em box so a glyph can be laid out, scaled, and slanted
// deterministically at composition time.

/// A single normalized stroke point in glyph-local coordinates.
///
/// The `x`/`y` are expressed in em units (see `StyleMetrics.emHeight`). Pen
/// dynamics captured from a real `PKStrokePoint` are preserved so personal ink
/// keeps its rhythm when replayed: `timeOffset`, `force`, `azimuth`, `altitude`,
/// `opacity`, `size`, and the iPadOS render refinements
/// `secondaryScale`/`threshold`/`lateralJitter`.
public struct InkPoint: Codable, Sendable, Equatable {
    public var x: Double
    public var y: Double
    public var timeOffset: Double
    public var force: Double
    public var azimuth: Double
    public var altitude: Double
    public var opacity: Double
    public var size: Double
    public var secondaryScale: Double
    public var threshold: Double
    public var lateralJitter: Double

    public init(
        x: Double,
        y: Double,
        timeOffset: Double = 0,
        force: Double = 1,
        azimuth: Double = 0,
        altitude: Double = .pi / 2,
        opacity: Double = 1,
        size: Double = 1,
        secondaryScale: Double = 1,
        threshold: Double = 0,
        lateralJitter: Double = 0
    ) {
        self.x = x
        self.y = y
        self.timeOffset = timeOffset
        self.force = force
        self.azimuth = azimuth
        self.altitude = altitude
        self.opacity = opacity
        self.size = size
        self.secondaryScale = secondaryScale
        self.threshold = threshold
        self.lateralJitter = lateralJitter
    }

    public var location: CGPoint { CGPoint(x: x, y: y) }
}

/// A normalized centerline stroke: an ordered list of `InkPoint`s. Stroke order
/// within a glyph and point order within a stroke are both meaningful for
/// animation and are preserved verbatim.
///
/// In addition to point dynamics, a stroke retains the `PKStroke`-level rendering
/// metadata needed to reconstruct the exact original stroke on iPadOS 27:
/// `randomSeed` (randomized-effect seed, iOS 16+), `renderGroupID` (wet-ink
/// compositing group, iOS 27+), and `renderState` — the FULL optional
/// `PKStroke.RenderState` (iOS 27+).
///
/// `PKStroke.RenderState` is itself `Codable`/`Sendable`/`Equatable` on
/// iPadOS 27 and may carry OPAQUE ink state in addition to the observable
/// `grainOffset`. We therefore store the whole value rather than reducing it to
/// its grain offset, so a captured stroke round-trips byte-for-byte (both
/// through JSON and through `PKStroke` reconstruction) with no loss of the
/// opaque particle/render information.
///
/// The deployment target is iPadOS 27, so `PKStroke.RenderState` is always
/// available; the field is a plain stored property. All metadata is
/// optional/defaulted, and decoding remains backward-compatible with legacy
/// encodings that stored only `grainOffsetX`/`grainOffsetY`.
public struct InkStroke: Codable, Sendable, Equatable {
    public var points: [InkPoint]
    /// Seed for randomized ink effects. Preserved from the source `PKStroke`.
    public var randomSeed: UInt32
    /// Wet-ink compositing group UUID (iPadOS 27). Nil when ungrouped.
    public var renderGroupID: UUID?
    /// The FULL render state from the source stroke's `PKStroke.RenderState`
    /// (iPadOS 27), including any opaque ink state. Nil when the source used
    /// default rendering. Persisted via `PKStroke.RenderState`'s own `Codable`
    /// conformance so nothing is dropped.
    public var renderState: PKStroke.RenderState?

    public init(
        points: [InkPoint],
        randomSeed: UInt32 = 0,
        renderGroupID: UUID? = nil,
        renderState: PKStroke.RenderState? = nil
    ) {
        self.points = points
        self.randomSeed = randomSeed
        self.renderGroupID = renderGroupID
        self.renderState = renderState
    }

    /// Backward-compatible convenience initializer used by existing call sites
    /// and tests that think of render state purely as a grain offset. Wraps the
    /// offset in a full `PKStroke.RenderState`.
    public init(
        points: [InkPoint],
        randomSeed: UInt32,
        renderGroupID: UUID?,
        renderStateGrainOffset: CGPoint?
    ) {
        self.points = points
        self.randomSeed = randomSeed
        self.renderGroupID = renderGroupID
        if let grain = renderStateGrainOffset {
            self.renderState = PKStroke.RenderState(grainOffset: grain)
        } else {
            self.renderState = nil
        }
    }

    /// Convenience for authoring: build a stroke from bare (x, y) em coordinates
    /// with evenly spaced synthetic timing so authored ink still animates.
    public init(xy: [(Double, Double)], perPointTime: Double = 0.012) {
        self.points = xy.enumerated().map { index, pair in
            InkPoint(
                x: pair.0,
                y: pair.1,
                timeOffset: Double(index) * perPointTime
            )
        }
        self.randomSeed = 0
        self.renderGroupID = nil
        self.renderState = nil
    }

    /// Backward-compatible accessor: the observable grain offset of the retained
    /// render state. Reading returns the offset (nil when there is no render
    /// state); writing installs/clears a render state carrying just that offset.
    /// Kept because existing call sites/tests reference the grain offset by name;
    /// the FULL render state is preserved in `renderState`.
    public var renderStateGrainOffset: CGPoint? {
        get { renderState?.grainOffset }
        set {
            if let newValue {
                var state = renderState ?? PKStroke.RenderState()
                state.grainOffset = newValue
                renderState = state
            } else {
                renderState = nil
            }
        }
    }

    // MARK: - Codable (backward-compatible; metadata keys optional)

    private enum CodingKeys: String, CodingKey {
        case points, randomSeed, renderGroupID
        // Current key: the full render state, encoded via its own Codable.
        case renderState
        // Legacy keys: an older encoding stored only the grain offset pair.
        case grainOffsetX, grainOffsetY
    }

    public init(from decoder: Decoder) throws {
        let c = try decoder.container(keyedBy: CodingKeys.self)
        self.points = try c.decode([InkPoint].self, forKey: .points)
        self.randomSeed = try c.decodeIfPresent(UInt32.self, forKey: .randomSeed) ?? 0
        self.renderGroupID = try c.decodeIfPresent(UUID.self, forKey: .renderGroupID)

        // Prefer the full render state when present; otherwise fall back to the
        // legacy grain-offset-only encoding so old profiles keep decoding.
        if let state = try c.decodeIfPresent(PKStroke.RenderState.self, forKey: .renderState) {
            self.renderState = state
        } else if let gx = try c.decodeIfPresent(Double.self, forKey: .grainOffsetX),
                  let gy = try c.decodeIfPresent(Double.self, forKey: .grainOffsetY) {
            self.renderState = PKStroke.RenderState(grainOffset: CGPoint(x: gx, y: gy))
        } else {
            self.renderState = nil
        }
    }

    public func encode(to encoder: Encoder) throws {
        var c = encoder.container(keyedBy: CodingKeys.self)
        try c.encode(points, forKey: .points)
        if randomSeed != 0 { try c.encode(randomSeed, forKey: .randomSeed) }
        try c.encodeIfPresent(renderGroupID, forKey: .renderGroupID)
        // Encode the FULL render state (opaque + observable) via its own Codable.
        try c.encodeIfPresent(renderState, forKey: .renderState)
    }

    /// Returns a copy with points transformed by `transform`, carrying all
    /// `PKStroke`-level metadata (seed, render group, FULL render state)
    /// unchanged. Placement/preview/style transforms MUST use this rather than
    /// reconstructing `InkStroke(points:)` so metadata is never dropped.
    public func mappingPoints(_ transform: (InkPoint) -> InkPoint) -> InkStroke {
        InkStroke(
            points: points.map(transform),
            randomSeed: randomSeed,
            renderGroupID: renderGroupID,
            renderState: renderState
        )
    }
}

/// One deterministic variant of a glyph. Multiple variants let composition avoid
/// mechanical repetition without becoming random: the chosen variant is a pure
/// function of (character, position, seed).
public struct GlyphVariant: Codable, Sendable, Equatable {
    public var strokes: [InkStroke]
    /// Advance width in em units used for horizontal layout of the next glyph.
    public var advance: Double

    public init(strokes: [InkStroke], advance: Double) {
        self.strokes = strokes
        self.advance = advance
    }

    /// Total control-point count across all strokes; used by tests/animation.
    public var pointCount: Int { strokes.reduce(0) { $0 + $1.points.count } }
}

/// The bank of glyph variants for a single character key. A key is normally a
/// single character, but personal ligatures use multi-character keys
/// (e.g. "th") so a longest-match lookup can prefer them.
public struct GlyphBank: Codable, Sendable, Equatable {
    public var key: String
    public var variants: [GlyphVariant]

    public init(key: String, variants: [GlyphVariant]) {
        self.key = key
        self.variants = variants
    }

    /// Deterministically selects a variant for a layout position. Same inputs
    /// always yield the same variant; different positions spread across the set.
    public func variant(position: Int, seed: UInt64) -> GlyphVariant? {
        guard !variants.isEmpty else { return nil }
        let mixed = DeterministicRandom.mix(seed: seed, salt: UInt64(bitPattern: Int64(position)))
        let index = Int(mixed % UInt64(variants.count))
        return variants[index]
    }
}

/// Style-level metrics that shape a whole hand: baseline geometry plus bounded
/// variation ranges. All values are in em units (except angles, in radians).
public struct StyleMetrics: Codable, Sendable, Equatable {
    /// Nominal cap height / em size in points a glyph is rendered at.
    public var emHeight: Double
    /// Space advance in em units.
    public var spaceAdvance: Double
    /// Additional tracking added between glyphs, em units.
    public var letterSpacing: Double
    /// Line height in em units (baseline to baseline).
    public var lineHeight: Double
    /// Nominal slant applied to the whole hand, radians (positive = rightward).
    public var slant: Double
    /// Maximum extra per-glyph slant jitter, radians.
    public var slantJitter: Double
    /// Maximum per-glyph baseline offset, em units.
    public var baselineJitter: Double
    /// Maximum per-glyph spacing multiplier jitter (0.05 = ±5%).
    public var spacingJitter: Double
    /// Word-space multiplier for rhythm (personal phrase-derived).
    public var wordSpacingMultiplier: Double

    public init(
        emHeight: Double,
        spaceAdvance: Double,
        letterSpacing: Double,
        lineHeight: Double,
        slant: Double,
        slantJitter: Double,
        baselineJitter: Double,
        spacingJitter: Double,
        wordSpacingMultiplier: Double = 1
    ) {
        self.emHeight = emHeight
        self.spaceAdvance = spaceAdvance
        self.letterSpacing = letterSpacing
        self.lineHeight = lineHeight
        self.slant = slant
        self.slantJitter = slantJitter
        self.baselineJitter = baselineJitter
        self.spacingJitter = spacingJitter
        self.wordSpacingMultiplier = wordSpacingMultiplier
    }
}

/// A composed glyph placed at a concrete position on the page (points space).
public struct ComposedGlyph: Sendable, Equatable {
    public var character: String
    /// The strokes for this glyph in page-point coordinates, in stroke order.
    public var strokes: [InkStroke]
    /// Zero-based line index the glyph belongs to (for reduce-motion reveal).
    public var line: Int
    /// True when this glyph is a visible `?` substituted for an unsupported
    /// input character.
    public var isFallbackGlyph: Bool

    public init(character: String, strokes: [InkStroke], line: Int, isFallbackGlyph: Bool) {
        self.character = character
        self.strokes = strokes
        self.line = line
        self.isFallbackGlyph = isFallbackGlyph
    }
}

/// The full result of composing an answer string into vector ink, plus explicit
/// fallback telemetry so callers/tests can assert behavior.
public struct ComposedAnswer: Sendable, Equatable {
    public var glyphs: [ComposedGlyph]
    public var lineCount: Int
    /// Total bounds of the composed ink in page-point coordinates.
    public var bounds: CGRect
    /// The plain text actually laid out (post-normalization), in source order.
    public var normalizedText: String

    // MARK: Fallback telemetry (explicit result flags)

    /// Count of input characters replaced by the visible `?` glyph.
    public var unsupportedCharacterCount: Int
    /// Count of glyphs that fell back from Personal to the selected preset.
    public var personalMissingGlyphFallbackCount: Int
    /// True when the answer was truncated to fit the max height.
    public var didTruncateForHeight: Bool
    /// True when at least one word exceeded the line width and was broken.
    public var didBreakLongWord: Bool

    public init(
        glyphs: [ComposedGlyph],
        lineCount: Int,
        bounds: CGRect,
        normalizedText: String,
        unsupportedCharacterCount: Int,
        personalMissingGlyphFallbackCount: Int,
        didTruncateForHeight: Bool,
        didBreakLongWord: Bool
    ) {
        self.glyphs = glyphs
        self.lineCount = lineCount
        self.bounds = bounds
        self.normalizedText = normalizedText
        self.unsupportedCharacterCount = unsupportedCharacterCount
        self.personalMissingGlyphFallbackCount = personalMissingGlyphFallbackCount
        self.didTruncateForHeight = didTruncateForHeight
        self.didBreakLongWord = didBreakLongWord
    }

    public var totalStrokeCount: Int { glyphs.reduce(0) { $0 + $1.strokes.count } }
    public var totalPointCount: Int {
        glyphs.reduce(0) { partial, glyph in
            partial + glyph.strokes.reduce(0) { $0 + $1.points.count }
        }
    }
}

/// Small, dependency-free deterministic hashing/PRNG used for variant selection
/// and bounded jitter. Same seed always yields the same sequence, which keeps
/// composed output reproducible and testable.
public enum DeterministicRandom {
    /// SplitMix64-style mixing; stable across platforms and runs.
    public static func mix(seed: UInt64, salt: UInt64) -> UInt64 {
        var z = seed &+ (salt &* 0x9E37_79B9_7F4A_7C15)
        z = (z ^ (z >> 30)) &* 0xBF58_476D_1CE4_E5B9
        z = (z ^ (z >> 27)) &* 0x94D0_49BB_1331_11EB
        return z ^ (z >> 31)
    }

    /// A deterministic value in `-1...1` from a seed and salt.
    public static func signedUnit(seed: UInt64, salt: UInt64) -> Double {
        let m = mix(seed: seed, salt: salt)
        // Map the top 53 bits to [0,1), then to [-1, 1).
        let unit = Double(m >> 11) * (1.0 / 9_007_199_254_740_992.0)
        return unit * 2 - 1
    }

    /// Stable 64-bit seed from a string (FNV-1a). Keeps composition deterministic
    /// per answer text without relying on Swift's randomized `Hashable`.
    public static func seed(for string: String) -> UInt64 {
        var hash: UInt64 = 0xCBF2_9CE4_8422_2325
        for byte in string.utf8 {
            hash ^= UInt64(byte)
            hash = hash &* 0x0000_0100_0000_01B3
        }
        return hash
    }
}
