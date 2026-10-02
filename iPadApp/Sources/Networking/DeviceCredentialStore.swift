import Foundation
import Security

/// Abstraction over device bearer-credential storage so tests can substitute an
/// in-memory implementation.
public protocol DeviceCredentialStoring: Sendable {
    func bearerToken() -> String?
    func save(bearerToken: String) throws
    func clear() throws
}

public enum KeychainError: Error, Equatable {
    case unexpectedStatus(OSStatus)
    case encodingFailed
}

/// A Keychain-backed store for the device bearer credential.
///
/// The bootstrap token is NEVER hardcoded and NEVER read from Info.plist. It may
/// only originate from a process environment variable (see
/// `AppEnvironment.bootstrapToken`) and is then persisted here so subsequent
/// launches read it from the Keychain rather than the environment.
public struct KeychainCredentialStore: DeviceCredentialStoring {
    private let service: String
    private let account: String

    public init(service: String = "com.livingpage.device-credential", account: String = "bearer") {
        self.service = service
        self.account = account
    }

    private func baseQuery() -> [String: Any] {
        [
            kSecClass as String: kSecClassGenericPassword,
            kSecAttrService as String: service,
            kSecAttrAccount as String: account,
        ]
    }

    public func bearerToken() -> String? {
        var query = baseQuery()
        query[kSecReturnData as String] = true
        query[kSecMatchLimit as String] = kSecMatchLimitOne
        var item: CFTypeRef?
        let status = SecItemCopyMatching(query as CFDictionary, &item)
        guard status == errSecSuccess, let data = item as? Data else { return nil }
        return String(data: data, encoding: .utf8)
    }

    public func save(bearerToken: String) throws {
        guard let data = bearerToken.data(using: .utf8) else { throw KeychainError.encodingFailed }
        // Delete any existing item first so save is idempotent.
        SecItemDelete(baseQuery() as CFDictionary)
        var attributes = baseQuery()
        attributes[kSecValueData as String] = data
        attributes[kSecAttrAccessible as String] = kSecAttrAccessibleAfterFirstUnlockThisDeviceOnly
        let status = SecItemAdd(attributes as CFDictionary, nil)
        guard status == errSecSuccess else { throw KeychainError.unexpectedStatus(status) }
    }

    public func clear() throws {
        let status = SecItemDelete(baseQuery() as CFDictionary)
        guard status == errSecSuccess || status == errSecItemNotFound else {
            throw KeychainError.unexpectedStatus(status)
        }
    }
}

/// In-memory credential store used by tests and UI-testing mode. Never persists.
public final class InMemoryCredentialStore: DeviceCredentialStoring, @unchecked Sendable {
    private let lock = NSLock()
    private var token: String?

    public init(token: String? = nil) {
        self.token = token
    }

    public func bearerToken() -> String? {
        lock.lock(); defer { lock.unlock() }
        return token
    }

    public func save(bearerToken: String) throws {
        lock.lock(); defer { lock.unlock() }
        token = bearerToken
    }

    public func clear() throws {
        lock.lock(); defer { lock.unlock() }
        token = nil
    }
}
