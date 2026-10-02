import Testing
import Foundation
import PencilKit
@testable import LivingPage

/// Optional recognition round-trip / Character Error Rate (CER) harness.
///
/// This composes preset (and, when a profile exists, personal) ink for known
/// strings, feeds the resulting `PKDrawing` to the on-device
/// `PKStrokeRecognizer`, and measures CER against the source text.
///
/// IMPORTANT VALIDATION NOTE:
/// `PKStrokeRecognizer` uses on-device handwriting models whose quality is only
/// representative on PHYSICAL hardware. Results gathered on the iOS Simulator are
/// NOT valid device evidence and are therefore NOT asserted here. On the
/// Simulator this suite records the measured CER as informational output and
/// always passes; the pass/fail thresholds (≤5% preset, ≤10% personal) are only
/// enforced when running on a real device (detected via the absence of the
/// `SIMULATOR_DEVICE_NAME` environment variable) AND when opt-in is requested via
/// the `LIVINGPAGE_RUN_CER` environment flag.
@Suite("Recognizer round-trip CER (device-only thresholds)")
struct RecognizerRoundTripTests {

    private var isSimulator: Bool {
        ProcessInfo.processInfo.environment["SIMULATOR_DEVICE_NAME"] != nil
    }
    private var optedIn: Bool {
        ProcessInfo.processInfo.environment["LIVINGPAGE_RUN_CER"] == "1"
    }

    /// Levenshtein-based character error rate in `0...1`.
    private func cer(recognized: String, expected: String) -> Double {
        let a = Array(recognized.lowercased())
        let b = Array(expected.lowercased())
        if b.isEmpty { return a.isEmpty ? 0 : 1 }
        var prev = Array(0...b.count)
        var cur = [Int](repeating: 0, count: b.count + 1)
        for i in 1...max(a.count, 1) {
            cur[0] = i
            for j in 1...b.count {
                if i <= a.count && a[i - 1] == b[j - 1] {
                    cur[j] = prev[j - 1]
                } else {
                    cur[j] = 1 + min(prev[j], cur[j - 1], prev[j - 1])
                }
            }
            swap(&prev, &cur)
        }
        return Double(prev[b.count]) / Double(b.count)
    }

    @Test("Preset ink round-trips through the recognizer")
    func presetRoundTrip() async throws {
        guard optedIn else { return } // opt-in only; skipped by default
        let expected = "the living page"
        let composer = AnswerComposer(provider: PresetHand(style: .uprightOpen))
        let composed = composer.compose(expected, width: 800, origin: .init(x: 40, y: 40))
        let drawing = InkStrokeBuilder.drawing(from: composed, width: 4)

        let recognizer = PKStrokeRecognizer(preferredLanguages: [Locale.Language(identifier: "en")])
        await recognizer.updateDrawing(drawing)
        let recognized = await recognizer.recognizedText() ?? ""
        let rate = cer(recognized: recognized, expected: expected)

        if isSimulator {
            // Informational only — NOT device evidence.
            print("[CER][simulator][preset] recognized=\"\(recognized)\" cer=\(rate) (informational, not device evidence)")
        } else {
            // Enforced on physical hardware only.
            #expect(rate <= 0.05, "preset CER \(rate) exceeded 5% device target")
        }
    }

    @Test("Personal ink round-trips through the recognizer")
    func personalRoundTrip() async throws {
        guard optedIn else { return }
        let expected = "living ink"
        let personal = PersonalHand(profile: SyntheticProfile.usable())
        let composer = AnswerComposer(provider: personal, fallbackProvider: PresetHand(style: .uprightOpen))
        let composed = composer.compose(expected, width: 800, origin: .init(x: 40, y: 40))
        let drawing = InkStrokeBuilder.drawing(from: composed, width: 4)

        let recognizer = PKStrokeRecognizer(preferredLanguages: [Locale.Language(identifier: "en")])
        await recognizer.updateDrawing(drawing)
        let recognized = await recognizer.recognizedText() ?? ""
        let rate = cer(recognized: recognized, expected: expected)

        if isSimulator {
            print("[CER][simulator][personal] recognized=\"\(recognized)\" cer=\(rate) (informational, not device evidence)")
        } else {
            #expect(rate <= 0.10, "personal CER \(rate) exceeded 10% device target")
        }
    }
}
