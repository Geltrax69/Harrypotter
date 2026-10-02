import Foundation

/// The calibration plan: an ordered set of sections, each a list of prompted
/// tokens. Signatures are explicitly NOT part of any section and are never
/// requested (see the copy in `CalibrationSection`).
public enum CalibrationSectionKind: String, Codable, Sendable, CaseIterable {
    case lowercasePrimary
    case lowercaseVariation
    case uppercasePrimary
    case uppercaseVariation
    case numerals
    case punctuation
    case ligatures
    case rhythmPhrases
}

/// A prompted token to capture, plus whether it is a phrase (used to derive
/// rhythm metrics rather than a single glyph).
///
/// The same visible token (e.g. "a") is prompted in both a primary and a
/// variation section, so `token` is NOT unique across the plan. Progress and
/// variant placement therefore key off `promptID` (section kind + local index),
/// which is stable and unique, and `variantSlot`, which deterministically
/// routes the primary capture to variant slot 0 and the variation capture to
/// slot 1 of the same glyph bank.
public struct CalibrationPrompt: Codable, Sendable, Equatable, Identifiable {
    public var token: String
    public var isPhrase: Bool
    /// Stable, plan-unique identifier: "<sectionKind>#<indexWithinSection>".
    public var promptID: String
    /// Which variant slot this capture occupies within the token's glyph bank.
    /// Primary sections use slot 0; variation sections use slot 1. Phrases use 0.
    public var variantSlot: Int
    public var id: String { promptID }
    public init(token: String, isPhrase: Bool = false, promptID: String, variantSlot: Int = 0) {
        self.token = token
        self.isPhrase = isPhrase
        self.promptID = promptID
        self.variantSlot = variantSlot
    }
}

public struct CalibrationSection: Codable, Sendable, Equatable, Identifiable {
    public var kind: CalibrationSectionKind
    public var title: String
    public var prompts: [CalibrationPrompt]
    public var id: String { kind.rawValue }

    public init(kind: CalibrationSectionKind, title: String, prompts: [CalibrationPrompt]) {
        self.kind = kind
        self.title = title
        self.prompts = prompts
    }
}

/// The full plan. Fixed and deterministic so progress indices stay stable.
public enum CalibrationPlan {
    public static let sections: [CalibrationSection] = build()

    /// Flat list of every prompted token in order (used for overall progress).
    public static var allTokens: [String] { sections.flatMap { $0.prompts.map(\.token) } }

    /// Every stable prompt ID in the plan, in order.
    public static var allPromptIDs: [String] { sections.flatMap { $0.prompts.map(\.promptID) } }

    /// Non-phrase tokens that should become glyph banks.
    public static var glyphTokens: [String] {
        sections.flatMap { $0.prompts }.filter { !$0.isPhrase }.map(\.token)
    }

    /// Variation sections capture a second natural pass and route to variant
    /// slot 1; primary sections route to slot 0.
    static func variantSlot(for kind: CalibrationSectionKind) -> Int {
        switch kind {
        case .lowercaseVariation, .uppercaseVariation: return 1
        default: return 0
        }
    }

    private static func prompts(
        _ tokens: [String], kind: CalibrationSectionKind, isPhrase: Bool = false
    ) -> [CalibrationPrompt] {
        let slot = variantSlot(for: kind)
        return tokens.enumerated().map { index, token in
            CalibrationPrompt(
                token: token,
                isPhrase: isPhrase,
                promptID: "\(kind.rawValue)#\(index)",
                variantSlot: slot
            )
        }
    }

