import SwiftUI

/// Recovery UI shown on recognition or network failure. The user's ink is always
/// preserved by the model; the preserved recognized text (when present) is shown
/// so nothing feels lost. Actions adapt to what makes sense for the failure.
struct RecoverySlip: View {
    let error: RecoverableError
    /// Provided only when retrying the same request is sensible.
    let onRetry: (() -> Void)?
    let onKeepWriting: () -> Void
    let onStartOver: () -> Void

    var body: some View {
        VStack(alignment: .leading, spacing: 14) {
            Label(error.message, systemImage: "exclamationmark.circle")
                .font(.headline.weight(.regular))
                .foregroundStyle(Palette.indigo)
                .fixedSize(horizontal: false, vertical: true)
                .accessibilityIdentifier("error-message")

            if let text = error.recognizedText {
                Text("\u{201C}\(text)\u{201D}")
                    .font(.subheadline)
                    .foregroundStyle(Palette.graphiteSoft)
                    .fixedSize(horizontal: false, vertical: true)
            }

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
        if let onRetry {
            Button(action: onRetry) {
                Label("Try Again", systemImage: "arrow.clockwise")
                    .frame(maxWidth: .infinity, minHeight: 44, alignment: .center)
            }
            .buttonStyle(.borderedProminent)
            .tint(Palette.indigo)
            .accessibilityIdentifier("retry")
        }

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
