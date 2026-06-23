---
slug: code/rxauthswift-core
title: RxAuthSwift Core API Reference
description: Public API of the RxAuthSwift core target — configuration, OAuthManager, token storage, models, and errors
---

# RxAuthSwift Core API Reference

Public symbols in the `RxAuthSwift` target.

## RxAuthConfiguration

`public struct RxAuthConfiguration: Sendable` — immutable OAuth configuration.

### Initializer parameters

| Parameter | Type | Default | Purpose |
| --- | --- | --- | --- |
| `issuer` | `String` | — | Base URL of the auth server. |
| `clientID` | `String` | — | OAuth client identifier. |
| `redirectURI` | `String` | — | Redirect URI; its scheme is the callback scheme. |
| `scopes` | `[String]` | `["openid", "profile", "email"]` | Requested scopes. |
| `authorizePath` | `String` | `/api/oauth/authorize` | Authorization endpoint. |
| `tokenPath` | `String` | `/api/oauth/token` | Token endpoint. |
| `userInfoPath` | `String` | `/api/oauth/userinfo` | User-info endpoint. |
| `nativePasswordTokenPath` | `String?` | `nil` | Native password-grant endpoint (falls back to `tokenPath`). |
| `nativeSignupPath` | `String?` | `/api/oauth/signup` | Native signup endpoint. |
| `passkeyChallengePath` / `passkeyVerificationPath` | `String?` | `nil` | Passkey sign-in pair. |
| `passkeyRegistrationChallengePath` / `passkeyRegistrationVerificationPath` | `String?` | `nil` | Passkey registration pair. |
| `passkeyUpgradeChallengePath` / `passkeyUpgradeVerificationPath` | `String?` | `nil` | Passkey upgrade pair. |
| `passkeyAccountCreationOptionsPath` / `passkeyAccountCreationVerifyPath` | `String?` | `nil` | System-sheet account-creation pair. |
| `passkeyRelyingPartyIdentifier` | `String?` | `nil` | WebAuthn RP ID (falls back to issuer host). |
| `uiSchemaPath` | `String?` | `/api/auth/ui-schema` | Server-driven UI schema endpoint. |
| `keychainServiceName` | `String` | `com.rxlab.RxAuthSwift` | Keychain service scope. |

### Computed properties

Derived `URL?` accessors: `authorizeURL`, `tokenURL`, `userInfoURL`,
`nativePasswordTokenURL`, `nativeSignupURL`, `passkeyChallengeURL`,
`passkeyVerificationURL`, `passkeyRegistrationChallengeURL`,
`passkeyRegistrationVerificationURL`, `passkeyUpgradeChallengeURL`,
`passkeyUpgradeVerificationURL`, `passkeyAccountCreationOptionsURL`,
`passkeyAccountCreationVerifyURL`, and `redirectScheme`. Optional endpoints
resolve to `nil` when their path is unset.

- `func uiSchemaURL(flow: AuthUISchema.Flow) -> URL?` — builds the schema URL
  for a flow, appending `client_id`.

## OAuthManager

`@MainActor @Observable public final class OAuthManager` — owns authentication
state and drives every flow.

### Observable state (read-only)

| Property | Type | Meaning |
| --- | --- | --- |
| `authState` | `AuthenticationState` | `.unknown` / `.authenticated` / `.unauthenticated`. |
| `currentUser` | `User?` | The signed-in user. |
| `errorMessage` | `String?` | Last user-facing error. |
| `infoMessage` | `String?` | Informational message (e.g. email-verification prompt). |
| `isAuthenticating` | `Bool` | A flow is in progress. |
| `signInSchema` / `signUpSchema` | `AuthUISchema?` | Loaded server-driven schemas. |
| `isLoadingSchema` | `Bool` | Schema fetch in progress. |
| `pendingPasskeyOffer` | `Bool` | A post-signup passkey offer is awaiting resolution. |

### Capability flags