    private static func build() -> [CalibrationSection] {
        let lowerTokens = "abcdefghijklmnopqrstuvwxyz".map(String.init)
        let upperTokens = "ABCDEFGHIJKLMNOPQRSTUVWXYZ".map(String.init)
        let digitTokens = "0123456789".map(String.init)
        let punctTokens = [".", ",", "?", "!", "'", "-", ":", ";", "(", ")"]
        // Minimum required ligatures plus a few more common ones.
        let ligTokens = ["th", "he", "in", "er", "an", "re", "on", "at"]
        let phraseTokens = ["the quick brown fox", "living page answers in ink"]
        return [
            CalibrationSection(kind: .lowercasePrimary, title: "Lowercase letters",
                               prompts: prompts(lowerTokens, kind: .lowercasePrimary)),
            CalibrationSection(kind: .lowercaseVariation, title: "Lowercase again, naturally",
                               prompts: prompts(lowerTokens, kind: .lowercaseVariation)),
            CalibrationSection(kind: .uppercasePrimary, title: "Uppercase letters",
                               prompts: prompts(upperTokens, kind: .uppercasePrimary)),
            CalibrationSection(kind: .uppercaseVariation, title: "Uppercase again, naturally",
                               prompts: prompts(upperTokens, kind: .uppercaseVariation)),
            CalibrationSection(kind: .numerals, title: "Numbers",
                               prompts: prompts(digitTokens, kind: .numerals)),
            CalibrationSection(kind: .punctuation, title: "Punctuation",
                               prompts: prompts(punctTokens, kind: .punctuation)),
            CalibrationSection(kind: .ligatures, title: "Common letter pairs",
                               prompts: prompts(ligTokens, kind: .ligatures)),
            CalibrationSection(kind: .rhythmPhrases, title: "Two short phrases (not a signature)",
                               prompts: prompts(phraseTokens, kind: .rhythmPhrases, isPhrase: true)),
        ]
    }
}

/// Resumable calibration progress: which section/prompt the user is on, and
/// which prompts have saved samples. Persisted locally as JSON.
///
/// Schema v2 keys saved state off stable `savedPromptIDs` (section kind + local
/// index) rather than raw tokens, because the same token is prompted in both a
/// primary and a variation section. Keying off tokens made variation sections
/// look pre-complete and capped overall progress below 100%.
///
/// V1 MIGRATION SAFETY: a v1 file stored only `savedTokens`. A legacy token
/// carries NO information about which pass (primary vs variation) produced it,
/// so crediting BOTH prompts would let an old, single-pass profile falsely
/// claim the variation pass is already complete. To stay conservative, each
/// legacy token is credited to ONLY the FIRST matching prompt in plan order —
/// which is always the primary section — leaving the variation prompt unsaved.
/// The user is then correctly asked to complete the variation pass, and overall
/// progress is never inflated.
public struct CalibrationProgress: Codable, Sendable, Equatable {
    public static let currentVersion = 2
    public var version: Int
    /// Index into `CalibrationPlan.sections`.
    public var sectionIndex: Int
    /// Index into the current section's prompts.
    public var promptIndex: Int
    /// Stable prompt IDs that have at least one saved sample.
    public var savedPromptIDs: Set<String>

    public init(
        version: Int = CalibrationProgress.currentVersion,
        sectionIndex: Int = 0,
        promptIndex: Int = 0,
        savedPromptIDs: Set<String> = []
    ) {
        self.version = version
        self.sectionIndex = sectionIndex
        self.promptIndex = promptIndex
        self.savedPromptIDs = savedPromptIDs
    }

    /// Conservatively maps a set of visible tokens to prompt IDs, crediting each
    /// token to ONLY the first matching prompt in plan order (the primary
    /// section). This is the safe migration/back-compat mapping: an old
    /// token-based record cannot claim a variation pass it never captured.
    static func primaryPromptIDs(forTokens tokens: Set<String>) -> Set<String> {
        var ids: Set<String> = []
        var creditedTokens: Set<String> = []
        // `CalibrationPlan.sections` is ordered primary-before-variation, so the
        // first prompt encountered for a token is its primary prompt.
        for section in CalibrationPlan.sections {
            for prompt in section.prompts
            where tokens.contains(prompt.token) && !creditedTokens.contains(prompt.token) {
                ids.insert(prompt.promptID)
                creditedTokens.insert(prompt.token)
            }
        }
        return ids
    }

