import Foundation

/// Abstraction over profile + progress persistence so tests can inject a
/// temporary directory and assert atomic, protected, backup-excluded writes.
public protocol HandwritingProfileStoring: Sendable {
    func loadProfile() -> HandwritingProfile?
    func saveProfile(_ profile: HandwritingProfile) throws
    func deleteProfile() throws
    func loadProgress() -> CalibrationProgress?
    func saveProgress(_ progress: CalibrationProgress) throws
    func deleteProgress() throws
}

public enum ProfileStoreError: Error, Equatable {
    case encodingFailed
    case writeFailed
    /// A physical-device write could not apply data protection and was refused
    /// rather than silently downgrading to an unprotected file.
    case protectedWriteUnavailable
}

/// Stores the handwriting profile + calibration progress as local JSON in
/// Application Support.
///
/// Guarantees:
/// - Atomic writes (`.atomic`) so a crash never leaves a torn file.
/// - `FileProtectionType.completeUntilFirstUserAuthentication` (or stronger).
/// - Excluded from iCloud/iTunes backup via `isExcludedFromBackup`.
/// - Corruption/version recovery: unreadable or future-version files are
///   discarded and treated as "no profile", never crashing the app.
public struct FileHandwritingProfileStore: HandwritingProfileStoring {
    private let directory: URL
    private let profileURL: URL
    private let progressURL: URL
    /// When true, a protected write that fails may fall back to an unprotected
    /// atomic write. This is permitted ONLY in the Simulator or when an explicit
    /// test directory is injected; on a physical device a protection failure
    /// MUST surface as an error rather than silently downgrading privacy.
    private let allowsUnprotectedFallback: Bool

    /// A fresh `FileManager.default` per call keeps this type `Sendable`.
    private var fileManager: FileManager { .default }

    /// True when running in the iOS Simulator (no Secure Enclave / data
    /// protection guarantees), detected via the simulator environment.
    private static var isSimulator: Bool {
        ProcessInfo.processInfo.environment["SIMULATOR_DEVICE_NAME"] != nil
    }

    public init(directory: URL? = nil) {
        let fileManager = FileManager.default
        let base: URL
        // An injected directory implies a test/sandbox context; the default
        // Application Support path implies production device storage.
        let injectedDirectory = directory != nil
        if let directory {
            base = directory
        } else {
            let appSupport = (try? fileManager.url(
                for: .applicationSupportDirectory, in: .userDomainMask,
                appropriateFor: nil, create: true
            )) ?? fileManager.temporaryDirectory
            base = appSupport.appendingPathComponent("Handwriting", isDirectory: true)
        }
        self.directory = base
        self.profileURL = base.appendingPathComponent("profile.json")
        self.progressURL = base.appendingPathComponent("progress.json")
        // Only relax protection when we are NOT on a physical device: either the
        // Simulator, or a test that injected its own directory.
        self.allowsUnprotectedFallback = FileHandwritingProfileStore.isSimulator || injectedDirectory
        try? ensureDirectory()
    }

    private func ensureDirectory() throws {
        if !fileManager.fileExists(atPath: directory.path) {
            try fileManager.createDirectory(at: directory, withIntermediateDirectories: true)
        }
        // Protect the profile directory itself, not just the files within it.
        applyProtection(directory)
        excludeFromBackup(directory)
    }

    // MARK: - Profile

    public func loadProfile() -> HandwritingProfile? {
        decode(HandwritingProfile.self, from: profileURL) { profile in
            // Version recovery: refuse to load a newer schema than we understand.
            profile.version <= HandwritingProfile.currentVersion
        }
    }

    public func saveProfile(_ profile: HandwritingProfile) throws {
        try writeJSON(profile, to: profileURL)
    }

    public func deleteProfile() throws {
        try removeIfExists(profileURL)
    }

    // MARK: - Progress

    public func loadProgress() -> CalibrationProgress? {
        decode(CalibrationProgress.self, from: progressURL) { progress in
            progress.version <= CalibrationProgress.currentVersion
        }
    }

    public func saveProgress(_ progress: CalibrationProgress) throws {
        try writeJSON(progress, to: progressURL)
    }

    public func deleteProgress() throws {
        try removeIfExists(progressURL)
    }

    // MARK: - Shared helpers

    private func decode<T: Decodable>(_ type: T.Type, from url: URL, accept: (T) -> Bool) -> T? {
        guard let data = try? Data(contentsOf: url) else { return nil }
        // Corruption recovery: a decode failure yields nil (treated as absent),
        // and the corrupt file is removed so the next save starts clean.
        guard let value = try? JSONDecoder().decode(T.self, from: data) else {
            try? removeIfExists(url)
            return nil
        }
        guard accept(value) else { return nil }
        return value
    }

