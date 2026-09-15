import CryptoKit
import Foundation
import Testing
@testable import RxAuthSwift

// MARK: - Configuration

@Suite("Sign in with Apple configuration")
struct AppleSignInConfigurationTests {
    @Test func nativeAppleEndpointsHaveDefaults() {
        let config = RxAuthConfiguration(
            issuer: "https://auth.example.com",
            clientID: "client-123",
            redirectURI: "myapp://callback"
        )

        #expect(config.appleNonceURL?.absoluteString == "https://auth.example.com/api/oauth/social/apple/nonce")
        #expect(config.appleNativeSignInURL?.absoluteString == "https://auth.example.com/api/oauth/social/apple")
    }

    @Test func nativeAppleEndpointsCanBeCustomised() {
        let config = RxAuthConfiguration(
            issuer: "https://auth.example.com",
            clientID: "client-123",
            redirectURI: "myapp://callback",
            appleNoncePath: "/custom/nonce",
            appleNativeSignInPath: "/custom/apple"
        )

        #expect(config.appleNonceURL?.absoluteString == "https://auth.example.com/custom/nonce")
        #expect(config.appleNativeSignInURL?.absoluteString == "https://auth.example.com/custom/apple")
    }

    @Test func nilPathsDisableTheNativePath() {
        // Opting out sends Apple through the ordinary browser flow instead.
        let config = RxAuthConfiguration(
            issuer: "https://auth.example.com",
            clientID: "client-123",
            redirectURI: "myapp://callback",
            appleNoncePath: nil,
            appleNativeSignInPath: nil
        )

        #expect(config.appleNonceURL == nil)
        #expect(config.appleNativeSignInURL == nil)
    }

    @Test @MainActor func managerReportsNativeAppleSupportFromConfiguration() {
        let enabled = OAuthManager(
            configuration: RxAuthConfiguration(
                issuer: "https://auth.example.com",
                clientID: "client-123",
                redirectURI: "myapp://callback"
            ),
            tokenStorage: InMemoryTokenStorage()
        )
        #expect(enabled.supportsNativeAppleSignIn)

        let disabled = OAuthManager(
            configuration: RxAuthConfiguration(
                issuer: "https://auth.example.com",
                clientID: "client-123",
                redirectURI: "myapp://callback",
                appleNoncePath: nil,
                appleNativeSignInPath: nil
            ),
            tokenStorage: InMemoryTokenStorage()
        )
        #expect(!disabled.supportsNativeAppleSignIn)
    }
}

// MARK: - Schema-driven availability

@Suite("Sign in with Apple availability")
struct AppleSignInAvailabilityTests {
    /// The button is only ever drawn from what the server advertises: a
    /// deployment without Apple configured omits it from `identityProviders`,
    /// and no Apple button appears.
    @Test func schemaWithoutAppleAdvertisesNoAppleProvider() throws {
        let json = #"""
        {
          "flow": "signin",
          "title": "Sign in",
          "submitLabel": "Sign in",
          "fields": [],
          "supportedMethods": [],
          "identityProviders": [
            {
              "id": "google",
              "label": "Continue with Google",
              "iconUrl": "https://auth.rxlab.app/brand/google-g.svg",
              "darkIconUrl": "https://auth.rxlab.app/brand/google-g.svg",
              "authorizationParameters": { "identity_provider": "google" }
            }
          ],
          "links": []
        }
        """#

        let schema = try JSONDecoder().decode(AuthUISchema.self, from: Data(json.utf8))
        let providers = try #require(schema.identityProviders)
        #expect(!providers.contains { $0.id == AuthUISchema.IdentityProvider.appleProviderID })
    }

    @Test func appleProviderDecodesWithServerSuppliedBrandMarks() throws {
        let json = #"""
        {
          "flow": "signin",
          "title": "Sign in",
          "submitLabel": "Sign in",
          "fields": [],
          "supportedMethods": [],
          "identityProviders": [
            {
              "id": "apple",
              "label": "Continue with Apple",
              "iconUrl": "https://auth.rxlab.app/brand/apple-logo-black.svg",
              "darkIconUrl": "https://auth.rxlab.app/brand/apple-logo-white.svg",
              "authorizationParameters": { "identity_provider": "apple" }
            }
          ],
          "links": []
        }
        """#

        let schema = try JSONDecoder().decode(AuthUISchema.self, from: Data(json.utf8))
        let apple = try #require(schema.identityProviders?.first)

        #expect(apple.id == AuthUISchema.IdentityProvider.appleProviderID)
        #expect(apple.label == "Continue with Apple")
        // The mark is monochrome, so light and dark are different files.
        #expect(apple.iconURL(dark: false)?.absoluteString == "https://auth.rxlab.app/brand/apple-logo-black.svg")
        #expect(apple.iconURL(dark: true)?.absoluteString == "https://auth.rxlab.app/brand/apple-logo-white.svg")
    }

    @Test func appleProviderIDMatchesTheServerIdentifier() {
        #expect(AuthUISchema.IdentityProvider.appleProviderID == "apple")
    }
}

// MARK: - Nonce hashing

#if os(macOS) || os(iOS)
@Suite("Apple nonce hashing")
struct AppleNonceHashingTests {
    /// Must agree byte-for-byte with the server's hex-encoded SHA-256, or the
    /// nonce comparison in POST /api/oauth/social/apple rejects every sign-in.
    @Test func hashesToLowercaseHexSHA256() {
        let hashed = PlatformAppleSignInAuthenticator.sha256Hex("raw-nonce-value")

        #expect(hashed.count == 64)
        #expect(hashed == hashed.lowercased())
        #expect(hashed.allSatisfy { $0.isHexDigit })

        let expected = SHA256.hash(data: Data("raw-nonce-value".utf8))
            .map { String(format: "%02x", $0) }
            .joined()
        #expect(hashed == expected)
    }

    @Test func knownVector() {
        // SHA-256("abc") — pins the encoding, not just self-consistency.
        #expect(
            PlatformAppleSignInAuthenticator.sha256Hex("abc")
                == "ba7816bf8f01cfea414140de5dae2223b00361a396177a9cb410ff61f20015ad"
        )
    }

    @Test func differentNoncesHashDifferently() {
        #expect(
            PlatformAppleSignInAuthenticator.sha256Hex("nonce-a")
                != PlatformAppleSignInAuthenticator.sha256Hex("nonce-b")
        )
    }
}
#endif

// MARK: - Errors

@Suite("Sign in with Apple errors")
struct AppleSignInErrorTests {
    @Test func unavailableErrorHasADescription() {
        #expect(
            OAuthError.appleSignInUnavailable.errorDescription
                == "Sign in with Apple is not configured for this app"
        )
    }
}