    /// Backwards-compatible initializer that accepts visible tokens. To stay
    /// consistent with the safe migration policy, each token is credited to only
    /// its FIRST (primary) matching prompt — never the variation prompt — so a
    /// token-based record cannot inflate progress by implying a variation pass.
    /// Kept so existing tests/API that think in terms of tokens keep working.
    public init(
        version: Int = CalibrationProgress.currentVersion,
        sectionIndex: Int = 0,
        promptIndex: Int = 0,
        savedTokens: Set<String>
    ) {
        let ids = CalibrationProgress.primaryPromptIDs(forTokens: savedTokens)
        self.init(version: version, sectionIndex: sectionIndex, promptIndex: promptIndex, savedPromptIDs: ids)
    }

    /// Backwards-compatible token view: the set of visible tokens that have at
    /// least one saved prompt. Kept for tests/API convenience; NOT used for
    /// progress math (which uses `savedPromptIDs`).
    public var savedTokens: Set<String> {
        var tokens: Set<String> = []
        let byID = CalibrationProgress.promptsByID
        for id in savedPromptIDs {
            if let token = byID[id]?.token { tokens.insert(token) }
        }
        return tokens
    }

    private static let promptsByID: [String: CalibrationPrompt] = {
        var map: [String: CalibrationPrompt] = [:]
        for section in CalibrationPlan.sections {
            for prompt in section.prompts { map[prompt.promptID] = prompt }
        }
        return map
    }()

    // MARK: - Codable with migration

    private enum CodingKeys: String, CodingKey {
        case version, sectionIndex, promptIndex, savedPromptIDs, savedTokens
    }

    public init(from decoder: Decoder) throws {
        let c = try decoder.container(keyedBy: CodingKeys.self)
        let decodedVersion = try c.decodeIfPresent(Int.self, forKey: .version) ?? 1
        self.sectionIndex = try c.decodeIfPresent(Int.self, forKey: .sectionIndex) ?? 0
        self.promptIndex = try c.decodeIfPresent(Int.self, forKey: .promptIndex) ?? 0

        if let ids = try c.decodeIfPresent(Set<String>.self, forKey: .savedPromptIDs) {
            self.savedPromptIDs = ids
            self.version = CalibrationProgress.currentVersion
        } else if let legacyTokens = try c.decodeIfPresent(Set<String>.self, forKey: .savedTokens) {
            // v1 -> v2 migration (SAFE): credit each legacy token to ONLY its
            // first/primary matching prompt, never the variation prompt. A v1
            // record carries no primary-vs-variation distinction, so crediting
            // both would let a single-pass profile falsely claim the variation
            // pass is complete and inflate overall progress. Conservatively
            // crediting the primary prompt keeps the variation pass correctly
            // pending.
            self.savedPromptIDs = CalibrationProgress.primaryPromptIDs(forTokens: legacyTokens)
            self.version = CalibrationProgress.currentVersion
        } else {
            self.savedPromptIDs = []
            self.version = decodedVersion
        }
    }

    public func encode(to encoder: Encoder) throws {
        var c = encoder.container(keyedBy: CodingKeys.self)
        try c.encode(version, forKey: .version)
        try c.encode(sectionIndex, forKey: .sectionIndex)
        try c.encode(promptIndex, forKey: .promptIndex)
        try c.encode(savedPromptIDs, forKey: .savedPromptIDs)
    }

    /// Overall fraction of prompts saved (0...1). Reaches 1.0 only when every
    /// prompt — primary AND variation — has a sample.
    public var overallFraction: Double {
        let total = CalibrationPlan.allPromptIDs.count
        guard total > 0 else { return 0 }
        return Double(savedPromptIDs.count) / Double(total)
    }

    /// Fraction of the current section's prompts saved (0...1).
    public func sectionFraction() -> Double {
        guard sectionIndex < CalibrationPlan.sections.count else { return 1 }
        let prompts = CalibrationPlan.sections[sectionIndex].prompts
        guard !prompts.isEmpty else { return 1 }
        let saved = prompts.filter { savedPromptIDs.contains($0.promptID) }.count
        return Double(saved) / Double(prompts.count)
    }
}
