import Foundation
import Security

/// Keychain-backed storage for Spotify OAuth tokens.
///
/// Tokens are never written to `UserDefaults`, never logged, and never placed on disk in
/// plaintext. There is no client secret to store — the OAuth flow uses PKCE precisely so a
/// desktop app doesn't have to embed one.
enum KeychainStore {
    private static let service = "app.nocta.spotify"

    enum KeychainError: LocalizedError {
        case unexpectedStatus(OSStatus)

        var errorDescription: String? {
            switch self {
            case .unexpectedStatus(let status):
                let message = SecCopyErrorMessageString(status, nil) as String? ?? "unknown"
                return "Keychain error \(status): \(message)"
            }
        }
    }

    static func save(_ data: Data, account: String) throws {
        // Delete first: SecItemUpdate on a missing item fails, and this keeps the write simple.
        try? delete(account: account)

        let query: [String: Any] = [
            kSecClass as String: kSecClassGenericPassword,
            kSecAttrService as String: service,
            kSecAttrAccount as String: account,
            kSecValueData as String: data,
            // Readable while the screen is locked, so the Lock Screen controller can still
            // show liked state — but never before the first unlock after boot, and never
            // synced to iCloud.
            kSecAttrAccessible as String: kSecAttrAccessibleAfterFirstUnlockThisDeviceOnly,
        ]

        let status = SecItemAdd(query as CFDictionary, nil)
        guard status == errSecSuccess else { throw KeychainError.unexpectedStatus(status) }
    }

    /// `nil` means there is no stored item. A read that is *refused* — the user denied the
    /// keychain prompt, or the app's signature no longer matches the item's ACL — throws
    /// instead, because silently reporting "not signed in" makes the Spotify controls vanish
    /// with no explanation.
    static func load(account: String) throws -> Data? {
        let query: [String: Any] = [
            kSecClass as String: kSecClassGenericPassword,
            kSecAttrService as String: service,
            kSecAttrAccount as String: account,
            kSecReturnData as String: true,
            kSecMatchLimit as String: kSecMatchLimitOne,
        ]

        var result: AnyObject?
        let status = SecItemCopyMatching(query as CFDictionary, &result)
        switch status {
        case errSecSuccess:     return result as? Data
        case errSecItemNotFound: return nil
        default:                throw KeychainError.unexpectedStatus(status)
        }
    }

    static func delete(account: String) throws {
        let query: [String: Any] = [
            kSecClass as String: kSecClassGenericPassword,
            kSecAttrService as String: service,
            kSecAttrAccount as String: account,
        ]
        let status = SecItemDelete(query as CFDictionary)
        guard status == errSecSuccess || status == errSecItemNotFound else {
            throw KeychainError.unexpectedStatus(status)
        }
    }

    // MARK: - Codable convenience

    static func save<T: Encodable>(_ value: T, account: String) throws {
        try save(try JSONEncoder().encode(value), account: account)
    }

    static func load<T: Decodable>(_ type: T.Type, account: String) throws -> T? {
        guard let data = try load(account: account) else { return nil }
        return try? JSONDecoder().decode(type, from: data)
    }
}
