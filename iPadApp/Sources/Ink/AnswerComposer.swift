import Foundation
import CoreGraphics

/// Normalizes an answer string to the English/Latin subset the alphabet renders.
/// Unsupported characters are preserved as-is so the composer can substitute a
/// VISIBLE `?` glyph and count it (rather than silently dropping content).
public enum AnswerTextNormalizer {
    /// Folds accents to ASCII where possible, normalizes curly quotes/dashes to
    /// the authored punctuation, collapses horizontal whitespace, and keeps
    /// explicit newlines. Does not strip unsupported characters — that decision
    /// belongs to the composer so it can render a visible fallback.
    public static func normalize(_ raw: String) -> String {
        // Map common typographic variants onto authored punctuation.
        var mapped = raw
            .replacingOccurrences(of: "\u{2018}", with: "'")
            .replacingOccurrences(of: "\u{2019}", with: "'")
            .replacingOccurrences(of: "\u{201C}", with: "\"")
            .replacingOccurrences(of: "\u{201D}", with: "\"")
            .replacingOccurrences(of: "\u{2013}", with: "-")
            .replacingOccurrences(of: "\u{2014}", with: "-")
            .replacingOccurrences(of: "\u{2026}", with: "...")
            .replacingOccurrences(of: "\t", with: " ")
            .replacingOccurrences(of: "\r\n", with: "\n")
            .replacingOccurrences(of: "\r", with: "\n")

        // Fold diacritics to base Latin letters (é -> e) so accented English
        // renders instead of falling back to '?'.
        mapped = mapped.folding(options: .diacriticInsensitive, locale: Locale(identifier: "en_US"))

        // Collapse runs of spaces (but keep newlines).
        let lines = mapped.split(separator: "\n", omittingEmptySubsequences: false).map { line -> String in
            line.split(whereSeparator: { $0 == " " }).joined(separator: " ")
        }
        return lines.joined(separator: "\n")
    }
}

/// Lays out normalized text into placed vector glyphs using a `GlyphProviding`
/// hand, with an optional preset fallback provider for Personal missing glyphs.
///
/// Layout is fully deterministic given the same inputs (text, width, providers,
/// seed): variant selection and bounded jitter derive from a stable seed, so
/// tests can assert exact geometry.
public struct AnswerComposer: Sendable {
    private let provider: GlyphProviding
    /// Used only when `provider` is a Personal profile that lacks a glyph; a
    /// preset fills the gap. When `provider` is itself a preset, this is nil.
    private let fallbackProvider: GlyphProviding?
    private let seed: UInt64

    public init(provider: GlyphProviding, fallbackProvider: GlyphProviding? = nil, seed: UInt64 = 0x5EED) {
        self.provider = provider
        self.fallbackProvider = fallbackProvider
        self.seed = seed
    }

