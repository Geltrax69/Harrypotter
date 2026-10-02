import SwiftUI
import PencilKit

/// A Pencil-only capture pad for a single calibration token. No keyboard is ever
/// shown. Reports drawing changes so Save can validate non-tiny ink.
struct CapturePad: UIViewRepresentable {
    @Binding var drawing: PKDrawing
    var onChange: (PKDrawing) -> Void

    func makeCoordinator() -> Coordinator { Coordinator(self) }

    func makeUIView(context: Context) -> PKCanvasView {
        let canvas = PKCanvasView()
        canvas.drawingPolicy = .pencilOnly
        canvas.delegate = context.coordinator
        canvas.backgroundColor = .clear
        canvas.isOpaque = false
        canvas.tool = PKInkingTool(.pen, color: Palette.graphiteInk, width: 4)
        canvas.accessibilityIdentifier = "capture-pad"
        canvas.drawing = drawing
        return canvas
    }

    func updateUIView(_ canvas: PKCanvasView, context: Context) {
        context.coordinator.parent = self
        if canvas.drawing != drawing {
            context.coordinator.applyingExternal = true
            canvas.drawing = drawing
            context.coordinator.applyingExternal = false
        }
    }

    final class Coordinator: NSObject, PKCanvasViewDelegate {
        var parent: CapturePad
        var applyingExternal = false
        init(_ parent: CapturePad) { self.parent = parent }
        func canvasViewDrawingDidChange(_ canvasView: PKCanvasView) {
            guard !applyingExternal else { return }
            parent.drawing = canvasView.drawing
            parent.onChange(canvasView.drawing)
        }
    }
}

/// Renders a normalized glyph (`[InkStroke]`) as a small static vector preview.
/// This is real ink, not a font: strokes are drawn into a display-only canvas.
struct VectorGlyphPreview: UIViewRepresentable {
    var strokes: [InkStroke]
    var size: CGFloat = 60

    func makeUIView(context: Context) -> PKCanvasView {
        let canvas = PKCanvasView()
        canvas.backgroundColor = .clear
        canvas.isOpaque = false
        canvas.isUserInteractionEnabled = false
        canvas.drawing = render()
        canvas.accessibilityIdentifier = "vector-preview"
        return canvas
    }

    func updateUIView(_ canvas: PKCanvasView, context: Context) {
        canvas.drawing = render()
    }

    private func render() -> PKDrawing {
        // Scale normalized em coords (~0.72 tall) into the preview box.
        let scale = size * 0.7
        let baseline = size * 0.8
        let placed = strokes.map { stroke -> InkStroke in
            stroke.mappingPoints { p in
                var np = p
                np.x = 6 + p.x * scale
                np.y = baseline + p.y * scale
                return np
            }
        }
        let pk = placed.compactMap { InkStrokeBuilder.stroke(from: $0, color: Palette.graphiteInk, width: 3) }
        return PKDrawing(strokes: pk)
    }
}

/// The full calibration experience. Native sheet, resumable, Pencil-only,
/// with section + overall progress, a live vector preview, and native controls.
/// Copy explicitly states this is not a signature.
struct CalibrationView: View {
    @State var model: CalibrationViewModel
    let onClose: () -> Void

    @State private var padDrawing = PKDrawing()
    @State private var showTooSmall = false
    @Environment(\.dynamicTypeSize) private var dynamicType

    var body: some View {
        NavigationStack {
            ZStack {
                Palette.sheet.ignoresSafeArea()
                VStack(alignment: .leading, spacing: 18) {
                    header
                    progressBars
                    promptCard
                    padArea
                    if !model.previewStrokes.isEmpty {
                        previewRow
                    }
                    Spacer(minLength: 0)
                    controls
                }
                .padding(20)
            }
            .navigationTitle("Calibrate your hand")
            .navigationBarTitleDisplayMode(.inline)
            .toolbar {
                ToolbarItem(placement: .cancellationAction) {
                    Button("Close") { model.finish(); onClose() }
                        .accessibilityIdentifier("calibration-close")
                }
            }
            .alert("That mark was too light to save", isPresented: $showTooSmall) {
                Button("OK", role: .cancel) {}
            } message: {
                Text("Write the character a little larger, then Save Sample.")
            }
            // Distinct from "too small": a secure-storage failure is actionable
            // and never exposes filesystem details.
            .alert(
                "Couldn’t save securely",
                isPresented: Binding(
                    get: { model.storageError != nil },
                    set: { if !$0 { model.clearStorageError() } }
                )
            ) {
                Button("OK", role: .cancel) { model.clearStorageError() }
            } message: {
                Text(model.storageError ?? CalibrationViewModel.secureStorageErrorMessage)
            }
        }
    }

    private var header: some View {
        // Explicit privacy copy: signatures are forbidden and never requested.
        Text("Write each character as it feels natural. This is not a signature — never write your name or signature here. Everything stays on this device.")
            .font(.footnote)
            .foregroundStyle(Palette.graphiteSoft)
            .fixedSize(horizontal: false, vertical: true)
            .accessibilityIdentifier("calibration-privacy")
    }

    private var progressBars: some View {
        VStack(alignment: .leading, spacing: 8) {
            labeledProgress("This section", value: model.sectionFraction)
            labeledProgress("Overall", value: model.overallFraction)
        }
        .accessibilityIdentifier("calibration-progress")
    }

