// LIVING PAGE — ROYAL FOLIO
//
// A single endless enchanted page. You write a question by hand; when your pen
// rests, the page answers in a flowing script, in gold leaf by night (royal
// violet by day), right beneath your words. Keep writing below to ask again.
// No status chatter, no chat chrome: a crest, the paper, the script, and the
// quill/eraser/clear controls. Paper and script are the visitor's choice.

import SwiftUI
import PencilKit

struct PageView: View {
    @State private var model = AppEnvironment.makeViewModel()
    @State private var tool: CanvasTool = .pen
    @State private var showClearConfirm = false
    @AppStorage("paperStyle") private var paper: PaperStyle = .royal
    @AppStorage("answerFont") private var font: AnswerFont = .cedarville
    @Environment(\.accessibilityReduceMotion) private var reduceMotion
    @Environment(\.colorScheme) private var colorScheme

    var body: some View {
        GeometryReader { geo in
            ZStack {
                background

                VStack(spacing: 0) {
                    topBar
                        .padding(.horizontal, 24)
                        .padding(.top, 8)

                    ZStack {
                        InkCanvasView(
                            drawing: Binding(
                                get: { model.drawing },
                                set: { _ in }
                            ),
                            tool: tool,
                            isDrawingLocked: model.isDrawingLocked,
                            answers: model.answers,
                            revealed: model.revealedCharacters,
                            font: font,
                            paper: paper,
                            isDark: colorScheme == .dark,
                            pageWidth: geo.size.width,
                            onDrawingChanged: { model.drawingChanged($0) }
                        )
                        .accessibilityLabel("Writing page. Write your question with Apple Pencil.")

                        // Inline recovery (network problems) rises from below.
                        VStack {
                            Spacer()
                            overlay
                                .padding(.horizontal, 24)
                                .padding(.bottom, 96)
                        }
                        .allowsHitTesting(overlayInteractive)
                    }
                }

                // Tool controls, bottom-trailing, 44pt.
                VStack {
                    Spacer()
                    HStack {
                        Spacer()
                        toolControls
                            .padding(.trailing, 24)
                            .padding(.bottom, 24)
                    }
                }
            }
            .onAppear { model.updatePageWidth(geo.size.width) }
            .onChange(of: geo.size.width) { _, newWidth in model.updatePageWidth(newWidth) }
        }
        .confirmationDialog(
            "Clear the page?",
            isPresented: $showClearConfirm,
            titleVisibility: .visible
        ) {
            Button("Clear", role: .destructive) { model.clear() }
                .accessibilityIdentifier("clear-confirm")
            Button("Keep", role: .cancel) {}
                .accessibilityIdentifier("clear-cancel")
        } message: {
            Text("This erases every question and answer on the page.")
        }
        .onAppear {
            if let injected = AppEnvironment.uiTestingInjectedDrawing,
               ProcessInfo.processInfo.arguments.contains("--inject-drawing") {
                model.drawingChanged(injected)
            }
            model.setReduceMotion(reduceMotion)
        }
        .onChange(of: reduceMotion) { _, newValue in model.setReduceMotion(newValue) }
    }

    // MARK: - Background

    /// Midnight velvet (or warm vellum) with a soft glow at the heart of the page.
    private var background: some View {
        ZStack {
            Palette.royalSheet
            RadialGradient(
                colors: [Palette.royalSheetGlow, Palette.royalSheet],
                center: .init(x: 0.5, y: 0.35),
                startRadius: 40,
                endRadius: 900
            )
            .opacity(0.9)
        }
        .ignoresSafeArea()
    }

    // MARK: - Top bar (crest + paper + script)

