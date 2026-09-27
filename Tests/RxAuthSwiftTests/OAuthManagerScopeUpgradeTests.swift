import Foundation
import Testing
@testable import RxAuthSwift

private final class ScopeMockURLProtocol: URLProtocol, @unchecked Sendable {
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

@Suite("OAuthManager scope upgrades", .serialized)
struct OAuthManagerScopeUpgradeTests {
    private let scopes = ["openid", "read:profile", "read:email"]

    private func makeConfig() -> RxAuthConfiguration {
        RxAuthConfiguration(
            issuer: "https://auth.example.com",
            clientID: "scope-test-client",
            redirectURI: "testapp://callback",
            scopes: scopes
        )
    }

    private func makeDefaults() -> UserDefaults {
        let name = "OAuthManagerScopeUpgradeTests-\(UUID().uuidString)"
        let defaults = UserDefaults(suiteName: name)!
        defaults.removePersistentDomain(forName: name)
        return defaults
    }

    private func jwt(scope: String?) -> String {
        var claims: [String: Any] = ["sub": "user-1"]
        if let scope { claims["scope"] = scope }
        let payload = try! JSONSerialization.data(withJSONObject: claims)
        return "eyJhbGciOiJSUzI1NiJ9.\(Base64URL.encode(payload)).sig"
    }

    private var signedInScopesKey: String {
        "RxAuthSwift.signedInScopes.scope-test-client.com.rxlab.RxAuthSwift"
    }

    @Test func grantedScopesAreReadFromJWTAccessTokens() {
        #expect(OAuthManager.grantedScopes(inAccessToken: jwt(scope: "openid read:email")) == ["openid", "read:email"])
        #expect(OAuthManager.grantedScopes(inAccessToken: jwt(scope: nil)) == nil)
        #expect(OAuthManager.grantedScopes(inAccessToken: "opaque") == nil)
    }

    @Test @MainActor func restoreSignsOutASessionGrantedFewerScopes() async throws {
        let storage = InMemoryTokenStorage()
        try storage.saveAccessToken(jwt(scope: "openid"))
        try storage.saveRefreshToken("refresh")
        try storage.saveExpiresAt(Date().addingTimeInterval(3600))
        let manager = OAuthManager(configuration: makeConfig(), tokenStorage: storage, scopeDefaults: makeDefaults())

        await manager.checkExistingAuth()

        #expect(manager.authState == .unauthenticated)
        #expect(storage.getAccessToken() == nil)
        #expect(storage.getRefreshToken() == nil)
    }

    @Test @MainActor func recordedSignInScopesPreventASignOutLoop() async throws {
        let defaults = makeDefaults()
        // The last interactive sign-in already requested today's scopes, even
        // though the server granted fewer — signing out again wouldn't help.
        defaults.set(scopes, forKey: signedInScopesKey)
        let manager = OAuthManager(configuration: makeConfig(), tokenStorage: InMemoryTokenStorage(), scopeDefaults: defaults)

        #expect(manager.sessionMissingScopes(granted: ["openid"]) == nil)

        defaults.set(["openid"], forKey: signedInScopesKey)
        #expect(manager.sessionMissingScopes(granted: Set(scopes)) == ["read:profile", "read:email"])
    }

    @Test @MainActor func unknownGrantsAreTreatedAsUpToDate() {
        let manager = OAuthManager(configuration: makeConfig(), tokenStorage: InMemoryTokenStorage(), scopeDefaults: makeDefaults())
        #expect(manager.sessionMissingScopes(granted: nil) == nil)
        #expect(manager.sessionMissingScopes(granted: Set(scopes)) == nil)
    }

    @Test @MainActor func refreshWithNarrowerScopesSignsOutInsteadOfSaving() async throws {
        let narrowToken = jwt(scope: "openid")
        ScopeMockURLProtocol.requestHandler = { request in
            let body = try! JSONSerialization.data(withJSONObject: [
                "access_token": narrowToken,
                "refresh_token": "rotated",
                "expires_in": 3600,
                "token_type": "Bearer",
                "scope": "openid",
            ])
            let response = HTTPURLResponse(url: request.url!, statusCode: 200, httpVersion: nil, headerFields: nil)!
            return (response, body)
        }
        URLProtocol.registerClass(ScopeMockURLProtocol.self)
        defer {
            URLProtocol.unregisterClass(ScopeMockURLProtocol.self)
            ScopeMockURLProtocol.requestHandler = nil
        }

        let storage = InMemoryTokenStorage()
        try storage.saveAccessToken("expired-opaque")
        try storage.saveRefreshToken("old-refresh")
        try storage.saveExpiresAt(Date().addingTimeInterval(-3600))
        let manager = OAuthManager(configuration: makeConfig(), tokenStorage: storage, scopeDefaults: makeDefaults())

        await #expect(throws: OAuthError.self) {
            try await manager.refreshTokenIfNeeded()
        }
        #expect(manager.authState == .unauthenticated)
        #expect(storage.getAccessToken() == nil)
        #expect(storage.getRefreshToken() == nil)
    }
}
