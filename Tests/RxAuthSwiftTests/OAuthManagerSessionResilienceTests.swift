import Foundation
import Testing
@testable import RxAuthSwift

private final class ResilienceURLProtocol: URLProtocol, @unchecked Sendable {
    enum Reply { case status(Int, Data), failure(URLError.Code) }

    nonisolated(unsafe) static var handler: (@Sendable (URLRequest) -> Reply)?
    nonisolated(unsafe) static var paths: [String] = []

    override class func canInit(with request: URLRequest) -> Bool { true }
    override class func canonicalRequest(for request: URLRequest) -> URLRequest { request }

    override func startLoading() {
        Self.paths.append(request.url?.path ?? "")
        switch Self.handler?(request) ?? .failure(.notConnectedToInternet) {
        case .status(let code, let data):
            let response = HTTPURLResponse(url: request.url!, statusCode: code, httpVersion: nil, headerFields: nil)!
            client?.urlProtocol(self, didReceive: response, cacheStoragePolicy: .notAllowed)
            client?.urlProtocol(self, didLoad: data)
            client?.urlProtocolDidFinishLoading(self)
        case .failure(let code):
            client?.urlProtocol(self, didFailWithError: URLError(code))
        }
    }

    override func stopLoading() {}
}

@Suite("OAuthManager keeps sessions through transient failures", .serialized)
@MainActor
struct OAuthManagerSessionResilienceTests {
    private let defaults: UserDefaults

    init() {
        let suite = "RxAuthSwiftTests.resilience.\(UUID().uuidString)"
        defaults = UserDefaults(suiteName: suite)!
        ResilienceURLProtocol.paths = []
    }

    private func makeManager(_ storage: TokenStorageProtocol) -> OAuthManager {
        OAuthManager(
            configuration: RxAuthConfiguration(
                issuer: "https://auth.example.com", clientID: "test-client",
                redirectURI: "testapp://callback"),
            tokenStorage: storage,
            scopeDefaults: defaults
        )
    }

    private func expiredSession() throws -> InMemoryTokenStorage {
        let storage = InMemoryTokenStorage()
        try storage.saveAccessToken("expired-access")
        try storage.saveRefreshToken("refresh-token")
        try storage.saveExpiresAt(Date().addingTimeInterval(-3600))
        return storage
    }

    private func validSession() throws -> InMemoryTokenStorage {
        let storage = InMemoryTokenStorage()
        try storage.saveAccessToken("valid-access")
        try storage.saveRefreshToken("refresh-token")
        try storage.saveExpiresAt(Date().addingTimeInterval(3600))
        return storage
    }

    private func withProtocol<T>(_ handler: @escaping @Sendable (URLRequest) -> ResilienceURLProtocol.Reply,
                                 _ body: () async throws -> T) async rethrows -> T {
        ResilienceURLProtocol.handler = handler
        URLProtocol.registerClass(ResilienceURLProtocol.self)
        defer {
            URLProtocol.unregisterClass(ResilienceURLProtocol.self)
            ResilienceURLProtocol.handler = nil
        }
        return try await body()
    }

    nonisolated private static let userJSON = Data(#"{"sub":"user-1","name":"Ada","email":"ada@example.com"}"#.utf8)

    @Test func offlineRefreshKeepsSession() async throws {
        let storage = try expiredSession()
        let manager = makeManager(storage)
        await withProtocol({ _ in .failure(.notConnectedToInternet) }) {
            await manager.checkExistingAuth()
        }
        #expect(manager.authState == .authenticated)
        #expect(storage.getRefreshToken() == "refresh-token")
    }

    @Test func serverErrorDuringRefreshKeepsSession() async throws {
        let storage = try expiredSession()
        let manager = makeManager(storage)
        await withProtocol({ _ in .status(503, Data()) }) {
            await manager.checkExistingAuth()
        }
        #expect(manager.authState == .authenticated)
        #expect(storage.getRefreshToken() == "refresh-token")
    }

    @Test func rejectedRefreshSignsOut() async throws {
        let storage = try expiredSession()
        let manager = makeManager(storage)
        await withProtocol({ _ in .status(400, Data(#"{"error":"invalid_grant"}"#.utf8)) }) {
            await manager.checkExistingAuth()
        }
        #expect(manager.authState == .unauthenticated)
        #expect(storage.getRefreshToken() == nil)
    }

    @Test func offlineUserInfoKeepsSessionWithCachedUser() async throws {
        let storage = try validSession()
        // A previous launch fetched the profile while online.
        let online = makeManager(storage)
        await withProtocol({ _ in .status(200, Self.userJSON) }) {
            await online.checkExistingAuth()
        }
        let cached = try #require(online.currentUser)

        let manager = makeManager(storage)
        await withProtocol({ _ in .failure(.timedOut) }) {
            await manager.checkExistingAuth()
        }
        #expect(manager.authState == .authenticated)
        #expect(manager.currentUser == cached)
        #expect(storage.getAccessToken() == "valid-access")
    }

    @Test func rejectedAccessTokenWithRejectedRefreshSignsOut() async throws {
        let storage = try validSession()
        let manager = makeManager(storage)
        await withProtocol({ request in
            request.url?.path.hasSuffix("userinfo") == true ? .status(401, Data()) : .status(400, Data())
        }) {
            await manager.checkExistingAuth()
        }
        #expect(manager.authState == .unauthenticated)
        #expect(storage.getAccessToken() == nil)
    }

    @Test func forcedRefreshIgnoresStoredExpiry() async throws {
        let storage = try validSession()
        let manager = makeManager(storage)
        let tokenJSON = Data(#"{"access_token":"new-access","refresh_token":"new-refresh","token_type":"Bearer","expires_in":3600}"#.utf8)
        try await withProtocol({ request in
            request.url?.path.hasSuffix("userinfo") == true ? .status(200, Self.userJSON) : .status(200, tokenJSON)
        }) {
            try await manager.refreshTokenIfNeeded()
            #expect(storage.getAccessToken() == "valid-access")
            try await manager.refreshTokenIfNeeded(force: true)
        }
        #expect(storage.getAccessToken() == "new-access")
        #expect(storage.getRefreshToken() == "new-refresh")
    }

    @Test func logoutClearsCachedUser() async throws {
        let storage = try validSession()
        let manager = makeManager(storage)
        await withProtocol({ _ in .status(200, Self.userJSON) }) {
            await manager.checkExistingAuth()
        }
        await manager.logout()

        try storage.saveAccessToken("valid-access")
        try storage.saveRefreshToken("refresh-token")
        try storage.saveExpiresAt(Date().addingTimeInterval(3600))
        let next = makeManager(storage)
        await withProtocol({ _ in .failure(.notConnectedToInternet) }) {
            await next.checkExistingAuth()
        }
        #expect(next.currentUser == nil)
    }

    @Test(arguments: [(400, true), (401, true), (403, true), (408, false), (429, false), (500, false), (503, false)])
    func sessionRejectionClassification(status: Int, rejected: Bool) {
        #expect(OAuthManager.isSessionRejection(status: status) == rejected)
    }
}