    private func labeledProgress(_ label: String, value: Double) -> some View {
        VStack(alignment: .leading, spacing: 2) {
            Text(label).font(.caption).foregroundStyle(Palette.graphiteSoft)
            ProgressView(value: value)
                .tint(Palette.indigo)
        }
    }

    private var promptCard: some View {
        VStack(alignment: .leading, spacing: 6) {
            Text(model.currentSection.title)
                .font(.subheadline.weight(.semibold))
                .foregroundStyle(Palette.graphiteSoft)
            Text(model.currentPrompt.isPhrase ? "Write: \u{201C}\(model.currentPrompt.token)\u{201D}" : "Write: \(model.currentPrompt.token)")
                .font(.title2.weight(.regular))
                .foregroundStyle(Palette.graphite)
                .accessibilityIdentifier("calibration-prompt")
                .accessibilityLabel("Write \(model.currentPrompt.token)")
        }
    }

    private var padArea: some View {
        ZStack {
            RuledPaper()
            CapturePad(drawing: $padDrawing) { model.padChanged($0) }
                .accessibilityIdentifier("capture-pad")
        }
        .frame(height: 200)
        .background(
            RoundedRectangle(cornerRadius: 14, style: .continuous).fill(Palette.sheetEdge)
        )
        .overlay(
            RoundedRectangle(cornerRadius: 14, style: .continuous)
                .strokeBorder(Palette.graphiteSoft.opacity(0.25), lineWidth: 1)
        )
    }

    private var previewRow: some View {
        HStack(spacing: 12) {
            Text("Your ink")
                .font(.caption).foregroundStyle(Palette.graphiteSoft)
            VectorGlyphPreview(strokes: model.previewStrokes)
                .frame(width: 60, height: 60)
                .accessibilityIdentifier("calibration-preview")
                .accessibilityLabel("Live preview of your last saved character")
        }
    }

    private var controls: some View {
        // Adapt to accessibility Dynamic Type: try the horizontal row first, and
        // fall back to a vertical stack when the labels grow too wide to fit.
        // 44pt hit targets are preserved in both layouts.
        ViewThatFits(in: .horizontal) {
            HStack(spacing: 12) { controlButtons }
            VStack(spacing: 12) { controlButtons }
        }
    }

    @ViewBuilder
    private var controlButtons: some View {
        Button {
            padDrawing = PKDrawing()
            model.padChanged(padDrawing)
        } label: {
            Label("Clear", systemImage: "xmark").frame(minHeight: 44)
        }
        .buttonStyle(.bordered)
        .tint(Palette.graphite)
        .accessibilityIdentifier("calibration-clear")

        Button {
            if !model.isFirstPrompt { model.previous(); padDrawing = PKDrawing() }
        } label: {
            Label("Previous", systemImage: "chevron.left").frame(minHeight: 44)
        }
        .buttonStyle(.bordered)
        .tint(Palette.graphite)
        .disabled(model.isFirstPrompt)
        .accessibilityIdentifier("calibration-previous")

        Button {
            switch model.saveSampleDetailed(padDrawing) {
            case .saved:
                padDrawing = PKDrawing()
                model.padChanged(padDrawing)
            case .tooSmall:
                showTooSmall = true
            case .storageFailed:
                // The storage-error alert is driven by model.storageError; keep
                // the ink on the pad so the user can retry the save.
                break
            }
        } label: {
            Label("Save Sample", systemImage: "checkmark").frame(minHeight: 44).padding(.horizontal, 6)
        }
        .buttonStyle(.borderedProminent)
        .tint(Palette.indigo)
        .accessibilityIdentifier("calibration-save")

        if model.isLastPrompt {
            Button {
                model.finish(); onClose()
            } label: {
                Label("Done", systemImage: "flag.checkered").frame(minHeight: 44)
            }
            .buttonStyle(.bordered)
            .tint(Palette.indigo)
            .accessibilityIdentifier("calibration-done")
        } else {
            Button {
                model.next(); padDrawing = PKDrawing()
            } label: {
                Label("Next", systemImage: "chevron.right").frame(minHeight: 44)
            }
            .buttonStyle(.bordered)
            .tint(Palette.graphite)
            .accessibilityIdentifier("calibration-next")
        }
    }
}

/// A subtle ruled/margin paper treatment for the calibration surface. Cool
/// mineral paper, graphite rules, dark-mode-safe. No franchise styling.
struct RuledPaper: View {
    var body: some View {
        GeometryReader { geo in
            let midline = geo.size.height * 0.6
            ZStack(alignment: .topLeading) {
                Palette.sheet
                // Baseline rule.
                Path { p in
                    p.move(to: CGPoint(x: 0, y: midline))
                    p.addLine(to: CGPoint(x: geo.size.width, y: midline))
                }
                .stroke(Palette.indigo.opacity(0.25), lineWidth: 1)
                // Ascender guide.
                Path { p in
                    p.move(to: CGPoint(x: 0, y: midline * 0.45))
                    p.addLine(to: CGPoint(x: geo.size.width, y: midline * 0.45))
                }
                .stroke(Palette.graphiteSoft.opacity(0.18), lineWidth: 1)
                // Left margin.
                Path { p in
                    p.move(to: CGPoint(x: 28, y: 0))
                    p.addLine(to: CGPoint(x: 28, y: geo.size.height))
                }
                .stroke(Palette.indigo.opacity(0.18), lineWidth: 1)
            }
            .accessibilityHidden(true)
        }
    }
}
