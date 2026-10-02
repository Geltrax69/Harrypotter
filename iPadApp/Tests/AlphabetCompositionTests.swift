import Testing
import Foundation
import CoreGraphics
@testable import LivingPage

// MARK: - Preset coverage & alphabet

@Suite("Preset alphabet coverage")
struct AlphabetCoverageTests {
    private let requiredPunctuation = Array(". , ? ! ' \" - : ; ( ) / & + = % # @".split(separator: " ").map(String.init))

    @Test("Base alphabet covers A-Z, a-z, 0-9")
    func alphanumericCoverage() {
        for ch in "ABCDEFGHIJKLMNOPQRSTUVWXYZabcdefghijklmnopqrstuvwxyz0123456789" {
            #expect(BaseAlphabet.glyphs[String(ch)] != nil, "missing glyph \(ch)")
        }
    }

    @Test("Base alphabet covers required punctuation and the ? fallback")
    func punctuationCoverage() {
        for p in requiredPunctuation {
            #expect(BaseAlphabet.glyphs[p] != nil, "missing punctuation \(p)")
        }
        #expect(BaseAlphabet.glyphs[BaseAlphabet.fallbackKey] != nil)
    }

    @Test("Every glyph has at least one non-trivial stroke")
    func nonTrivialStrokes() {
        for (key, strokes) in BaseAlphabet.glyphs {
            #expect(!strokes.isEmpty, "\(key) has no strokes")
            let points = strokes.reduce(0) { $0 + $1.points.count }
            #expect(points >= 2, "\(key) is a single point, not recognizable geometry")
        }
    }

    @Test("Every preset hand renders all base characters")
    func presetsCoverEverything() {
        for style in HandwritingStyle.presets {
            let hand = PresetHand(style: style)
            for key in BaseAlphabet.glyphs.keys {
                #expect(hand.bank(for: key) != nil, "\(style) missing \(key)")
            }
        }
    }

    @Test("Presets have materially different metrics")
    func presetsDiffer() {
        let a = PresetHand(style: .uprightOpen).metrics
        let b = PresetHand(style: .quickSlanted).metrics
        let c = PresetHand(style: .compactRounded).metrics
        #expect(a.slant != b.slant)
        #expect(b.slant > a.slant) // slanted leans more than upright
        #expect(c.emHeight < a.emHeight) // rounded is more compact
        #expect(a.lineHeight != c.lineHeight)
    }
}

// MARK: - Deterministic composition

@Suite("Deterministic composition")
struct DeterministicCompositionTests {
    private func composer(_ style: HandwritingStyle = .uprightOpen) -> AnswerComposer {
        AnswerComposer(provider: PresetHand(style: style))
    }

    @Test("Same input yields byte-identical geometry")
    func deterministicGeometry() {
        let c = composer()
        let a = c.compose("Hello, Living Page!", width: 400)
        let b = c.compose("Hello, Living Page!", width: 400)
        #expect(a.glyphs == b.glyphs)
        #expect(a.bounds == b.bounds)
        #expect(a.totalStrokeCount == b.totalStrokeCount)
    }

    @Test("Glyphs preserve normalized content and source order")
    func sourceOrder() {
        let c = composer()
        let result = c.compose("abc", width: 400)
        let chars = result.glyphs.map(\.character)
        #expect(chars == ["a", "b", "c"])
        #expect(result.normalizedText == "abc")
    }

    @Test("A different style produces different geometry for the same text")
    func styleAffectsGeometry() {
        let upright = composer(.uprightOpen).compose("writing", width: 400)
        let slanted = composer(.quickSlanted).compose("writing", width: 400)
        #expect(upright.glyphs != slanted.glyphs)
    }
}

// MARK: - Wrapping and bounds

@Suite("Wrapping and bounds")
struct WrappingTests {
    private let composer = AnswerComposer(provider: PresetHand(style: .uprightOpen))

    @Test("Narrow page wraps into more lines than a wide page")
    func narrowWrapsMore() {
        let text = "the living page answers every question in flowing ink"
        let narrow = composer.compose(text, width: 160)
        let wide = composer.compose(text, width: 900)
        #expect(narrow.lineCount > wide.lineCount)
    }

    @Test("All ink stays within the page width bound")
    func withinWidth() {
        let width: CGFloat = 300
        let result = composer.compose("the living page answers questions", width: width, origin: CGPoint(x: 20, y: 0))
        // Right edge should not substantially exceed origin.x + width.
        #expect(result.bounds.maxX <= 20 + width + 40)
    }

    @Test("Explicit newlines create new lines")
    func newlineSupport() {
        let result = composer.compose("line one\nline two", width: 900)
        #expect(result.lineCount >= 2)
        let lines = Set(result.glyphs.map(\.line))
        #expect(lines.count >= 2)
    }

    @Test("An over-long word is broken and flagged")
    func longWordFallback() {
        let result = composer.compose("supercalifragilisticexpialidocious", width: 120)
        #expect(result.didBreakLongWord)
        #expect(result.lineCount >= 2)
    }

    @Test("Max height truncates and flags")
    func maxHeightTruncates() {
        let text = String(repeating: "word ", count: 200)
        let result = composer.compose(text, width: 200, maxHeight: 120)
        #expect(result.didTruncateForHeight)
    }
}

// MARK: - Punctuation & fallback

@Suite("Punctuation and unsupported fallback")
struct FallbackTests {
    private let composer = AnswerComposer(provider: PresetHand(style: .uprightOpen))

    @Test("Unsupported characters render a visible ? and are counted")
    func unsupportedFallback() {
        // Emoji / CJK are unsupported by the Latin alphabet.
        let result = composer.compose("hi \u{4E2D}\u{6587}", width: 400)
        #expect(result.unsupportedCharacterCount == 2)
        // The fallback glyphs are present and flagged.
        let fallbacks = result.glyphs.filter { $0.isFallbackGlyph }
        #expect(fallbacks.count == 2)
        #expect(fallbacks.allSatisfy { $0.character == "?" })
    }

    @Test("Supported punctuation is not treated as fallback")
    func punctuationNotFallback() {
        let result = composer.compose("a.b,c?d!", width: 400)
        #expect(result.unsupportedCharacterCount == 0)
        #expect(result.glyphs.allSatisfy { !$0.isFallbackGlyph })
    }

    @Test("Accented English folds to base Latin, not fallback")
    func accentFolding() {
        let result = composer.compose("caf\u{00E9}", width: 400)
        #expect(result.unsupportedCharacterCount == 0)
    }
}
