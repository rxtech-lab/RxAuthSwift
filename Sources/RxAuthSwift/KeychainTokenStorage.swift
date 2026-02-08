import Foundation
import Security

public final class KeychainTokenStorage: TokenStorageProtocol, @unchecked Sendable {
    private let serviceName: String
    private let accessTokenKey = "access_token"
    private let refreshTokenKey = "refresh_token"
    private let expiresAtKey = "expires_at"
    private let lock = NSLock()

    public init(serviceName: String = "com.rxlab.RxAuthSwift") {
        self.serviceName = serviceName
    }

    // MARK: - Access Token

    public func saveAccessToken(_ token: String) throws {
        try saveString(token, forKey: accessTokenKey)
    }

    public func getAccessToken() -> String? {
        getString(forKey: accessTokenKey)
    }

    public func deleteAccessToken() throws {
        try deleteItem(forKey: accessTokenKey)
    }

    // MARK: - Refresh Token

    public func saveRefreshToken(_ token: String) throws {
        try saveString(token, forKey: refreshTokenKey)
    }

    public func getRefreshToken() -> String? {
        getString(forKey: refreshTokenKey)
    }

    public func deleteRefreshToken() throws {
        try deleteItem(forKey: refreshTokenKey)
    }

    // MARK: - Expiration

    public func saveExpiresAt(_ date: Date) throws {
        let timestamp = String(date.timeIntervalSince1970)
        try saveString(timestamp, forKey: expiresAtKey)
    }

    public func getExpiresAt() -> Date? {
        guard let timestampString = getString(forKey: expiresAtKey),
              let timestamp = Double(timestampString)
        else { return nil }
        return Date(timeIntervalSince1970: timestamp)
    }

    public func isTokenExpired() -> Bool {
        guard let expiresAt = getExpiresAt() else { return true }
        // Consider expired if within 10 minutes of expiration
        return expiresAt.timeIntervalSinceNow < 600
    }

    public func clearAll() throws {
        try deleteAccessToken()
        try deleteRefreshToken()
        try deleteItem(forKey: expiresAtKey)
    }

    // MARK: - Private Keychain Helpers

    private func saveString(_ value: String, forKey key: String) throws {
        lock.lock()
        defer { lock.unlock() }

        guard let data = value.data(using: .utf8) else {
            throw KeychainError.unexpectedData
        }

        let query: [String: Any] = [
            kSecClass as String: kSecClassGenericPassword,
            kSecAttrService as String: serviceName,
            kSecAttrAccount as String: key,
        ]

        // Delete existing item first
        SecItemDelete(query as CFDictionary)

        var addQuery = query
        addQuery[kSecValueData as String] = data

        let status = SecItemAdd(addQuery as CFDictionary, nil)
        guard status == errSecSuccess else {
            throw KeychainError.saveFailed(status)
        }
    }

    private func getString(forKey key: String) -> String? {
        lock.lock()
        defer { lock.unlock() }

        let query: [String: Any] = [
            kSecClass as String: kSecClassGenericPassword,
            kSecAttrService as String: serviceName,
            kSecAttrAccount as String: key,
            kSecReturnData as String: true,
            kSecMatchLimit as String: kSecMatchLimitOne,
        ]

        var result: AnyObject?
        let status = SecItemCopyMatching(query as CFDictionary, &result)

        guard status == errSecSuccess,
              let data = result as? Data,
              let string = String(data: data, encoding: .utf8)
        else { return nil }

        return string
    }

    private func deleteItem(forKey key: String) throws {
        lock.lock()
        defer { lock.unlock() }

        let query: [String: Any] = [
            kSecClass as String: kSecClassGenericPassword,
            kSecAttrService as String: serviceName,
            kSecAttrAccount as String: key,
        ]

        let status = SecItemDelete(query as CFDictionary)
        guard status == errSecSuccess || status == errSecItemNotFound else {
            throw KeychainError.deleteFailed(status)
        }
    }
}