    private var topBar: some View {
        HStack(spacing: 12) {
            HStack(spacing: 8) {
                Image(systemName: "sparkles")
                    .symbolEffect(.pulse, isActive: isBusy)
                    .foregroundStyle(Palette.gold)
                Text("Living Page")
                    .font(.royal(22, bold: true))
                    .foregroundStyle(Palette.gold)
            }
            // Status stays available to VoiceOver only; nothing visual.
            .accessibilityElement(children: .ignore)
            .accessibilityLabel("Living Page. \(statusText)")
            .accessibilityIdentifier("status-line")

            Spacer()

            Menu {
                Picker("Paper", selection: $paper) {
                    ForEach(PaperStyle.allCases) { style in
                        Label(style.displayName, systemImage: style.symbol).tag(style)
                    }
                }
            } label: {
                royalChip(paper.displayName, symbol: "book.closed")
            }
            .accessibilityIdentifier("paper-picker")

            Menu {
                Picker("Script", selection: $font) {
                    ForEach(AnswerFont.allCases) { f in
                        Text(f.displayName).tag(f)
                    }
                }
            } label: {
                royalChip(font.displayName, symbol: "scribble.variable")
            }
            .accessibilityIdentifier("script-picker")
        }
        .frame(minHeight: 52)
    }

    private func royalChip(_ title: String, symbol: String) -> some View {
        Label(title, systemImage: symbol)
            .font(.royal(14))
            .foregroundStyle(Palette.gold)
            .padding(.horizontal, 14)
            .frame(minHeight: 44)
            .background(Capsule().fill(Palette.royalSheet.opacity(0.6)))
            .overlay(Capsule().strokeBorder(Palette.gold.opacity(0.5), lineWidth: 1))
    }

    private var isBusy: Bool {
        switch model.phase {
        case .recognizing, .sending, .rendering: return true
        default: return false
        }
    }

    private var statusText: String {
        switch model.phase {
        case .blank: return "Write a question."
        case .writing, .waiting: return "Writing."
        case .recognizing: return "Reading your writing."
        case .confirming: return "Read your question."
        case .sending: return "Asking."
        case .rendering: return "Writing the answer."
        case .answered(_, let answer): return "Answered: \(answer)"
        case .error(let e): return e.message
        }
    }

    // MARK: - Overlay (network recovery only)

    private var overlayInteractive: Bool {
        if case .error(let e) = model.phase, e.kind.isNetwork { return true }
        return false
    }

    @ViewBuilder
    private var overlay: some View {
        if case .error(let err) = model.phase, err.kind.isNetwork {
            RecoverySlip(
                error: err,
                onRetry: err.isRetryable ? { model.retry() } : nil,
                onKeepWriting: { model.keepWriting() },
                onStartOver: { model.startOver() }
            )
            .transition(reduceMotion ? .opacity : .move(edge: .bottom).combined(with: .opacity))
        }
    }

    // MARK: - Tool controls

    private var toolControls: some View {
        HStack(spacing: 8) {
            toolButton(.pen, symbol: "pencil.tip", label: "Pen")
            toolButton(.eraser, symbol: "eraser", label: "Eraser")
            Button {
                // Confirm before clearing a nonblank page.
                if model.isPageNonblank { showClearConfirm = true } else { model.clear() }
            } label: {
                Image(systemName: "trash")
                    .frame(width: 44, height: 44)
            }
            .buttonStyle(.bordered)
            .tint(Palette.gold)
            .accessibilityLabel("Clear the page")
            .accessibilityIdentifier("clear")
        }
        .padding(6)
        .background(Capsule().fill(Palette.royalSheet.opacity(0.85)))
        .overlay(Capsule().strokeBorder(Palette.gold.opacity(0.45), lineWidth: 1))
        .shadow(color: Palette.gold.opacity(0.18), radius: 12)
    }

    private func toolButton(_ target: CanvasTool, symbol: String, label: String) -> some View {
        Button {
            tool = target
        } label: {
            Image(systemName: symbol)
                .frame(width: 44, height: 44)
        }
        .buttonStyle(.bordered)
        .tint(tool == target ? Palette.gold : Palette.graphiteSoft)
        .accessibilityLabel(label)
        .accessibilityAddTraits(tool == target ? .isSelected : [])
        .accessibilityIdentifier("tool-\(label.lowercased())")
    }
}

private extension RecoverableError.Kind {
    var isNetwork: Bool {
        if case .network = self { return true }
        return false
    }
}

private extension RecoverableError {
    var isRetryable: Bool {
        if case .network(let e) = kind { return e.isRetryable }
        return false
    }
}
