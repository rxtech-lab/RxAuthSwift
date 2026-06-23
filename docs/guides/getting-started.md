---
slug: guides/getting-started
title: Getting Started
description: Install RxAuthSwift, configure OAuth, and present the sign-in UI
---

# Getting Started

## Requirements

- iOS 18+ / macOS 15+ (the Swift package declares iOS 26 / macOS 26 as the
  build platforms; newer-API features degrade gracefully at runtime)
- Swift 6.2+ / Xcode 16+

## Installation

Add the package to your `Package.swift`:

```swift
dependencies: [
    .package(url: "https://github.com/rxtech-lab/RxAuthSwift.git", from: "1.0.0"),
]
```

Then depend on the targets you need:

```swift
.target(
    name: "YourApp",
    dependencies: [
        "RxAuthSwift",      // Core OAuth logic
        "RxAuthSwiftUI",    // Sign-in UI components (optional)
    ]
)
```

## 1. Configure OAuth

```swift
import RxAuthSwift

let config = RxAuthConfiguration(
    issuer: "https://auth.example.com",
    clientID: "your-client-id",
    redirectURI: "yourapp://callback",
    scopes: ["openid", "profile", "email"]
)
```

Endpoint paths default to `/api/oauth/authorize`, `/api/oauth/token`, and
`/api/oauth/userinfo`, and can each be overridden. See
[Configuration reference](../code/rxauthswift-core.md) for every parameter.

## 2. Create an OAuthManager

```swift
let authManager = OAuthManager(configuration: config)
```

You can inject custom token storage or a logger:

```swift
let authManager = OAuthManager(
    configuration: config,
    tokenStorage: MyCustomTokenStorage()
)
```

## 3. Restore the session on launch

```swift
@main
struct MyApp: App {
    @State private var authManager = OAuthManager(configuration: config)

    var body: some Scene {
        WindowGroup {
            ContentView()
                .task { await authManager.checkExistingAuth() }
        }
    }
}
```

## 4. Show the sign-in UI

```swift
import RxAuthSwiftUI

RxSignInView(
    manager: authManager,
    appearance: RxSignInAppearance(
        icon: .image(Image("MyLogo")),
        title: "Welcome",
        subtitle: "Sign in to continue",
        signInButtonTitle: "Get Started",
        accentColor: .purple,
        secondaryColor: .pink
    ),
    onAuthSuccess: { /* navigate home */ },
    onAuthFailed: { error in /* show alert */ }
)
```

See the [SwiftUI module reference](../code/rxauthswiftui.md) for the advanced
ViewBuilder initializer and every appearance option.

## 5. React to auth state

```swift
switch authManager.authState {
case .unknown:        ProgressView()
case .unauthenticated: RxSignInView(manager: authManager)
case .authenticated:   HomeView(user: authManager.currentUser)
}
```

## 6. Log out

```swift
await authManager.logout()
```

## 7. Handle session expiry

```swift
NotificationCenter.default.addObserver(
    forName: .rxAuthSessionExpired,
    object: nil,
    queue: .main
) { _ in
    // Session could not be refreshed; route back to sign-in.
}
```
