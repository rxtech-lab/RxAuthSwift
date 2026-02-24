import Foundation
import Testing
@testable import RxAuthSwift

// MARK: - Mock Token Storage (clearAll fails but individual deletes work)

private final class ClearAllFailingTokenStorage: TokenStorageProtocol, @unchecked Sendable {
    private let lock = NSLock()
    private var accessToken: String?
    private var refreshToken: String?
    private var expiresAt: Date?

    func saveAccessToken(_ token: String) throws {
        lock.lock()
        defer { lock.unlock() }
        accessToken = token
    }

    func getAccessToken() -> String? {
        lock.lock()
        defer { lock.unlock() }
        return accessToken
    }

    func deleteAccessToken() throws {
        lock.lock()
        defer { lock.unlock() }
        accessToken = nil
    }

    func saveRefreshToken(_ token: String) throws {
        lock.lock()
        defer { lock.unlock() }
        refreshToken = token
    }

    func getRefreshToken() -> String? {
        lock.lock()
        defer { lock.unlock() }
        return refreshToken
    }

    func deleteRefreshToken() throws {
        lock.lock()
        defer { lock.unlock() }
        refreshToken = nil
    }

    func saveExpiresAt(_ date: Date) throws {
        lock.lock()
        defer { lock.unlock() }
        expiresAt = date
    }

    func getExpiresAt() -> Date? {
        lock.lock()
        defer { lock.unlock() }
        return expiresAt
    }

    func isTokenExpired() -> Bool {
        lock.lock()
        defer { lock.unlock() }
        guard let expiresAt else { return true }
        return expiresAt.timeIntervalSinceNow < 600
    }

    /// Always throws to simulate a storage failure during clearAll().
    func clearAll() throws {
        throw ClearAllError.simulatedFailure
    }

    enum ClearAllError: Error {
        case simulatedFailure
    }
}

// MARK: - Mock URL Protocol

private final class MockURLProtocol: URLProtocol, @unchecked Sendable {
    nonisolated(unsafe) static var requestHandler: (@Sendable (URLRequest) -> (HTTPURLResponse, Data))?

    override class func canInit(with request: URLRequest) -> Bool { true }
    override class func canonicalRequest(for request: URLRequest) -> URLRequest { request }

    override func startLoading() {
        guard let handler = Self.requestHandler else {
            client?.urlProtocolDidFinishLoading(self)
            return
        }
        let (response, data) = handler(request)
        client?.urlProtocol(self, didReceive: response, cacheStoragePolicy: .notAllowed)
        client?.urlProtocol(self, didLoad: data)
        client?.urlProtocolDidFinishLoading(self)
    }

    override func stopLoading() {}
}

// MARK: - Thread-safe Counter

private final class LockedCounter: @unchecked Sendable {
    private let lock = NSLock()
    private var _value = 0

    var value: Int {
        lock.lock()
        defer { lock.unlock() }
        return _value
    }

    func increment() {
        lock.lock()
        defer { lock.unlock() }
        _value += 1
    }
}

// MARK: - Tests

@Suite("OAuthManager Token Cleanup", .serialized)
struct OAuthManagerTokenCleanupTests {
    private func makeConfig() -> RxAuthConfiguration {
        RxAuthConfiguration(
            issuer: "https://auth.example.com",
            clientID: "test-client",
            redirectURI: "testapp://callback"
        )
    }

    // MARK: - logout() Tests

    @Test @MainActor func logoutClearsAllTokens() async throws {
        let storage = InMemoryTokenStorage()
        try storage.saveAccessToken("access-123")
        try storage.saveRefreshToken("refresh-456")
        try storage.saveExpiresAt(Date().addingTimeInterval(3600))

        let manager = OAuthManager(
            configuration: makeConfig(),
            tokenStorage: storage
        )

        await manager.logout()

        #expect(storage.getAccessToken() == nil)
        #expect(storage.getRefreshToken() == nil)
        #expect(storage.getExpiresAt() == nil)
        #expect(manager.authState == .unauthenticated)
        #expect(manager.currentUser == nil)
    }

    @Test @MainActor func logoutClearsTokensWhenClearAllFails() async throws {
        let storage = ClearAllFailingTokenStorage()
        try storage.saveAccessToken("access-123")
        try storage.saveRefreshToken("refresh-456")
        try storage.saveExpiresAt(Date().addingTimeInterval(3600))

        let manager = OAuthManager(
            configuration: makeConfig(),
            tokenStorage: storage
        )

        await manager.logout()

        // Even though clearAll() throws, individual deletes should remove tokens
        #expect(storage.getAccessToken() == nil)
        #expect(storage.getRefreshToken() == nil)
        #expect(manager.authState == .unauthenticated)
        #expect(manager.currentUser == nil)
    }

    // MARK: - checkExistingAuth() Tests

