import Foundation
import PencilKit
import CoreGraphics

/// Deterministic synthetic handwriting artifacts for tests and UI-testing mode.
/// These build a usable `HandwritingProfile` and capture-pad samples WITHOUT any
/// Apple Pencil, using genuine vector strokes (not rasters).
public enum SyntheticProfile {
    /// A usable profile derived from the base alphabet, so Personal resolves to a
    /// real PersonalHand rather than falling back. Deterministic.
    public static func usable() -> HandwritingProfile {
        var banks: [String: GlyphBank] = [:]
        // Cover the full lowercase + a few others so `isUsable` is true.
        let coverage = "abcdefghijklmnopqrstuvwxyz0123456789.,?".map(String.init)
        for key in coverage {
            guard let first = key.first else { continue }
            let (strokes, _) = BaseAlphabet.strokes(for: first)
            guard !strokes.isEmpty else { continue }
            // Two variants so deterministic variant selection has choices.
            let v1 = GlyphVariant(strokes: strokes, advance: BaseAlphabet.advance(for: key))
            let v2 = GlyphVariant(strokes: strokes.map { jitter($0, by: 0.01) }, advance: BaseAlphabet.advance(for: key))
            banks[key] = GlyphBank(key: key, variants: [v1, v2])
        }
        // A captured ligature so longest-match personal ligatures are exercised.
        if let th = BaseAlphabet.glyphs["t"], let h = BaseAlphabet.glyphs["h"] {
            let shifted = h.map { stroke in InkStroke(points: stroke.points.map { p in
                var np = p; np.x += 0.5; return np
            }) }
            banks["th"] = GlyphBank(key: "th", variants: [GlyphVariant(strokes: th + shifted, advance: 1.0)])
        }
        let metrics = StyleMetrics(
            emHeight: 38, spaceAdvance: 0.32, letterSpacing: 0.06, lineHeight: 1.55,
            slant: 0.10, slantJitter: 0.03, baselineJitter: 0.02, spacingJitter: 0.05
        )
        return HandwritingProfile(banks: banks, metrics: metrics)
    }

    private static func jitter(_ stroke: InkStroke, by amount: Double) -> InkStroke {
        InkStroke(points: stroke.points.enumerated().map { i, p in
            var np = p
            np.x += (i % 2 == 0 ? amount : -amount)
            return np
        })
    }
}

/// Builds genuine capture-pad `PKDrawing`s for a token without hardware. Used by
/// calibration unit tests and the UI-testing sample-injection harness.
public enum SyntheticSample {
    /// A drawing of the base glyph for `token`, scaled to `emPoints`, placed so
    /// it is a valid (non-tiny) sample.
    public static func drawing(for token: String, emPoints: CGFloat = 120) -> PKDrawing {
        let first = token.first.map { BaseAlphabet.strokes(for: $0).strokes } ?? []
        let strokes = first.isEmpty ? [InkStroke(xy: [(0, 0), (0.5, -0.7), (1.0, 0)])] : first
        let ink = PKInk(.pen, color: .black)
        let pkStrokes: [PKStroke] = strokes.map { st in
            let pts = st.points.enumerated().map { i, p in
                PKStrokePoint(
                    location: CGPoint(x: 40 + p.x * emPoints, y: 200 + p.y * emPoints),
                    timeOffset: TimeInterval(i) * 0.02,
                    size: CGSize(width: 4, height: 4),
                    opacity: 1, force: 1, azimuth: 0, altitude: .pi / 2
                )
            }
            let dupPts = pts.count == 1 ? pts + pts : pts
            return PKStroke(ink: ink, path: PKStrokePath(controlPoints: dupPts, creationDate: Date()))
        }
        return PKDrawing(strokes: pkStrokes)
    }

    /// A multi-stroke phrase-like drawing for rhythm metric derivation.
    public static func phrase(emPoints: CGFloat = 100) -> PKDrawing {
        let ink = PKInk(.pen, color: .black)
        var strokes: [PKStroke] = []
        for word in 0..<3 {
            let baseX = 40 + CGFloat(word) * (emPoints * 1.6)
            let pts = (0..<10).map { i in
                PKStrokePoint(
                    location: CGPoint(x: baseX + CGFloat(i) * 8, y: 200 - CGFloat(i % 3) * 20),
                    timeOffset: TimeInterval(i) * 0.02,
                    size: CGSize(width: 4, height: 4),
                    opacity: 1, force: 1, azimuth: 0, altitude: .pi / 2
                )
            }
            strokes.append(PKStroke(ink: ink, path: PKStrokePath(controlPoints: pts, creationDate: Date())))
        }
        return PKDrawing(strokes: strokes)
    }
}
