import Foundation
import PencilKit
import CoreGraphics

/// Converts captured `PKDrawing` samples into normalized glyph geometry and
/// assembles a `HandwritingProfile`. Stroke order and per-point dynamics are
/// preserved; only coordinates are normalized into the glyph-local em box.
public enum CalibrationSampleProcessor {
    /// Minimum bounding-box diagonal (points) for a sample to count as non-tiny.
    public static let minimumDiagonal: CGFloat = 24

    /// Whether a captured drawing has enough ink to be a real sample.
    public static func isValidSample(_ drawing: PKDrawing) -> Bool {
        guard !drawing.strokes.isEmpty else { return false }
        let b = drawing.bounds
        guard !b.isNull, !b.isEmpty else { return false }
        let diag = (b.width * b.width + b.height * b.height).squareRoot()
        return diag >= minimumDiagonal
    }

    /// Normalizes a single-glyph drawing into an `InkStroke` array in em units.
    /// The drawing is scaled uniformly so its height maps to ~0.72 em (cap
    /// height) and translated so the baseline sits at y=0. Stroke order and all
    /// dynamics are retained.
    public static func normalizeGlyph(_ drawing: PKDrawing) -> [InkStroke] {
        let bounds = drawing.bounds
        guard !bounds.isNull, bounds.height > 0 else { return [] }
        // Uniform scale so height -> ~0.72 em; preserves aspect ratio.
        let targetHeight: CGFloat = 0.72
        let scale = targetHeight / bounds.height
        let originX = bounds.minX
        // Map the bounding-box bottom to baseline (y=0), growing upward negative.
        let bottomY = bounds.maxY

        return drawing.strokes.compactMap { stroke -> InkStroke? in
            var sampled = Array(stroke.path.interpolatedPoints(by: .distance(1.5)))
            // Guarantee usable geometry: fall back to raw control points when
            // interpolation is too sparse (very short strokes).
            if sampled.count < 2 {
                sampled = (0..<stroke.path.count).map { stroke.path[$0] }
            }
            guard sampled.count >= 2 else { return nil }
            // A representative pen size for this stroke in em units, derived from
            // the source point sizes rather than a flat constant, so heavier or
            // lighter strokes keep their relative weight.
            let sizes = sampled.map { Double(max($0.size.width, $0.size.height)) }
            let referenceSize = sizes.max() ?? 4
            let pts = sampled.map { sp -> InkPoint in
                let nx = Double((sp.location.x - originX) * scale)
                let ny = Double((sp.location.y - bottomY) * scale) // <=0 above baseline
                // A meaningful per-point size normalized against the stroke's
                // reference size (so relative pressure-driven width survives),
                // never a flat 1 for every point.
                let pointSize = referenceSize > 0
                    ? Double(max(sp.size.width, sp.size.height)) / referenceSize
                    : 1
                // Preserve source threshold (iOS 26+) and lateral jitter
                // (iOS 27+) rather than overwriting with constants.
                var threshold = 0.0
                var lateralJitter = 0.0
                if #available(iOS 26.0, *) { threshold = Double(sp.threshold) }
                if #available(iOS 27.0, *) { lateralJitter = Double(sp.lateralJitter) }
                return InkPoint(
                    x: nx,
                    y: ny,
                    timeOffset: sp.timeOffset,
                    force: Double(sp.force),
                    azimuth: Double(sp.azimuth),
                    altitude: Double(sp.altitude),
                    opacity: Double(sp.opacity),
                    size: pointSize,
                    secondaryScale: Double(sp.secondaryScale),
                    threshold: threshold,
                    lateralJitter: lateralJitter
                )
            }
            // Preserve the source stroke's rendering metadata so a captured
            // glyph can be reconstructed exactly. renderGroupID/renderState are
            // iPadOS 27 only; the deployment target is 27 so they are always
            // available. Capture the FULL render state (opaque + observable),
            // not just its grain offset.
            let groupID: UUID? = stroke.renderGroupID
            let renderState: PKStroke.RenderState? = stroke.renderState
            return InkStroke(
                points: Array(pts),
                randomSeed: stroke.randomSeed,
                renderGroupID: groupID,
                renderState: renderState
            )
        }
    }

