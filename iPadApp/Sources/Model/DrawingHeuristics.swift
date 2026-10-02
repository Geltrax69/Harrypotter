import Foundation
import PencilKit
import CoreGraphics

/// Pure helpers for evaluating a `PKDrawing` without any UIKit interaction.
public enum DrawingHeuristics {
    /// Minimum bounding-box diagonal (in points) a drawing must span before we
    /// consider it worth recognizing. Guards against stray dots and accidental
    /// taps.
    public static let minimumDiagonal: CGFloat = 40

    /// Minimum number of strokes required.
    public static let minimumStrokeCount = 1

    /// Whether the drawing has no strokes at all.
    public static func isBlank(_ drawing: PKDrawing) -> Bool {
        drawing.strokes.isEmpty
    }

    /// Whether the drawing is too small/sparse to be a real question.
    public static func isTooSmall(_ drawing: PKDrawing) -> Bool {
        if drawing.strokes.count < minimumStrokeCount { return true }
        let bounds = drawing.bounds
        if bounds.isNull || bounds.isEmpty { return true }
        let diagonal = (bounds.width * bounds.width + bounds.height * bounds.height).squareRoot()
        return diagonal < minimumDiagonal
    }

    /// True when the drawing is a plausible candidate for recognition.
    public static func isRecognizable(_ drawing: PKDrawing) -> Bool {
        !isBlank(drawing) && !isTooSmall(drawing)
    }
}

/// Builds real vector PKDrawings for tests and UI-testing mode, without any
/// Apple Pencil hardware. These are genuine strokes, not rasters.
public enum SyntheticDrawing {
    /// A single horizontal-ish stroke spanning `length` points, large enough to
    /// pass `DrawingHeuristics.isRecognizable`.
    public static func line(from start: CGPoint = CGPoint(x: 80, y: 120),
                            length: CGFloat = 320,
                            pointCount: Int = 24) -> PKDrawing {
        let ink = PKInk(.pen, color: .black)
        var points: [PKStrokePoint] = []
        let step = length / CGFloat(max(pointCount - 1, 1))
        for i in 0..<pointCount {
            let x = start.x + step * CGFloat(i)
            let y = start.y + sin(CGFloat(i) / 3.0) * 12 // gentle waviness -> real geometry
            let point = PKStrokePoint(
                location: CGPoint(x: x, y: y),
                timeOffset: TimeInterval(i) * 0.02,
                size: CGSize(width: 3, height: 3),
                opacity: 1,
                force: 1,
                azimuth: 0,
                altitude: .pi / 2
            )
            points.append(point)
        }
        let path = PKStrokePath(controlPoints: points, creationDate: Date())
        let stroke = PKStroke(ink: ink, path: path)
        return PKDrawing(strokes: [stroke])
    }

    /// A tiny dot that should be rejected by the "too small" heuristic.
    public static func tinyDot(at origin: CGPoint = CGPoint(x: 100, y: 100)) -> PKDrawing {
        let ink = PKInk(.pen, color: .black)
        let points = [
            PKStrokePoint(location: origin, timeOffset: 0, size: CGSize(width: 2, height: 2),
                          opacity: 1, force: 1, azimuth: 0, altitude: .pi / 2),
            PKStrokePoint(location: CGPoint(x: origin.x + 2, y: origin.y + 2), timeOffset: 0.01,
                          size: CGSize(width: 2, height: 2), opacity: 1, force: 1, azimuth: 0, altitude: .pi / 2),
        ]
        let path = PKStrokePath(controlPoints: points, creationDate: Date())
        return PKDrawing(strokes: [PKStroke(ink: ink, path: path)])
    }
}