    @Test @MainActor func checkExistingAuthUnauthenticatedWithNoTokens() async {
        let storage = InMemoryTokenStorage()
        let manager = OAuthManager(
            configuration: makeConfig(),
            tokenStorage: storage
        )

        await manager.checkExistingAuth()

        #expect(manager.authState == .unauthenticated)
    }

    @Test @MainActor func checkExistingAuthClearsStaleTokensAfterRefreshFailure() async throws {
        // Set up mock handler before registering protocol to avoid race conditions
        MockURLProtocol.requestHandler = { request in
            let response = HTTPURLResponse(
                url: request.url!,
                statusCode: 400,
                httpVersion: nil,
                headerFields: nil
            )!
            return (response, Data())
        }

        URLProtocol.registerClass(MockURLProtocol.self)
        defer { URLProtocol.unregisterClass(MockURLProtocol.self) }

        let storage = InMemoryTokenStorage()
        // Set up stale tokens: expired access token + refresh token
        try storage.saveAccessToken("expired-access")
        try storage.saveRefreshToken("stale-refresh")
        try storage.saveExpiresAt(Date().addingTimeInterval(-3600)) // expired 1 hour ago

        let manager = OAuthManager(
            configuration: makeConfig(),
            tokenStorage: storage
        )

        // First call finds stale refresh token, tries refresh → 400 → clears tokens
        await manager.checkExistingAuth()

        #expect(manager.authState == .unauthenticated)
        // Tokens must be cleared so the next checkExistingAuth() won't retry
        #expect(storage.getAccessToken() == nil)
        #expect(storage.getRefreshToken() == nil)
    }

    @Test @MainActor func checkExistingAuthDoesNotRetryAfterTokensCleared() async throws {
        let counter = LockedCounter()
        MockURLProtocol.requestHandler = { request in
            counter.increment()
            let response = HTTPURLResponse(
                url: request.url!,
                statusCode: 400,
                httpVersion: nil,
                headerFields: nil
            )!
            return (response, Data())
        }

        URLProtocol.registerClass(MockURLProtocol.self)
        defer { URLProtocol.unregisterClass(MockURLProtocol.self) }

        let storage = InMemoryTokenStorage()
        try storage.saveAccessToken("expired-access")
        try storage.saveRefreshToken("stale-refresh")
        try storage.saveExpiresAt(Date().addingTimeInterval(-3600))

        let manager = OAuthManager(
            configuration: makeConfig(),
            tokenStorage: storage
        )

        // First call: finds stale refresh token, tries refresh, fails, clears tokens
        await manager.checkExistingAuth()
        #expect(manager.authState == .unauthenticated)

        let firstCallCount = counter.value

        // Second call: no tokens should remain, so no refresh attempt
        await manager.checkExistingAuth()
        #expect(manager.authState == .unauthenticated)
        #expect(counter.value == firstCallCount, "Should not make additional refresh requests after tokens are cleared")
    }

    @Test @MainActor func fullCycleRefreshFailureThenRecheck() async throws {
        // Simulate the full bug scenario:
        // 1. User has tokens
        // 2. Refresh fails with 400
        // 3. Tokens should be fully cleared
        // 4. Subsequent checkExistingAuth() should NOT attempt to refresh

        MockURLProtocol.requestHandler = { request in
            let response = HTTPURLResponse(
                url: request.url!,
                statusCode: 400,
                httpVersion: nil,
                headerFields: nil
            )!
            return (response, Data())
        }

        URLProtocol.registerClass(MockURLProtocol.self)
        defer { URLProtocol.unregisterClass(MockURLProtocol.self) }

        let storage = InMemoryTokenStorage()
        try storage.saveAccessToken("old-access")
        try storage.saveRefreshToken("old-refresh")
        try storage.saveExpiresAt(Date().addingTimeInterval(-100)) // expired

        let manager = OAuthManager(
            configuration: makeConfig(),
            tokenStorage: storage
        )

        // Step 1: Check existing auth → refresh fails → signs out
        await manager.checkExistingAuth()
        #expect(manager.authState == .unauthenticated)
        #expect(storage.getAccessToken() == nil)
        #expect(storage.getRefreshToken() == nil)

        // Step 2: Simulate user signing in again by saving new tokens
        try storage.saveAccessToken("new-access")
        try storage.saveRefreshToken("new-refresh")
        try storage.saveExpiresAt(Date().addingTimeInterval(3600)) // valid

        // Step 3: Now update the mock to return valid responses for the new session
        MockURLProtocol.requestHandler = { request in
            let userInfoJSON = #"{"id":"user-1","name":"Test User","email":"test@example.com"}"#
            let response = HTTPURLResponse(
                url: request.url!,
                statusCode: 200,
                httpVersion: nil,
                headerFields: ["Content-Type": "application/json"]
            )!
            return (response, userInfoJSON.data(using: .utf8)!)
        }

        // Step 4: Check existing auth with new valid tokens
        await manager.checkExistingAuth()
        #expect(manager.authState == .authenticated)
        #expect(manager.currentUser?.id == "user-1")
    }
}
