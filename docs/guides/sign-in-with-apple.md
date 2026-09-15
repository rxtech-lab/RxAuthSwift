---
title: Sign in with Apple
---

# Sign in with Apple

Apple is the one identity provider that behaves differently on Apple platforms.
The others hand the user to a browser and come back with an authorization code;
Apple has an OS-level ceremony that reuses the signed-in Apple Account, offers
Hide My Email inline, and never leaves the app. RxAuthSwift takes the native
path on iOS and macOS, and the server keeps the browser flow for the web.

Callers don't have to care. The button is rendered from the server's UI schema
like every other provider, and `authenticate(identityProvider:)` picks the right
mechanism:

```swift
// Exactly the same call for Google, GitHub, or Apple.
try await manager.authenticate(identityProvider: provider)
```

## The button is the server's decision

There is no client-side Apple toggle. The sign-in UI draws one button per entry
in the schema's `identityProviders`, using the label and brand marks the server
supplies:

```json
{
  "id": "apple",
  "label": "Continue with Apple",
  "iconUrl":     "https://auth.rxlab.app/brand/apple-logo-black.svg",
  "darkIconUrl": "https://auth.rxlab.app/brand/apple-logo-white.svg",
  "authorizationParameters": { "identity_provider": "apple" }
}
```

A deployment without Apple credentials omits that entry, and **no Apple button
is drawn** — no client release required either way. The same is true in reverse:
enable Apple on the server and existing builds pick it up on their next schema
fetch.

## How the native flow works

1. The app asks the server for a single-use nonce
   (`POST /api/oauth/social/apple/nonce`).
2. It passes **SHA-256(nonce)**, hex-encoded, as
   `ASAuthorizationAppleIDRequest.nonce`. Apple stamps that value into the
   identity token it mints.
3. The app posts the identity token back with the *raw* nonce
   (`POST /api/oauth/social/apple`).
4. The server verifies the token's signature against Apple's published keys,
   checks `iss`/`aud`/expiry, re-hashes its own copy of the nonce to confirm the
   token was minted for this one request, burns the nonce, and returns ordinary
   OAuth tokens.

Step 4 is what makes a leaked identity token useless: without the matching
server-issued nonce it can't be replayed inside its 10-minute validity window.

### The name arrives exactly once

Apple gives the app the user's name on the **first** authorization and never
again. RxAuthSwift forwards it on that first call; if the account is later
deleted server-side and the user signs in again, Apple sends nothing, and the
display name falls back to the email local part. During development, re-test the
first-run path by removing the app under *Settings → Apple Account → Sign in with
Apple*.

### Hide My Email

A user who picks Hide My Email produces a `@privaterelay.appleid.com` address.
It is verified, stable per user per app, and deliverable — the server treats it
like any other verified address and keys the account on it.

## Configuration

Defaults point at the rxlab-auth endpoints, so there is usually nothing to set:

```swift
let config = RxAuthConfiguration(
    issuer: "https://auth.rxlab.app",
    clientID: "your-client-id",
    redirectURI: "myapp://callback"
    // appleNoncePath / appleNativeSignInPath default to the native endpoints
)
```

Pass `appleNoncePath: nil, appleNativeSignInPath: nil` to opt out and send Apple
through the browser flow with the other providers.

## App target setup

1. Xcode → your target → **Signing & Capabilities** → **+ Capability** →
   **Sign in with Apple**.
2. Make sure the same capability is enabled on the App ID in the Apple Developer
   portal.
3. Give the server your bundle identifier for `APPLE_OAUTH_BUNDLE_IDS` — native
   identity tokens are audienced to the bundle ID, not to the web Services ID,
   and the server rejects an audience it wasn't told about.

## Server setup

See the auth server's `.env.example`. Sign in with Apple needs four values, and
the provider stays hidden until all four are present:

| Variable | Where it comes from |
| --- | --- |
| `APPLE_OAUTH_SERVICES_ID` | Identifiers → Services IDs. The web `client_id`. |
| `APPLE_OAUTH_TEAM_ID` | Top-right of developer.apple.com/account. |
| `APPLE_OAUTH_KEY_ID` | Keys → your "Sign in with Apple" key. |
| `APPLE_OAUTH_PRIVATE_KEY` | The downloaded `AuthKey_<KEYID>.p8`, base64-encoded: `base64 -i AuthKey_<KEYID>.p8 \| tr -d '\n'`. |

Plus `APPLE_OAUTH_BUNDLE_IDS` (comma-separated) for the native endpoint.

Apple has no static client secret: the server mints a short-lived ES256 JWT from
the `.p8` key for each token exchange.

## App Review note

Guideline 4.8 requires an equivalent privacy-preserving login option wherever
third-party sign-in is offered — Sign in with Apple satisfies it. Apple's Human
Interface Guidelines also specify the button's appearance. This package renders
Apple with the same shape as the other providers, using the server-supplied
brand mark; if a reviewer objects, either swap in `SignInWithAppleButton` in a
custom sign-in surface and call `manager.authenticateWithApple()` directly, or
adjust `IdentityProviderButton` to special-case Apple's styling.
