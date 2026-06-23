---
slug: code/rxauthswiftui
title: RxAuthSwiftUI API Reference
description: Public API of the RxAuthSwiftUI target — RxSignInView and RxSignInAppearance
---

# RxAuthSwiftUI API Reference

Public symbols in the `RxAuthSwiftUI` target. This module depends on
`RxAuthSwift` and provides a drop-in SwiftUI sign-in surface driven by an
`OAuthManager`.

## RxSignInView

`public struct RxSignInView<Header: View>: View` — the sign-in / sign-up
surface. It renders from the manager's server-driven `AuthUISchema` when
available, falling back to sensible defaults, and automatically loads the
schema on first appearance. On macOS it shows native username/password fields
and an optional animated gradient background; passkey buttons appear when the
manager reports the matching capability.

### Simple initializer (appearance struct)

```swift
public init(
    manager: OAuthManager,
    appearance: RxSignInAppearance = RxSignInAppearance(),
    onAuthSuccess: (() -> Void)? = nil,
    onAuthFailed: ((Error) -> Void)? = nil
) where Header == Never
```

### Advanced initializer (custom header)

```swift
public init(
    manager: OAuthManager,
    appearance: RxSignInAppearance = RxSignInAppearance(),
    onAuthSuccess: (() -> Void)? = nil,
    onAuthFailed: ((Error) -> Void)? = nil,
    @ViewBuilder header: () -> Header
)
```

The `header` ViewBuilder replaces the default icon/title/subtitle block with
fully custom content.

### Example

```swift
RxSignInView(manager: authManager) {
    VStack {
        Image("Logo").resizable().frame(width: 100, height: 100)
        Text("My App").font(.largeTitle.bold())
    }
}
```

## RxSignInAppearance

`public struct RxSignInAppearance: @unchecked Sendable` — styling and copy for
`RxSignInView`.

### Properties / initializer defaults

| Property | Type | Default |
| --- | --- | --- |
| `icon` | `SignInIcon` | `.systemImage("lock.shield.fill")` |
| `title` | `LocalizedStringKey` | `"Welcome"` |
| `subtitle` | `LocalizedStringKey` | `"Sign in to continue"` |
| `signInButtonTitle` | `LocalizedStringKey` | `"Sign In"` |
| `signUpButtonTitle` | `LocalizedStringKey` | `"Create Account"` |
| `usernamePlaceholder` | `LocalizedStringKey` | `"Username"` |
| `passwordPlaceholder` | `LocalizedStringKey` | `"Password"` |
| `namePlaceholder` | `LocalizedStringKey` | `"Name"` |
| `passkeyButtonTitle` | `LocalizedStringKey` | `"Continue with Passkey"` |
| `passkeySignupButtonTitle` | `LocalizedStringKey` | `"Create Passkey Account"` |
| `accentColor` | `Color` | `.blue` |
| `secondaryColor` | `Color` | `.purple` |
| `showsAnimatedBackground` | `Bool` | `true` |

### SignInIcon

```swift
public enum SignInIcon: Sendable {
    case systemImage(String)        // SF Symbol
    case image(Image)               // SwiftUI Image
    case assetImage(String, Bundle?) // Asset catalog
    case none                       // No icon
}
```

## Glass effect

UI components use `.glassEffect` on iOS 26+ / macOS 26+ and fall back to
`.ultraThinMaterial` / `.borderedProminent` on older platforms.
