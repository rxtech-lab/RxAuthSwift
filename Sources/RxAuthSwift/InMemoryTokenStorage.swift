import Foundation

public final class InMemoryTokenStorage: TokenStorageProtocol, @unchecked Sendable {
    private let lock = NSLock()
    private var accessToken: String?
    private var refreshToken: String?
    private var expiresAt: Date?

    public init() {}

    public func saveAccessToken(_ token: String) throws {
        lock.lock()
        defer { lock.unlock() }
        accessToken = token
    }

    public func getAccessToken() -> String? {
        lock.lock()
        defer { lock.unlock() }
        return accessToken
    }

    public func deleteAccessToken() throws {
        lock.lock()
        defer { lock.unlock() }
        accessToken = nil
    }

    public func saveRefreshToken(_ token: String) throws {
        lock.lock()
        defer { lock.unlock() }
        refreshToken = token
    }

    public func getRefreshToken() -> String? {
        lock.lock()
        defer { lock.unlock() }
        return refreshToken
    }

    public func deleteRefreshToken() throws {
        lock.lock()
        defer { lock.unlock() }
        refreshToken = nil
    }

    public func saveExpiresAt(_ date: Date) throws {
        lock.lock()
        defer { lock.unlock() }
        expiresAt = date
    }

    public func getExpiresAt() -> Date? {
        lock.lock()
        defer { lock.unlock() }
        return expiresAt
    }

    public func isTokenExpired() -> Bool {
        lock.lock()
        defer { lock.unlock() }
        guard let expiresAt else { return true }
        return expiresAt.timeIntervalSinceNow < 600
    }

    public func clearAll() throws {
        lock.lock()
        defer { lock.unlock() }
        accessToken = nil
        refreshToken = nil
        expiresAt = nil
    }
}
