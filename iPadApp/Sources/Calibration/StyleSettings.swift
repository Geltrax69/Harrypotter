import Foundation

/// A minimal, injectable key-value abstraction so the selected style can be
/// persisted without hard-coupling to `UserDefaults.standard` (tests inject an
/// in-memory implementation).
public protocol KeyValueStoring: Sendable {
    func string(forKey key: String) -> String?
    func set(_ value: String?, forKey key: String)
}

extension UserDefaults: KeyValueStoring, @unchecked @retroactive Sendable {
    public func set(_ value: String?, forKey key: String) {
        if let value { self.setValue(value, forKey: key) }
        else { self.removeObject(forKey: key) }
    }
}

/// In-memory key-value store for tests.
public final class InMemoryKeyValueStore: KeyValueStoring, @unchecked Sendable {
    private let lock = NSLock()
    private var values: [String: String] = [:]
    public init() {}
    public func string(forKey key: String) -> String? {
        lock.lock(); defer { lock.unlock() }; return values[key]
    }
    public func set(_ value: String?, forKey key: String) {
        lock.lock(); defer { lock.unlock() }
        if let value { values[key] = value } else { values.removeValue(forKey: key) }
    }
}

/// Persists the user's selected handwriting style via an injected store.
public struct StyleSettings: Sendable {
    public static let styleKey = "livingpage.handwritingStyle"
    private let store: KeyValueStoring

    public init(store: KeyValueStoring) { self.store = store }

    public var selectedStyle: HandwritingStyle {
        get {
            guard let raw = store.string(forKey: Self.styleKey),
                  let style = HandwritingStyle(rawValue: raw) else {
                return .uprightOpen
            }
            return style
        }
        nonmutating set {
            store.set(newValue.rawValue, forKey: Self.styleKey)
        }
    }
}

/// Resolves the active `GlyphProviding` for a selected style, applying the
/// Personal→preset fallback rule. When Personal is selected but no usable
/// profile exists, the resolver returns the fallback preset and reports that
/// calibration is required.
public struct HandResolver: Sendable {
    /// The preset a Personal profile falls back to for missing glyphs and when
    /// no usable profile exists.
    public let fallbackPreset: HandwritingStyle

    public init(fallbackPreset: HandwritingStyle = .uprightOpen) {
        self.fallbackPreset = fallbackPreset
    }

    public struct Resolved: Sendable {
        public let provider: GlyphProviding
        /// Non-nil only when the primary provider is Personal: the preset used
        /// to fill missing glyphs.
        public let fallbackProvider: GlyphProviding?
        /// True when Personal was requested but no usable profile exists, so the
        /// UI should surface "Finish calibration".
        public let needsCalibration: Bool
    }

    public func resolve(style: HandwritingStyle, profile: HandwritingProfile?) -> Resolved {
        switch style {
        case .uprightOpen, .quickSlanted, .compactRounded:
            return Resolved(provider: PresetHand(style: style), fallbackProvider: nil, needsCalibration: false)
        case .personal:
            let preset = PresetHand(style: fallbackPreset)
            if let profile, profile.isUsable {
                return Resolved(
                    provider: PersonalHand(profile: profile),
                    fallbackProvider: preset,
                    needsCalibration: false
                )
            }
            // Graceful fallback: behave like the preset, flag calibration needed.
            return Resolved(provider: preset, fallbackProvider: nil, needsCalibration: true)
        }
    }
}