    /// Compose `text` into placed glyphs within `width` points and at most
    /// `maxHeight` points. `origin` is the top-left of the answer block in page
    /// coordinates; layout begins at the first baseline below it.
    /// `ruleSpacing`, when set, snaps baselines onto the page's ruled lines
    /// (absolute multiples of the spacing) so the answer sits on the rules.
    public func compose(
        _ text: String,
        width: CGFloat,
        maxHeight: CGFloat = .greatestFiniteMagnitude,
        origin: CGPoint = .zero,
        ruleSpacing: CGFloat? = nil
    ) -> ComposedAnswer {
        let normalized = AnswerTextNormalizer.normalize(text)
        let em = provider.metrics.emHeight
        var lineHeight = provider.metrics.lineHeight * em
        if let rule = ruleSpacing, rule > 0 {
            lineHeight = max(1, (lineHeight / rule).rounded()) * rule
        }

        var glyphs: [ComposedGlyph] = []
        var unsupported = 0
        var personalFallback = 0
        var didBreakLongWord = false
        var didTruncate = false

        // Compose seed folds the text so identical answers reproduce exactly.
        let composeSeed = seed ^ DeterministicRandom.seed(for: normalized)

        var lineIndex = 0
        var penX: CGFloat = 0
        // First baseline sits one line-height below the block origin (or on
        // the first rule below the glyph height when snapping to rules).
        var baselineY = origin.y + lineHeight
        if let rule = ruleSpacing, rule > 0 {
            baselineY = ((origin.y + em) / rule).rounded(.up) * rule
        }
        var position = 0 // monotonic glyph position for deterministic variants

        // Track minima/maxima for bounds.
        var minX = CGFloat.greatestFiniteMagnitude
        var minY = CGFloat.greatestFiniteMagnitude
        var maxX = -CGFloat.greatestFiniteMagnitude
        var maxY = -CGFloat.greatestFiniteMagnitude

        func advanceLine() {
            lineIndex += 1
            penX = 0
            baselineY += lineHeight
        }

        // Split into paragraphs on explicit newlines; wrap each independently.
        let paragraphs = normalized.split(separator: "\n", omittingEmptySubsequences: false).map(String.init)

        outer: for (pIdx, paragraph) in paragraphs.enumerated() {
            if pIdx > 0 { advanceLine() } // newline starts a fresh line
            let words = paragraph.split(separator: " ", omittingEmptySubsequences: true).map(String.init)

            for word in words {
                // Tokenize the word into longest-match units (ligatures first).
                let units = tokenize(word)
                let wordWidth = measure(units)

                // Word-aware wrap: if the word doesn't fit and the line isn't
                // empty, move to the next line first.
                if penX > 0, penX + CGFloat(wordWidth) * em > width {
                    advanceLine()
                }

                // Long-word fallback: a single word wider than the line is
                // broken unit-by-unit at the margin.
                if CGFloat(wordWidth) * em > width {
                    didBreakLongWord = true
                }

                for unit in units {
                    let unitAdvance = unitAdvanceEm(unit)
                    // Break within an over-long word.
                    if penX > 0, penX + CGFloat(unitAdvance) * em > width {
                        advanceLine()
                    }
                    if baselineY + em > origin.y + maxHeight {
                        didTruncate = true
                        break outer
                    }
                    let placed = placeUnit(
                        unit, atPenX: origin.x + penX, baselineY: baselineY, em: em,
                        lineIndex: lineIndex, position: position, seed: composeSeed,
                        unsupported: &unsupported, personalFallback: &personalFallback
                    )
                    for g in placed.glyphs {
                        for st in g.strokes {
                            for p in st.points {
                                minX = min(minX, CGFloat(p.x)); maxX = max(maxX, CGFloat(p.x))
                                minY = min(minY, CGFloat(p.y)); maxY = max(maxY, CGFloat(p.y))
                            }
                        }
                        glyphs.append(g)
                    }
                    penX += CGFloat(placed.advance) * em
                    position += 1
                }

                // Word space (with rhythm multiplier).
                penX += CGFloat(provider.metrics.spaceAdvance * provider.metrics.wordSpacingMultiplier) * em
            }
        }

        let bounds: CGRect
        if glyphs.isEmpty {
            bounds = CGRect(origin: origin, size: .zero)
        } else {
            bounds = CGRect(x: minX, y: minY, width: maxX - minX, height: maxY - minY)
        }

        return ComposedAnswer(
            glyphs: glyphs,
            lineCount: lineIndex + 1,
            bounds: bounds,
            normalizedText: normalized,
            unsupportedCharacterCount: unsupported,
            personalMissingGlyphFallbackCount: personalFallback,
            didTruncateForHeight: didTruncate,
            didBreakLongWord: didBreakLongWord
        )
    }

    // MARK: - Tokenization (longest-match ligatures)

