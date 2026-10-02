import Foundation
import PencilKit
import UIKit

/// Converts normalized composed ink into genuine `PKStroke`/`PKDrawing` values.
///
/// This is the ONLY path by which an answer becomes visible: real vector ink in
/// the same canvas as the question. No font, `Text`, raster image, or glyph
/// outline is ever used to render the answer.
public enum InkStrokeBuilder {
    /// Deep indigo answer ink, matching the "system voice" palette role.
    public static let answerInkColor = UIColor(
        red: 0.208, green: 0.235, blue: 0.451, alpha: 1.0
    )

    /// Builds a single `PKStroke` from a normalized stroke in page coordinates.
    /// Preserves per-point dynamics via the full `PKStrokePoint` initializer, and
    /// reconstructs the stroke with the retained `randomSeed`/`renderGroupID`/
    /// `renderState` (iPadOS 27) so a captured stroke round-trips exactly.
    public static func stroke(
        from inkStroke: InkStroke,
        color: UIColor = answerInkColor,
        width: CGFloat = 3.0
    ) -> PKStroke? {
        guard inkStroke.points.count >= 1 else { return nil }
        let ink = PKInk(.pen, color: color)
        var controlPoints: [PKStrokePoint] = []
        controlPoints.reserveCapacity(max(inkStroke.points.count, 2))
        for p in inkStroke.points {
            controlPoints.append(strokePoint(from: p, width: width))
        }
        // A single-point stroke needs a duplicate so the path has extent.
        if controlPoints.count == 1 {
            controlPoints.append(controlPoints[0])
        }
        let path = PKStrokePath(controlPoints: controlPoints, creationDate: Date(timeIntervalSinceReferenceDate: 0))

        // iPadOS 27: reconstruct with the retained render group + the FULL
        // render state so wet-ink compositing and all particle/grain state match
        // the source stroke exactly (not just the observable grain offset).
        if #available(iOS 27.0, *) {
            return PKStroke(
                ink: ink,
                path: path,
                transform: .identity,
                mask: nil,
                randomSeed: inkStroke.randomSeed,
                renderGroupID: inkStroke.renderGroupID,
                renderState: inkStroke.renderState
            )
        }
        // iOS 16+: preserve at least the random seed.
        return PKStroke(ink: ink, path: path, transform: .identity, mask: nil, randomSeed: inkStroke.randomSeed)
    }

    /// Builds a `PKStrokePoint`, preserving threshold (iOS 26+) and lateral
    /// jitter (iOS 27+) when the running OS supports those initializers.
    private static func strokePoint(from p: InkPoint, width: CGFloat) -> PKStrokePoint {
        let size = CGSize(width: width * CGFloat(p.size), height: width * CGFloat(p.size))
        if #available(iOS 27.0, *) {
            return PKStrokePoint(
                location: p.location, timeOffset: p.timeOffset, size: size,
                opacity: CGFloat(p.opacity), force: CGFloat(p.force),
                azimuth: CGFloat(p.azimuth), altitude: CGFloat(p.altitude),
                secondaryScale: CGFloat(p.secondaryScale),
                threshold: CGFloat(p.threshold), lateralJitter: CGFloat(p.lateralJitter)
            )
        }
        if #available(iOS 26.0, *) {
            return PKStrokePoint(
                location: p.location, timeOffset: p.timeOffset, size: size,
                opacity: CGFloat(p.opacity), force: CGFloat(p.force),
                azimuth: CGFloat(p.azimuth), altitude: CGFloat(p.altitude),
                secondaryScale: CGFloat(p.secondaryScale), threshold: CGFloat(p.threshold)
            )
        }
        return PKStrokePoint(
            location: p.location, timeOffset: p.timeOffset, size: size,
            opacity: CGFloat(p.opacity), force: CGFloat(p.force),
            azimuth: CGFloat(p.azimuth), altitude: CGFloat(p.altitude),
            secondaryScale: CGFloat(p.secondaryScale)
        )
    }

    /// Flattens a composed answer into `PKStroke`s in stroke order.
    public static func strokes(from answer: ComposedAnswer, width: CGFloat = 3.0) -> [PKStroke] {
        var result: [PKStroke] = []
        for glyph in answer.glyphs {
            for st in glyph.strokes {
                if let s = stroke(from: st, width: width) { result.append(s) }
            }
        }
        return result
    }

    /// Builds a complete answer drawing (all strokes revealed).
    public static func drawing(from answer: ComposedAnswer, width: CGFloat = 3.0) -> PKDrawing {
        PKDrawing(strokes: strokes(from: answer, width: width))
    }

    /// Reveals a prefix of a stroke for animation. Uses the iPadOS 27
    /// `substroke(range:)` when available, falling back to a control-point
    /// prefix on older systems. `fraction` is clamped to `0...1`.
    public static func partialStroke(_ stroke: PKStroke, fraction: Double) -> PKStroke? {
        let f = min(max(fraction, 0), 1)
        if f <= 0 { return nil }
        if f >= 1 { return stroke }
        let count = stroke.path.count
        guard count > 1 else { return stroke }
        let upper = Double(count - 1) * f
        // Parametric domain of substroke is [0, count-1] over the path index.
        return stroke.substroke(range: 0...CGFloat(upper))
    }
}
