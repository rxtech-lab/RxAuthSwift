import Foundation
import Testing
@testable import RxAuthSwift

// MARK: - PKCE Tests

@Suite("PKCE Helper")
struct PKCEHelperTests {
    @Test func codeVerifierIsBase64URLEncoded() {
        let verifier = PKCEHelper.generateCodeVerifier()
        #expect(!verifier.isEmpty)
        #expect(!verifier.contains("+"))
        #expect(!verifier.contains("/"))
        #expect(!verifier.contains("="))
    }

    @Test func codeVerifierHasExpectedLength() {
        let verifier = PKCEHelper.generateCodeVerifier()
        // 32 bytes base64-encoded ≈ 43 chars
        #expect(verifier.count >= 40)
        #expect(verifier.count <= 50)
    }

    @Test func codeChallengeIsDeterministic() {
        let verifier = "test-verifier-string-123"
        let challenge1 = PKCEHelper.generateCodeChallenge(from: verifier)
        let challenge2 = PKCEHelper.generateCodeChallenge(from: verifier)
        #expect(challenge1 == challenge2)
    }

    @Test func codeChallengeIsBase64URLEncoded() {
        let verifier = PKCEHelper.generateCodeVerifier()
        let challenge = PKCEHelper.generateCodeChallenge(from: verifier)
        #expect(!challenge.isEmpty)
        #expect(!challenge.contains("+"))
        #expect(!challenge.contains("/"))
        #expect(!challenge.contains("="))
    }

    @Test func codeChallengeIsDifferentFromVerifier() {
        let verifier = PKCEHelper.generateCodeVerifier()
        let challenge = PKCEHelper.generateCodeChallenge(from: verifier)
        #expect(verifier != challenge)
    }

    @Test func uniqueVerifiersEachTime() {
        let verifier1 = PKCEHelper.generateCodeVerifier()
        let verifier2 = PKCEHelper.generateCodeVerifier()
        #expect(verifier1 != verifier2)
    }
}

// MARK: - Configuration Tests

@Suite("RxAuthConfiguration")
struct RxAuthConfigurationTests {
    @Test func defaultEndpoints() {
        let config = RxAuthConfiguration(
            issuer: "https://auth.example.com",
            clientID: "client-123",
            redirectURI: "myapp://callback"
        )
        #expect(config.authorizePath == "/api/oauth/authorize")
        #expect(config.tokenPath == "/api/oauth/token")
        #expect(config.userInfoPath == "/api/oauth/userinfo")
    }

    @Test func defaultScopes() {
        let config = RxAuthConfiguration(
            issuer: "https://auth.example.com",
            clientID: "client-123",
            redirectURI: "myapp://callback"
        )
        #expect(config.scopes == ["openid", "profile", "email"])
    }

    @Test func customEndpoints() {
        let config = RxAuthConfiguration(
            issuer: "https://auth.example.com",
            clientID: "client-123",
            redirectURI: "myapp://callback",
            authorizePath: "/oauth/authorize",
            tokenPath: "/oauth/token",
            userInfoPath: "/oauth/me"
        )
        #expect(config.authorizePath == "/oauth/authorize")
        #expect(config.tokenPath == "/oauth/token")
        #expect(config.userInfoPath == "/oauth/me")
    }

    @Test func urlConstruction() {
        let config = RxAuthConfiguration(
            issuer: "https://auth.example.com",
            clientID: "client-123",
            redirectURI: "myapp://callback"
        )
        #expect(config.authorizeURL?.absoluteString == "https://auth.example.com/api/oauth/authorize")
        #expect(config.tokenURL?.absoluteString == "https://auth.example.com/api/oauth/token")
        #expect(config.userInfoURL?.absoluteString == "https://auth.example.com/api/oauth/userinfo")
    }

    @Test func redirectSchemeExtraction() {
        let config = RxAuthConfiguration(
            issuer: "https://auth.example.com",
            clientID: "client-123",
            redirectURI: "myapp://callback"
        )
        #expect(config.redirectScheme == "myapp")
    }

    @Test func customKeychainServiceName() {
        let config = RxAuthConfiguration(
            issuer: "https://auth.example.com",
            clientID: "client-123",
            redirectURI: "myapp://callback",
            keychainServiceName: "com.myapp.auth"
        )
        #expect(config.keychainServiceName == "com.myapp.auth")
    }
}

// MARK: - AuthenticationState Tests

@Suite("AuthenticationState")
struct AuthenticationStateTests {
    @Test func userModel() {
        let user = User(id: "1", name: "Test", email: "test@example.com", image: nil)
        #expect(user.id == "1")
        #expect(user.name == "Test")
        #expect(user.email == "test@example.com")
        #expect(user.image == nil)
    }

    @Test func userEquality() {
        let user1 = User(id: "1", name: "Test", email: "test@example.com", image: nil)
        let user2 = User(id: "1", name: "Test", email: "test@example.com", image: nil)
        #expect(user1 == user2)
    }

    @Test func userCodable() throws {
        let user = User(id: "1", name: "Test", email: "test@example.com", image: "https://example.com/avatar.png")
        let data = try JSONEncoder().encode(user)
        let decoded = try JSONDecoder().decode(User.self, from: data)
        #expect(decoded == user)
    }
}

// MARK: - OAuthError Tests

@Suite("OAuthError")
struct OAuthErrorTests {
    @Test func errorDescriptions() {
        #expect(OAuthError.invalidURL.errorDescription != nil)
        #expect(OAuthError.invalidConfiguration.errorDescription != nil)
        #expect(OAuthError.authenticationFailed("reason").errorDescription?.contains("reason") == true)
        #expect(OAuthError.tokenExchangeFailed("reason").errorDescription?.contains("reason") == true)
        #expect(OAuthError.noRefreshToken.errorDescription != nil)
        #expect(OAuthError.cancelled.errorDescription != nil)
    }
}
