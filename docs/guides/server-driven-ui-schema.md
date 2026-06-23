---
slug: guides/server-driven-ui-schema
title: Server-Driven UI Schema
description: How RxAuthSwift fetches and renders the sign-in/sign-up form from a backend-provided schema
---

# Server-Driven UI Schema

`AuthUISchema` lets the backend describe the native sign-in and sign-up forms —
field labels, validation, supported auth methods, and footer links — without
re-shipping the client. `RxSignInView` renders dynamically from these schemas.

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

### Link

Footer links (`id`, `label`, `href`) — e.g. "Forgot password?" or terms of
service.

## Previewing

In `DEBUG` builds, `OAuthManager._previewInject(signIn:signUp:)` injects
pre-baked schemas so SwiftUI previews can render the native form without
hitting the network.
