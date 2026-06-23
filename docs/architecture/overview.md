---
slug: architecture/overview
title: Architecture Overview
description: High-level design of RxAuthSwift — the core OAuth library and the SwiftUI sign-in module
---

# Architecture Overview

RxAuthSwift is an OAuth 2.0 authentication library for iOS and macOS with PKCE
support and a customizable SwiftUI sign-in UI. It targets iOS 26 / macOS 26
(building back to iOS 18 / macOS 15 features at runtime) and Swift 6.2.

## Package layout

The Swift package exposes two library products:

| Product | Target | Responsibility |
| --- | --- | --- |
| `RxAuthSwift` | `Sources/RxAuthSwift` | Core OAuth logic: configuration, the `OAuthManager` state machine, token storage, PKCE, passkey/WebAuthn ceremonies, and the server-driven UI schema model. No SwiftUI dependency. |
| `RxAuthSwiftUI` | `Sources/RxAuthSwiftUI` | Drop-in SwiftUI sign-in surface (`RxSignInView`), appearance customization, and supporting components. Depends on `RxAuthSwift`. |

The only external dependency is [`swift-log`](https://github.com/apple/swift-log),
used by `OAuthManager` for structured logging.

## Core building blocks

- **`RxAuthConfiguration`** — an immutable, `Sendable` value type holding the
  issuer, client ID, redirect URI, scopes, and every endpoint path. It derives
  fully-qualified `URL`s lazily and resolves optional native/passkey endpoints
  to `nil` when not configured. This is the single source of truth for which
  authentication methods are available.
- **`OAuthManager`** — a `@MainActor`, `@Observable` final class that owns all
  authentication state (`authState`, `currentUser`, `errorMessage`,
  `infoMessage`, schema). It is the only stateful object the host app holds.
- **`TokenStorageProtocol`** — the persistence seam. The default
  implementation is `KeychainTokenStorage`; `InMemoryTokenStorage` is provided
  for tests and previews. Hosts can inject a custom backend.
- **`AuthUISchema`** — a server-driven description of the sign-in/sign-up form
  (fields, validation, supported methods, links). It lets the backend evolve
  the native UI without re-shipping the client.

## Authentication flows

The library supports several flows, each gated on the corresponding endpoints
being present in `RxAuthConfiguration`:

1. **Authorization code + PKCE (browser).** `authenticate()` opens an
   `ASWebAuthenticationSession` (platform providers under
   `Sources/RxAuthSwift/Platform`), captures the redirect, and exchanges the
   code at the token endpoint. This is the universal, always-available flow.
2. **Native password grant.** `authenticate(username:password:)` posts an
   OAuth `password` grant directly to `nativePasswordTokenPath` (or
   `tokenPath`). Used by the native macOS form so the user never sees a
   browser.
3. **Native sign-up.** `signUp(username:password:name:)` POSTs JSON to
   `nativeSignupPath`. The server either returns tokens (immediate sign-in) or
   signals that email verification is required (`SignupResult`).
4. **Passkey sign-in / registration.** WebAuthn ceremonies via
   `AuthenticationServices`, exchanging a server challenge for a platform
   assertion/attestation and verifying it for tokens.
5. **Passkey upgrade.** After a password sign-in/sign-up, the OS can silently
   provision a passkey (`attemptAutomaticPasskeyUpgrade`, fire-and-forget) or
   the UI can prompt with an interactive upgrade (`addPasskeyForCurrentUser`).
6. **System-sheet account creation (iOS 26 / macOS 26).** Apple's
   `ASAuthorizationAccountCreationProvider` collects contact details from
   iCloud and produces a passkey with no in-app form.

All token-issuing flows converge on the same path: decode the token response,
persist via `TokenStorageProtocol`, fetch user info, set `authState =
.authenticated`, and start the refresh timer.

## State & session lifecycle

`authState` moves through `.unknown` → (`.authenticated` | `.unauthenticated`).
On launch the host calls `checkExistingAuth()`, which restores a session from a
valid access token, refreshes from a refresh token, or falls back to
`.unauthenticated`. A repeating 5-minute `Timer` refreshes tokens in the
background; an unrecoverable refresh failure clears storage, logs the user out,
and posts the `.rxAuthSessionExpired` notification so the host can react.

## Security notes

- PKCE (`S256`) is always used for the browser authorization-code flow
  (`PKCEHelper`).
- Tokens are stored in the Keychain by default, scoped to
  `keychainServiceName`.
- Passkey payloads are encoded/decoded as base64url (`Base64URL`) and the
  challenge response decoder tolerates the various server JSON shapes
  (flat, nested, SimpleWebAuthn-style) seen across endpoints.
