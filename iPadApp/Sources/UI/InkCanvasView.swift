import SwiftUI
import PencilKit

/// The tool the canvas is currently writing with.
enum CanvasTool: Equatable {
    case pen
    case eraser
}

/// A SwiftUI wrapper over `PKCanvasView`: the whole scrollable page.
///
/// - Apple Pencil draws (`drawingPolicy = .pencilOnly`); fingers scroll.
/// - The paper and every answer live in a `PaperView` inside the canvas's
///   scroll content, behind the ink, so everything scrolls together.
/// - The page always keeps a screen of blank paper below the lowest ink, so it
///   grows endlessly as it fills.
/// - While an answer writes itself, the page follows it.
struct InkCanvasView: UIViewRepresentable {
    @Binding var drawing: PKDrawing
    var tool: CanvasTool
    var isDrawingLocked: Bool
    var answers: [PageAnswer]
    var revealed: Int
    var font: AnswerFont
    var paper: PaperStyle
    var isDark: Bool
    var pageWidth: CGFloat
    var onDrawingChanged: (PKDrawing) -> Void

    private let minimumContentHeight: CGFloat = 2000
    /// Blank page kept below the lowest ink.
    private let trailingRoom: CGFloat = 1400
    private let growthStep: CGFloat = 1500

    func makeCoordinator() -> Coordinator { Coordinator(self) }

    func makeUIView(context: Context) -> PKCanvasView {
        let canvas = PKCanvasView()
        canvas.drawingPolicy = .pencilOnly
        canvas.delegate = context.coordinator
        canvas.backgroundColor = .clear
        canvas.isOpaque = false
        canvas.alwaysBounceVertical = true
        canvas.showsVerticalScrollIndicator = false
        canvas.showsHorizontalScrollIndicator = false
        canvas.accessibilityIdentifier = "ink-canvas"
        canvas.insertSubview(context.coordinator.paper, at: 0)
        applyTool(to: canvas)
        context.coordinator.appliedTool = tool
        canvas.drawing = drawing
        context.coordinator.noteDrawing(drawing)
        return canvas
    }

    func updateUIView(_ canvas: PKCanvasView, context: Context) {
        let coordinator = context.coordinator
        coordinator.parent = self
        // This runs on every model change (30x/s while an answer writes), so it
        // must stay O(1) and must never touch the pen mid-stroke: the canvas is
        // the source of truth for ink; only an external clear is pushed in.
        if drawing.strokes.count != canvas.drawing.strokes.count {
            coordinator.isApplyingExternalDrawing = true
            canvas.drawing = drawing
            coordinator.isApplyingExternalDrawing = false
            coordinator.noteDrawing(drawing)
        }
        if coordinator.appliedTool != tool {
            applyTool(to: canvas)
            coordinator.appliedTool = tool
        }
        if canvas.drawingGestureRecognizer.isEnabled == isDrawingLocked {
            canvas.drawingGestureRecognizer.isEnabled = !isDrawingLocked
        }

        let paper = context.coordinator.paper
        paper.update(
            paper: self.paper, isDark: isDark, answers: answers,
            revealed: revealed, font: font, pageWidth: pageWidth
        )

        // PencilKit only renders ink inside contentSize, so it must span the
        // page width; height keeps a screen of room below the lowest ink.
        // Grow in big steps so the page (and its paper) resizes rarely, not
        // after every stroke.
        let needed = max(coordinator.inkBottom, paper.contentBottom) + trailingRoom
        let target = CGSize(
            width: max(pageWidth, canvas.bounds.width),
            height: max(minimumContentHeight, (needed / growthStep).rounded(.up) * growthStep)
        )
        if canvas.contentSize != target {
            canvas.contentSize = target
        }
        if paper.frame.size != target {
            paper.frame = CGRect(origin: .zero, size: target)
        }
        if canvas.subviews.first !== paper {
            canvas.sendSubviewToBack(paper)
        }

        // Follow the answer while it writes itself, but never move the page
        // under a Pencil that is touching it.
        if !coordinator.isPencilDown, let y = paper.revealBottom {
            let visibleBottom = canvas.contentOffset.y + canvas.bounds.height - 140
            if y > visibleBottom {
                let newY = min(y - canvas.bounds.height + 260, target.height - canvas.bounds.height)
                canvas.setContentOffset(CGPoint(x: 0, y: max(newY, 0)), animated: true)
            }
        }
    }

    private func applyTool(to canvas: PKCanvasView) {
        switch tool {
        case .pen:
            canvas.tool = PKInkingTool(.pen, color: Palette.graphiteInk, width: 4)
        case .eraser:
            // Vector eraser removes whole strokes.
            canvas.tool = PKEraserTool(.vector)
        }
    }

    final class Coordinator: NSObject, PKCanvasViewDelegate {
        var parent: InkCanvasView
        var isApplyingExternalDrawing = false
        var appliedTool: CanvasTool?
        var isPencilDown = false
        /// Lowest ink point, recomputed once per stroke rather than per frame.
        private(set) var inkBottom: CGFloat = 0
        let paper = PaperView()

        init(_ parent: InkCanvasView) { self.parent = parent }

        func noteDrawing(_ drawing: PKDrawing) {
            let b = drawing.bounds
            inkBottom = b.isNull ? 0 : b.maxY
        }

        func canvasViewDidBeginUsingTool(_ canvasView: PKCanvasView) { isPencilDown = true }
        func canvasViewDidEndUsingTool(_ canvasView: PKCanvasView) { isPencilDown = false }

        func canvasViewDrawingDidChange(_ canvasView: PKCanvasView) {
            guard !isApplyingExternalDrawing else { return }
            let new = canvasView.drawing
            noteDrawing(new)
            parent.drawing = new
            parent.onDrawingChanged(new)
        }
    }
}
