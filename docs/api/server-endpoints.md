---
slug: api/server-endpoints
title: Backend Endpoint Contract
description: HTTP endpoints RxAuthSwift calls and the request/response shapes a compatible auth server must implement
---

# Backend Endpoint Contract

RxAuthSwift is a client; this page documents what a compatible auth server
must expose. Paths are relative to `issuer` and configurable on
`RxAuthConfiguration`. All token-issuing endpoints must return the standard
OAuth token JSON shape (below).

## Token response shape

Every token-issuing endpoint returns:

```json
{
  "access_token": "…",
  "refresh_token": "…",   // optional
  "expires_in": 3600,      // optional, seconds
  "token_type": "Bearer"  // optional
}
```

OAuth-style error responses (`{ "error": "...", "error_description": "..." }`)
are surfaced to the user via `error_description` when present.

## Authorization code + PKCE

- `GET {authorizePath}` (default `/api/oauth/authorize`) — standard
  authorization endpoint. The client sends `response_type=code`, `client_id`,
  `redirect_uri`, `scope`, `code_challenge`, `code_challenge_method=S256`.
- `POST {tokenPath}` (default `/api/oauth/token`),
  `application/x-www-form-urlencoded`:
  - **authorization_code**: `grant_type`, `code`, `redirect_uri`, `client_id`,
    `code_verifier`.
  - **refresh_token**: `grant_type`, `refresh_token`, `client_id`.
- `GET {userInfoPath}` (default `/api/oauth/userinfo`) — `Authorization: Bearer
  {access_token}`; returns a user object with `id`/`sub`, optional `name`,
  `email`, `image`/`picture`.

## Native password grant

`POST {nativePasswordTokenPath ?? tokenPath}`,
`application/x-www-form-urlencoded`: `grant_type=password`, `username`,
`password`, `client_id`, `scope`.

## Native sign-up

`POST {nativeSignupPath}` (default `/api/oauth/signup`), `application/json`:

```json
{ "client_id": "…", "username": "…", "password": "…", "name": "…", "scope": "…" }
```

Respond with either the token JSON (immediate sign-in) or a
verification-required payload:

```json
{ "user_id": "…", "email": "…", "email_verification_required": true }
```

## Passkey sign-in

- `POST {passkeyChallengePath}`, `application/json`:
  `{ "client_id", "redirect_uri", "username"? }`. Returns a base64url
  `challenge`, optional session id (`sessionID`/`sessionId`/`requestID`),
  optional relying-party id (`relyingPartyIdentifier`/`relyingPartyId`/`rpId`),
  and optional allowed credentials
  (`allowedCredentialIDs`/`allowedCredentials`/`allowCredentials`).
- `POST {passkeyVerificationPath}`, `application/json`: `{ "client_id",
  "session_id"?, "scope"?, "credential": { id, rawId, type, response: {
  clientDataJSON, authenticatorData, signature, userHandle } } }`. Returns
  token JSON.

## Passkey registration

- `POST {passkeyRegistrationChallengePath}`, `application/json`:
  `{ "client_id", "redirect_uri", "username", "name"? }`. Returns base64url
  `challenge` and `userID` (flat or nested under `user`), optional
  session/username/RP id.
- `POST {passkeyRegistrationVerificationPath}`, `application/json`:
  `{ "client_id", "session_id"?, "scope"?, "credential": { id, rawId, type,
  response: { clientDataJSON, attestationObject? } } }`. Returns token JSON.

## Passkey upgrade

Bearer-authenticated with the current access token.

- `POST {passkeyUpgradeChallengePath}` — body `{}`, `Authorization: Bearer …`.
  Same challenge shape as registration.
- `POST {passkeyUpgradeVerificationPath}` — `Authorization: Bearer …`,
  `{ "session_id"?, "name", "registration": { … credential … } }`.

## System-sheet account creation (iOS 26 / macOS 26)

- `POST {passkeyAccountCreationOptionsPath}`, `application/json`:
  `{ "client_id", "redirect_uri" }`. Same challenge shape as registration
  (username/displayName ignored — supplied by the OS).
- `POST {passkeyAccountCreationVerifyPath}`, `application/json`:
  `{ "client_id", "session_id"?, "scope"?, "contact_identifier",
  "contact_identifier_type", "name"?, "credential": { … } }`. Returns token
  JSON.

## Native Sign in with Apple

Two calls, mirroring the passkey options/verify shape. Only reachable when the
server has Apple configured — an unconfigured deployment omits `apple` from the
UI schema's `identityProviders`, so the client never draws the button and never
calls these.

- `POST {appleNoncePath}` (default `/api/oauth/social/apple/nonce`),
  `application/json`: `{ "client_id", "redirect_uri" }` →
  `{ "session_id", "nonce" }`. The nonce is single-use and expires in 5 minutes.
- The client passes **SHA-256(nonce), hex-encoded** as
  `ASAuthorizationAppleIDRequest.nonce`; Apple copies it into the identity
  token's `nonce` claim.
- `POST {appleNativeSignInPath}` (default `/api/oauth/social/apple`),
  `application/json`:
  `{ "client_id", "session_id", "nonce", "identity_token",
  "full_name": { "given_name"?, "family_name"? }?, "scope"? }`.
  Returns token JSON.

The server verifies the identity token's signature against Apple's JWKS, pins
`iss` to `https://appleid.apple.com` and `aud` to one of `APPLE_OAUTH_BUNDLE_IDS`
(native tokens are audienced to the app's bundle ID, not the web Services ID),
re-hashes the raw nonce to confirm the token was minted for this request, and
then burns the nonce.

`full_name` is Apple's first-authorization-only payload. Apple releases the
user's name to the app exactly **once**, on the very first consent, and never
again — so send it on that call or the display name is lost permanently.

Error responses use the usual OAuth shape: `invalid_grant` for a token that
fails verification or a stale/mismatched nonce, `access_denied` (403) when
sign-up is disabled or the address isn't whitelisted, `409` when the Apple
account is already linked elsewhere.

## Server-driven UI schema

`GET {uiSchemaPath}/{flow}?client_id={clientID}` (default
`/api/auth/ui-schema`), `flow` ∈ `signin` | `signup`. Returns an
[`AuthUISchema`](../guides/server-driven-ui-schema.md) JSON document.