`supportsPasskeyAuthentication`, `supportsNativeSignup`,
`supportsPasskeyRegistration`, `supportsPasskeyUpgrade`,
`supportsPasskeyAccountCreation` — each `true` only when the matching
endpoints are configured.

### Initializer

```swift
public init(
    configuration: RxAuthConfiguration,
    tokenStorage: TokenStorageProtocol? = nil,   // defaults to KeychainTokenStorage
    logger: Logger? = nil                          // swift-log; defaults to .info
)
```

### Methods

| Method | Description |
| --- | --- |
| `checkExistingAuth() async` | Restore a session from stored tokens on launch. |
| `authenticate() async throws` | Browser authorization-code + PKCE flow. |
| `authenticate(username:password:) async throws` | Native password grant. |
| `authenticateWithPasskey(username:) async throws` | Passkey assertion sign-in. |
| `signUp(username:password:name:) async throws -> SignupResult` | Native sign-up. |
| `signUpWithPasskey(username:name:) async throws` | Passkey registration sign-up. |
| `createAccountWithPasskey(acceptedIdentifiers:shouldRequestName:) async throws` | System-sheet account creation (iOS 26 / macOS 26). |
| `addPasskeyForCurrentUser() async throws` | Accept the post-signup passkey offer (interactive). |
| `skipPasskeyUpgradeOffer()` | Decline the post-signup passkey offer and finalize the session. |
| `refreshTokenIfNeeded() async throws` | Manually refresh tokens. |
| `loadUISchema() async -> (signIn:signUp:)` | Fetch both UI schemas. |
| `fetchUISchema(flow:) async -> AuthUISchema?` | Fetch one UI schema. |
| `logout() async` | Clear tokens, reset state. |
| `clearError()` / `clearInfo()` | Clear the corresponding message. |

A repeating 5-minute timer refreshes tokens while authenticated. On an
unrecoverable refresh failure the manager logs out and posts
`.rxAuthSessionExpired`.

## SignupResult

```swift
public enum SignupResult: Sendable, Equatable {
    case authenticated
    case emailVerificationRequired(email: String)
}
```

## AuthenticationState & User

```swift
public enum AuthenticationState: Sendable { case unknown, authenticated, unauthenticated }

public struct User: Codable, Identifiable, Sendable, Equatable {
    public let id: String      // decodes "id" or OIDC "sub"
    public let name: String?
    public let email: String?
    public let image: String?  // decodes "image" or OIDC "picture"
}
```

## TokenStorageProtocol

```swift
public protocol TokenStorageProtocol: Sendable {
    func saveAccessToken(_ token: String) throws
    func getAccessToken() -> String?
    func deleteAccessToken() throws
    func saveRefreshToken(_ token: String) throws
    func getRefreshToken() -> String?
    func deleteRefreshToken() throws
    func saveExpiresAt(_ date: Date) throws
    func getExpiresAt() -> Date?
    func isTokenExpired() -> Bool
    func clearAll() throws
}
```

Built-in implementations: `KeychainTokenStorage` (default, scoped to
`keychainServiceName`) and `InMemoryTokenStorage` (tests / previews).

## Errors

`OAuthError: LocalizedError, Sendable` cases: `invalidURL`,
`invalidConfiguration`, `authenticationFailed(String)`,
`tokenExchangeFailed(String)`, `tokenRefreshFailed(String)`,
`networkError(String)`, `userInfoFailed(String)`, `noRefreshToken`,
`invalidCallbackURL`, `cancelled`, `invalidCredentials`,
`invalidSignupDetails`, `passkeyUnavailable`.

`KeychainError: LocalizedError, Sendable` cases: `saveFailed(OSStatus)`,
`deleteFailed(OSStatus)`, `unexpectedData`.

## Notifications

```swift
extension Notification.Name {
    public static let rxAuthSessionExpired: Notification.Name
}
```

Posted when a token refresh fails unrecoverably and the user is logged out.