    private func writeJSON<T: Encodable>(_ value: T, to url: URL) throws {
        try? ensureDirectory()
        let encoder = JSONEncoder()
        encoder.outputFormatting = [.sortedKeys]
        guard let data = try? encoder.encode(value) else { throw ProfileStoreError.encodingFailed }
        do {
            // Atomic + data-protected write prevents torn files on crash and
            // keeps the profile encrypted at rest.
            try data.write(to: url, options: [.atomic, .completeFileProtectionUntilFirstUserAuthentication])
        } catch {
            // On a PHYSICAL DEVICE we must NEVER silently downgrade to an
            // unprotected write: a protection failure is a privacy failure and
            // surfaces as an error. Only the Simulator or an injected test
            // directory (which lack real data-protection guarantees) may retry
            // atomically without the protection class.
            guard allowsUnprotectedFallback else {
                throw ProfileStoreError.protectedWriteUnavailable
            }
            do {
                try data.write(to: url, options: [.atomic])
            } catch {
                throw ProfileStoreError.writeFailed
            }
        }
        applyProtection(url)
        excludeFromBackup(url)
    }

    private func removeIfExists(_ url: URL) throws {
        if fileManager.fileExists(atPath: url.path) {
            try fileManager.removeItem(at: url)
        }
    }

    private func applyProtection(_ url: URL) {
        try? fileManager.setAttributes(
            [.protectionKey: FileProtectionType.completeUntilFirstUserAuthentication],
            ofItemAtPath: url.path
        )
    }

    private func excludeFromBackup(_ url: URL) {
        var mutable = url
        var values = URLResourceValues()
        values.isExcludedFromBackup = true
        try? mutable.setResourceValues(values)
    }
}

/// In-memory store for tests that don't touch the filesystem.
public final class InMemoryProfileStore: HandwritingProfileStoring, @unchecked Sendable {
    private let lock = NSLock()
    private var profile: HandwritingProfile?
    private var progress: CalibrationProgress?

    public init(profile: HandwritingProfile? = nil, progress: CalibrationProgress? = nil) {
        self.profile = profile
        self.progress = progress
    }

    public func loadProfile() -> HandwritingProfile? { lock.lock(); defer { lock.unlock() }; return profile }
    public func saveProfile(_ profile: HandwritingProfile) throws { lock.lock(); defer { lock.unlock() }; self.profile = profile }
    public func deleteProfile() throws { lock.lock(); defer { lock.unlock() }; profile = nil }
    public func loadProgress() -> CalibrationProgress? { lock.lock(); defer { lock.unlock() }; return progress }
    public func saveProgress(_ progress: CalibrationProgress) throws { lock.lock(); defer { lock.unlock() }; self.progress = progress }
    public func deleteProgress() throws { lock.lock(); defer { lock.unlock() }; progress = nil }
}

/// A test/diagnostic store whose PROFILE writes fail with a chosen error, while
/// progress and reads behave normally (backed by an in-memory store). This lets
/// tests prove the transactional Save contract: when protected profile
/// persistence fails, the prompt is NOT marked saved, the failure is reported,
/// and a user-readable secure-storage message is surfaced — without ever
/// touching the filesystem or exposing filesystem details.
public final class ThrowingProfileStore: HandwritingProfileStoring, @unchecked Sendable {
    private let backing: InMemoryProfileStore
    private let lock = NSLock()
    /// When true, `saveProfile` throws `profileError`. Toggleable so a test can
    /// simulate a transient protected-write failure followed by recovery.
    public var failProfileSaves: Bool
    public var profileError: ProfileStoreError

    public init(
        failProfileSaves: Bool = true,
        profileError: ProfileStoreError = .protectedWriteUnavailable,
        profile: HandwritingProfile? = nil,
        progress: CalibrationProgress? = nil
    ) {
        self.backing = InMemoryProfileStore(profile: profile, progress: progress)
        self.failProfileSaves = failProfileSaves
        self.profileError = profileError
    }

    public func loadProfile() -> HandwritingProfile? { backing.loadProfile() }
    public func saveProfile(_ profile: HandwritingProfile) throws {
        lock.lock(); let shouldFail = failProfileSaves; let err = profileError; lock.unlock()
        if shouldFail { throw err }
        try backing.saveProfile(profile)
    }
    public func deleteProfile() throws { try backing.deleteProfile() }
    public func loadProgress() -> CalibrationProgress? { backing.loadProgress() }
    public func saveProgress(_ progress: CalibrationProgress) throws { try backing.saveProgress(progress) }
    public func deleteProgress() throws { try backing.deleteProgress() }
}