    /// Splits a word into render units, preferring the longest available
    /// ligature key at each position. Single characters otherwise.
    private func tokenize(_ word: String) -> [String] {
        let ligatures = provider.ligatureKeys.sorted { $0.count > $1.count }
        let chars = Array(word)
        var units: [String] = []
        var i = 0
        while i < chars.count {
            var matched: String?
            for lig in ligatures where lig.count <= chars.count - i {
                let slice = String(chars[i..<(i + lig.count)])
                if slice == lig, provider.bank(for: lig) != nil {
                    matched = lig
                    break
                }
            }
            if let m = matched {
                units.append(m)
                i += m.count
            } else {
                units.append(String(chars[i]))
                i += 1
            }
        }
        return units
    }

    // MARK: - Measurement

    private func unitAdvanceEm(_ unit: String) -> Double {
        if let bank = provider.bank(for: unit), let v = bank.variants.first {
            return v.advance + provider.metrics.letterSpacing
        }
        if let fb = fallbackProvider, let bank = fb.bank(for: unit), let v = bank.variants.first {
            return v.advance + provider.metrics.letterSpacing
        }
        // Fallback '?' width.
        return BaseAlphabet.advance(for: "?") + provider.metrics.letterSpacing
    }

    private func measure(_ units: [String]) -> Double {
        units.reduce(0) { $0 + unitAdvanceEm($1) }
    }

    // MARK: - Placement

    private struct PlacedUnit { let glyphs: [ComposedGlyph]; let advance: Double }

    private func placeUnit(
        _ unit: String, atPenX penX: CGFloat, baselineY: CGFloat, em: CGFloat,
        lineIndex: Int, position: Int, seed: UInt64,
        unsupported: inout Int, personalFallback: inout Int
    ) -> PlacedUnit {
        // Resolve variant: provider first, then preset fallback, then '?'.
        var chosenBank = provider.bank(for: unit)
        var isFallbackGlyph = false
        if chosenBank == nil, let fb = fallbackProvider, let b = fb.bank(for: unit) {
            chosenBank = b
            personalFallback += 1
        }
        if chosenBank == nil {
            // Visible '?' substitution for a truly unsupported character.
            let fbProvider = fallbackProvider ?? provider
            chosenBank = fbProvider.bank(for: BaseAlphabet.fallbackKey)
            isFallbackGlyph = true
            unsupported += 1
        }
        guard let bank = chosenBank,
              let variant = bank.variant(position: position, seed: seed) else {
            return PlacedUnit(glyphs: [], advance: provider.metrics.spaceAdvance)
        }

        // Bounded per-glyph slant/baseline/spacing variation, deterministic.
        let m = provider.metrics
        let slant = m.slant + DeterministicRandom.signedUnit(seed: seed, salt: UInt64(position) &* 3 &+ 1) * m.slantJitter
        let baseOffset = DeterministicRandom.signedUnit(seed: seed, salt: UInt64(position) &* 3 &+ 2) * m.baselineJitter * Double(em)
        let spacingMul = 1 + DeterministicRandom.signedUnit(seed: seed, salt: UInt64(position) &* 3 &+ 3) * m.spacingJitter
        let sizeMul = 1 + CGFloat(DeterministicRandom.signedUnit(seed: seed, salt: UInt64(position) &* 7 &+ 5)) * 0.07
        let drift = sin(Double(penX) / 170 + Double(lineIndex) * 1.7) * 0.05 * Double(em)

        let placedStrokes: [InkStroke] = variant.strokes.map { stroke in
            stroke.mappingPoints { p -> InkPoint in
                // Em -> points, apply slant as horizontal shear about baseline.
                let localX = CGFloat(p.x) * em * sizeMul
                let localY = CGFloat(p.y) * em * sizeMul
                let shearX = CGFloat(slant) * (-localY)
                var np = p
                np.x = Double(penX + localX + shearX)
                np.y = Double(baselineY + localY) + baseOffset + drift
                return np
            }
        }

        let glyph = ComposedGlyph(
            character: isFallbackGlyph ? BaseAlphabet.fallbackKey : unit,
            strokes: placedStrokes,
            line: lineIndex,
            isFallbackGlyph: isFallbackGlyph
        )
        return PlacedUnit(glyphs: [glyph], advance: variant.advance * spacingMul + m.letterSpacing)
    }
}
