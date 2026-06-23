---
slug: guides/passkeys
title: Passkeys & Native Auth
description: Configure and use passkey sign-in, registration, automatic upgrade, and system-sheet account creation
---

# Passkeys & Native Authentication

RxAuthSwift can run several passwordless and native flows in addition to the
browser-based authorization-code flow. Each flow is enabled purely by
configuring the matching endpoint pair on `RxAuthConfiguration` — if the
endpoints are absent, the corresponding `supports…` flag on `OAuthManager`
returns `false` and the UI hides that method.

## Native password sign-in & sign-up

For native macOS sign-in, `RxSignInView` renders username/password fields
instead of launching a browser. Password sign-in posts an OAuth `password`
grant to `nativePasswordTokenPath` (falling back to `tokenPath`):

```swift
let config = RxAuthConfiguration(
    issuer: "https://auth.example.com",
    clientID: "your-client-id",
    redirectURI: "yourapp://callback",
    nativePasswordTokenPath: "/api/oauth/token",
    nativeSignupPath: "/api/oauth/signup"
)
```

- `authManager.authenticate(username:password:)` performs the password grant.
- `authManager.signUp(username:password:name:)` POSTs JSON
  (`client_id`, `username`, `password`, optional `name`, `scope`) to the signup
  endpoint and returns a `SignupResult`:
  - `.authenticated` — tokens were issued and the user is signed in.
  - `.emailVerificationRequired(email:)` — the account was created but the
    server requires email verification first. `OAuthManager` surfaces a message
    via `infoMessage`.

## Passkey sign-in & registration

Enable passkey authentication and registration by configuring the challenge /
verification endpoint pairs:

```swift
let config = RxAuthConfiguration(
    issuer: "https://auth.example.com",
    clientID: "your-client-id",
    redirectURI: "yourapp://callback",
    passkeyChallengePath: "/api/passkeys/authentication/options",
    passkeyVerificationPath: "/api/passkeys/authentication/verify",
    passkeyRegistrationChallengePath: "/api/passkeys/registration/options",
    passkeyRegistrationVerificationPath: "/api/passkeys/registration/verify",
    passkeyRelyingPartyIdentifier: "auth.example.com"
)
```

- `authManager.authenticateWithPasskey(username:)` runs a WebAuthn assertion
  ceremony and exchanges it for tokens.
- `authManager.signUpWithPasskey(username:name:)` runs a registration ceremony.

The authentication challenge endpoint returns a base64url WebAuthn challenge,
an optional `requestID`/session, an optional relying-party identifier, and
optional allowed credential IDs. The registration challenge endpoint returns a
base64url challenge and user ID plus optional session/username/RP identifier.
The relying-party identifier is resolved in this order: the value in the
challenge response → `passkeyRelyingPartyIdentifier` → the host of `issuer`.

> Passkey ceremonies are implemented for macOS. On other platforms the
> passkey methods throw `OAuthError.passkeyUnavailable`.

## Automatic passkey upgrade

After a successful password sign-in or sign-up, the library can silently ask
the OS to provision a passkey so the next sign-in is passwordless. Configure
the upgrade endpoint pair:

```swift
passkeyUpgradeChallengePath: "/api/passkeys/upgrade/options",
passkeyUpgradeVerificationPath: "/api/passkeys/upgrade/verify",
```

- **Automatic (fire-and-forget):** triggered after `authenticate(username:password:)`.
  Errors are swallowed by design — the user never sees an upgrade prompt.
- **Interactive (post-signup offer):** when `supportsPasskeyUpgrade` is true,
  a successful `signUp(...)` sets `pendingPasskeyOffer = true` and holds
  `authState` at `.unauthenticated` so the host can present an "Add a passkey"
  prompt. Resolve it by calling either:
  - `addPasskeyForCurrentUser()` — runs the interactive registration ceremony
    (Bearer-authenticated with the just-issued token), then finalizes the
    session, or
  - `skipPasskeyUpgradeOffer()` — finalizes the session without a passkey.

## System-sheet account creation (iOS 26 / macOS 26)

`createAccountWithPasskey(acceptedIdentifiers:shouldRequestName:)` drives
Apple's `ASAuthorizationAccountCreationProvider`. The OS presents a native
sheet that pulls email/phone/name from iCloud, confirms with biometrics, and
produces a passkey — no in-app form. Enable it with:

```swift
passkeyAccountCreationOptionsPath: "/api/passkeys/account-creation/options",
passkeyAccountCreationVerifyPath: "/api/passkeys/account-creation/verify",
```

Emit the `passkey_account_creation` supported method only on the **signup**
flow of your UI schema.
