import Testing
import Foundation
import PencilKit
@testable import LivingPage

@Suite("Recognition text normalization")
struct RecognitionTextTests {
    @Test("nil in, nil out")
    func nilPassthrough() {
        #expect(RecognitionText.normalize(nil) == nil)
    }

    @Test("Whitespace-only becomes nil")
    func whitespaceOnly() {
        #expect(RecognitionText.normalize("   \n\t ") == nil)
    }

    @Test("Collapses internal whitespace and trims")
    func collapses() {
        #expect(RecognitionText.normalize("  what   is\nink? ") == "what is ink?")
    }
}

@Suite("Drawing heuristics")
struct DrawingHeuristicsTests {
    @Test("Empty drawing is blank")
    func blank() {
        #expect(DrawingHeuristics.isBlank(PKDrawing()))
        #expect(!DrawingHeuristics.isRecognizable(PKDrawing()))
    }

    @Test("Tiny dot is too small")
    func tiny() {
        let d = SyntheticDrawing.tinyDot()
        #expect(!DrawingHeuristics.isBlank(d))
        #expect(DrawingHeuristics.isTooSmall(d))
        #expect(!DrawingHeuristics.isRecognizable(d))
    }

    @Test("A real line is recognizable")
    func line() {
        let d = SyntheticDrawing.line()
        #expect(!DrawingHeuristics.isBlank(d))
        #expect(!DrawingHeuristics.isTooSmall(d))
        #expect(DrawingHeuristics.isRecognizable(d))
    }

    @Test("Synthetic line is a genuine vector stroke, not a raster")
    func realVectorStroke() {
        let d = SyntheticDrawing.line()
        #expect(d.strokes.count == 1)
        // A vector stroke exposes a path with control points.
        let stroke = d.strokes[0]
        #expect(stroke.path.count > 1)
    }
}
