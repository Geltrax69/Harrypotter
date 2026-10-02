import SwiftUI

/// The inline confirmation slip. It reads back the recognized text ("I read…")
/// and offers three Pencil-friendly actions. There is deliberately no text
/// field: the recognized text is not editable by keyboard.
struct ConfirmationSlip: View {
    let recognizedText: String
    let onAskKiro: () -> Void
    let onKeepWriting: () -> Void
    let onStartOver: () -> Void

    var body: some View {
        VStack(alignment: .leading, spacing: 16) {
            VStack(alignment: .leading, spacing: 6) {
                Text("I read…")
                    .font(.subheadline.weight(.medium))
                    .foregroundStyle(Palette.graphiteSoft)
                    .accessibilityHidden(true)
                Text("\u{201C}\(recognizedText)\u{201D}")
                    .font(.title3.weight(.regular))
                    .foregroundStyle(Palette.graphite)
                    .fixedSize(horizontal: false, vertical: true)
            }
            .accessibilityElement(children: .combine)
            .accessibilityLabel("I read: \(recognizedText)")

            ViewThatFits(in: .horizontal) {
                HStack(spacing: 12) { actionButtons }
                VStack(spacing: 8) { actionButtons }
            }
        }
        .padding(20)
        .background(
            RoundedRectangle(cornerRadius: 18, style: .continuous)
                .fill(Palette.sheetEdge)
        )
        .accessibilityElement(children: .contain)
    }

    @ViewBuilder
    private var actionButtons: some View {
        Button(action: onAskKiro) {
            Label("Ask", systemImage: "arrow.up.circle.fill")
                .frame(maxWidth: .infinity, minHeight: 44, alignment: .center)
                .padding(.horizontal, 8)
        }
        .buttonStyle(.borderedProminent)
        .tint(Palette.indigo)
        .accessibilityIdentifier("ask-kiro")

        Button(action: onKeepWriting) {
            Label("Keep Writing", systemImage: "pencil.line")
                .frame(maxWidth: .infinity, minHeight: 44, alignment: .center)
        }
        .buttonStyle(.bordered)
        .tint(Palette.graphite)
        .accessibilityIdentifier("keep-writing")

        Button(role: .destructive, action: onStartOver) {
            Label("Start Over", systemImage: "arrow.counterclockwise")
                .frame(maxWidth: .infinity, minHeight: 44, alignment: .center)
        }
        .buttonStyle(.bordered)
        .accessibilityIdentifier("start-over")
    }
}
