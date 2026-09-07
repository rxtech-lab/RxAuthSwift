---
slug: guides/server-driven-ui-schema
title: Server-Driven UI Schema
description: How RxAuthSwift fetches and renders the sign-in/sign-up form from a backend-provided schema
---

# Server-Driven UI Schema

`AuthUISchema` lets the backend describe the native sign-in and sign-up forms —
field labels, validation, supported auth methods, social identity providers,
and footer links — without re-shipping the client. `RxSignInView` renders dynamically from these schemas.

## Fetching

The schema is fetched from:

```
GET {issuer}{uiSchemaPath}/{flow}?client_id={clientID}
```

`uiSchemaPath` defaults to `/api/auth/ui-schema`; `flow` is `signin` or
`signup`. Load both flows at once with:

```swift
let (signIn, signUp) = await authManager.loadUISchema()
```

Results are stored on the manager as `signInSchema` and `signUpSchema`, with
`isLoadingSchema` reflecting progress. A single flow can be fetched with
`fetchUISchema(flow:)`. A failed or missing schema returns `nil` and the UI
falls back to its defaults rather than erroring.

## Schema shape

```swift
public struct AuthUISchema: Codable, Sendable, Equatable {
    public enum Flow: String { case signin, signup }

    public let flow: Flow
    public let title: String
    public let submitLabel: String
    public let fields: [Field]
    public let supportedMethods: [SupportedMethod]
    public let identityProviders: [IdentityProvider]?
    public let links: [Link]?
}
```

### Field

| Property | Type | Notes |
| --- | --- | --- |
| `key` | `String` | Unique field key (also its `id`). |
| `label` | `String` | Display label. |
| `placeholder` | `String?` | Optional placeholder. |
| `type` | `text` \| `email` \| `password` \| `name` | Keyboard / semantics. |
| `isPassword` | `Bool` | Secure entry. |
| `required` | `Bool` | Validation. |
| `autocomplete` | `String?` | Text-content type hint. |
| `validation` | `Validation?` | `minLength`, `maxLength`, `pattern`, `patternMessage`. |

`Field.validate(_:)` returns a user-facing error string when a value fails its
rules, or `nil` when it passes. Required-but-empty, length, and regex checks
are applied in that order.

### SupportedMethod

```swift
public enum MethodID: String {
    case password
    case passkey
    case passkeyAccountCreation = "passkey_account_creation"
}
```

Each method carries a `label` and a `primary` flag. The primary method is the
prominent button; non-primary methods are grouped together as secondary
options. Emit `passkey_account_creation` only on the signup flow.

### IdentityProvider

```swift
public struct IdentityProvider: Codable, Sendable, Equatable, Identifiable {
    public let id: String
    public let label: String                       // "Continue with Google"
    public let iconUrl: String?                    // absolute URL, usually SVG
    public let darkIconUrl: String?
    public let authorizationParameters: [String: String]

    public func iconURL(dark: Bool) -> URL?        // darkIconUrl ?? iconUrl
}
```

Social sign-in options. Each entry renders as a "Continue with …" row under
the alternative methods in the native picker. Tapping one calls
`OAuthManager.authenticate(identityProvider:)`, which runs the normal browser
authorization-code + PKCE flow with `authorizationParameters` appended to the
authorize URL (for RxLab Auth that is `identity_provider=<id>`), so the
server hands the user straight to the provider instead of its own login page.
Because the account is created server-side on first use, the same flow serves
both sign-in and sign-up.

Icons are fetched live from `iconUrl` / `darkIconUrl` (chosen by the current
color scheme) and rendered with [SwiftDraw](https://github.com/swhitty/SwiftDraw),
so a newly enabled provider shows its real mark without a client update. Keep
the SVGs simple — flat paths, gradients, and clip paths render; filters such
as `feGaussianBlur` and masks do not. URLs must be absolute; a missing,
relative, or unrenderable icon falls back to a generic symbol.

Emit `identityProviders` as an empty array or omit it entirely when no
providers are configured; both decode fine.

### Link

Footer links (`id`, `label`, `href`) — e.g. "Forgot password?" or terms of
service.

## Previewing

In `DEBUG` builds, `OAuthManager._previewInject(signIn:signUp:)` injects
pre-baked schemas so SwiftUI previews can render the native form without
hitting the network.