    /// The advance width (em) of a normalized glyph = its scaled width.
    public static func advance(_ drawing: PKDrawing) -> Double {
        let b = drawing.bounds
        guard !b.isNull, b.height > 0 else { return 0.56 }
        let scale = 0.72 / b.height
        return Double(b.width * scale) + 0.10 // small side bearing
    }
}

/// Builds and updates a `HandwritingProfile` from captured samples. Chooses the
/// longest captured ligature and stores deterministic variants (one per capture
/// of the same token becomes an additional variant, enabling natural variation).
public struct HandwritingProfileBuilder {
    public private(set) var banks: [String: GlyphBank]
    public private(set) var phraseMetrics: PhraseMetricsAccumulator
    /// Metrics carried over from an existing profile so that resuming and saving
    /// another glyph never clobbers previously-derived metrics with defaults.
    private let existingMetrics: StyleMetrics?
    /// True once at least one phrase has been ingested this session, so freshly
    /// derived metrics take precedence over the carried-over ones.
    private var didIngestPhrase = false

    public init(existing: HandwritingProfile? = nil) {
        self.banks = existing?.banks ?? [:]
        self.phraseMetrics = PhraseMetricsAccumulator()
        self.existingMetrics = existing?.metrics
    }

    /// Adds a captured glyph sample for a token at a specific variant slot.
    ///
    /// Slot 0 is the primary capture; slot 1 is the natural variation pass.
    /// Writing a slot replaces exactly that slot and never appends without
    /// bound, so re-doing a prompt overwrites only its own variant. The bank is
    /// grown just enough to hold the requested slot.
    public mutating func setGlyph(token: String, slot: Int, drawing: PKDrawing) {
        let strokes = CalibrationSampleProcessor.normalizeGlyph(drawing)
        guard !strokes.isEmpty else { return }
        let advance = CalibrationSampleProcessor.advance(drawing)
        let variant = GlyphVariant(strokes: strokes, advance: advance)
        let index = max(slot, 0)
        if var bank = banks[token] {
            if index < bank.variants.count {
                bank.variants[index] = variant
            } else {
                // Pad any gap by repeating the incoming variant so the bank stays
                // dense and deterministic; then place at the requested slot.
                while bank.variants.count < index { bank.variants.append(variant) }
                bank.variants.append(variant)
            }
            banks[token] = bank
        } else {
            var variants = [GlyphVariant](repeating: variant, count: index + 1)
            variants[index] = variant
            banks[token] = GlyphBank(key: token, variants: variants)
        }
    }

    /// Adds a captured glyph sample for a token, appending it as a new variant.
    public mutating func addGlyph(token: String, drawing: PKDrawing) {
        let strokes = CalibrationSampleProcessor.normalizeGlyph(drawing)
        guard !strokes.isEmpty else { return }
        let advance = CalibrationSampleProcessor.advance(drawing)
        let variant = GlyphVariant(strokes: strokes, advance: advance)
        if var bank = banks[token] {
            bank.variants.append(variant)
            banks[token] = bank
        } else {
            banks[token] = GlyphBank(key: token, variants: [variant])
        }
    }

    /// Replaces all variants for a token (used by "redo this sample").
    public mutating func replaceGlyph(token: String, drawing: PKDrawing) {
        let strokes = CalibrationSampleProcessor.normalizeGlyph(drawing)
        guard !strokes.isEmpty else { return }
        let advance = CalibrationSampleProcessor.advance(drawing)
        banks[token] = GlyphBank(key: token, variants: [GlyphVariant(strokes: strokes, advance: advance)])
    }

    /// Feeds a rhythm phrase sample; derives line-height/spacing/slant/rhythm.
    /// NOTE: phrases are used ONLY for metrics, never stored as a signature.
    public mutating func addPhrase(drawing: PKDrawing) {
        phraseMetrics.ingest(drawing)
        didIngestPhrase = true
    }

    /// Assembles the profile. Metrics come from freshly-ingested phrase samples
    /// when available this session; otherwise the existing profile's metrics are
    /// preserved (so resuming and saving a glyph never resets them); otherwise a
    /// sensible personal default.
    public func build() -> HandwritingProfile {
        let metrics: StyleMetrics
        if didIngestPhrase {
            metrics = phraseMetrics.metrics()
        } else if let existingMetrics {
            metrics = existingMetrics
        } else {
            metrics = phraseMetrics.metrics()
        }
        return HandwritingProfile(banks: banks, metrics: metrics)
    }
}

/// Accumulates rhythm/spacing/slant metrics from phrase drawings without ever
/// retaining the phrase geometry itself.
public struct PhraseMetricsAccumulator: Sendable {
    private var heights: [Double] = []
    private var slants: [Double] = []
    private var gaps: [Double] = []

    public init() {}

    public mutating func ingest(_ drawing: PKDrawing) {
        guard !drawing.strokes.isEmpty else { return }
        let bounds = drawing.bounds
        guard !bounds.isNull, bounds.height > 0 else { return }
        // x-height proxy from median stroke height.
        let strokeHeights = drawing.strokes.map { Double($0.renderBounds.height) }
        if let median = median(strokeHeights) { heights.append(median) }

        // Slant proxy: average signed dx over dy of each stroke.
        var slantSum = 0.0
        var slantCount = 0.0
        for stroke in drawing.strokes {
            let pts = stroke.path.interpolatedPoints(by: .distance(4)).map { $0.location }
            if let first = pts.first, let last = pts.last {
                let dy = Double(last.y - first.y)
                let dx = Double(last.x - first.x)
                if abs(dy) > 1 { slantSum += atan2(dx, -dy); slantCount += 1 }
            }
        }
        if slantCount > 0 { slants.append(slantSum / slantCount) }

        // Word-gap proxy: horizontal gaps between successive stroke render boxes.
        let sorted = drawing.strokes.map { $0.renderBounds }.sorted { $0.minX < $1.minX }
        for i in 1..<max(sorted.count, 1) where i < sorted.count {
            let gap = Double(sorted[i].minX - sorted[i - 1].maxX)
            if gap > 0 { gaps.append(gap) }
        }
    }

    /// Derives bounded `StyleMetrics`. Clamps everything so a noisy sample can
    /// never produce degenerate layout.
    public func metrics() -> StyleMetrics {
        let em = 38.0
        let avgSlant = clamp(average(slants) ?? 0.10, -0.35, 0.45)
        let avgGap = average(gaps).map { clamp($0 / em, 0.20, 0.60) } ?? 0.32
        let lineHeight = clamp((average(heights).map { $0 / em } ?? 1.0) + 1.0, 1.3, 1.9)
        return StyleMetrics(
            emHeight: em,
            spaceAdvance: avgGap,
            letterSpacing: 0.06,
            lineHeight: lineHeight,
            slant: avgSlant,
            slantJitter: 0.04,
            baselineJitter: 0.025,
            spacingJitter: 0.06,
            wordSpacingMultiplier: 1.0
        )
    }

    private func average(_ xs: [Double]) -> Double? {
        guard !xs.isEmpty else { return nil }
        return xs.reduce(0, +) / Double(xs.count)
    }
    private func median(_ xs: [Double]) -> Double? {
        guard !xs.isEmpty else { return nil }
        let s = xs.sorted()
        return s[s.count / 2]
    }
    private func clamp(_ v: Double, _ lo: Double, _ hi: Double) -> Double { min(max(v, lo), hi) }
}
