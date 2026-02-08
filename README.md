# RxAuthSwift

OAuth 2.0 authentication library for iOS and macOS with PKCE support and customizable SwiftUI sign-in UI.

## Requirements

- iOS 18+ / macOS 15+
- Swift 6.2+
- Xcode 16+

## Installation

Add to your `Package.swift`:

```swift
dependencies: [
    .package(url: "https://github.com/nicktrienenern/RxAuthSwift.git", from: "1.0.0"),
]
```

Then add the targets you need:

```swift
.target(
    name: "YourApp",
    dependencies: [
        "RxAuthSwift",      // Core OAuth logic
        "RxAuthSwiftUI",    // Sign-in UI components (optional)
    ]
)
```

## Usage

### 1. Configure OAuth

```swift
import RxAuthSwift

let config = RxAuthConfiguration(
    issuer: "https://auth.example.com",
    clientID: "your-client-id",
    redirectURI: "yourapp://callback",
    scopes: ["openid", "profile", "email"]
)
```

Endpoint paths default to `/api/oauth/authorize`, `/api/oauth/token`, `/api/oauth/userinfo` but can be overridden:

```swift
let config = RxAuthConfiguration(
    issuer: "https://auth.example.com",
    clientID: "your-client-id",
    redirectURI: "yourapp://callback",
    authorizePath: "/oauth/authorize",
    tokenPath: "/oauth/token",
    userInfoPath: "/oauth/me"
)
```

### 2. Create OAuthManager

```swift
let authManager = OAuthManager(configuration: config)
```

You can inject custom token storage:

```swift
let authManager = OAuthManager(
    configuration: config,
    tokenStorage: MyCustomTokenStorage()
)
```

### 3. Check Existing Auth on Launch

```swift
@main
struct MyApp: App {
    @State private var authManager = OAuthManager(configuration: config)

    var body: some Scene {
        WindowGroup {
            ContentView()
                .task {
                    await authManager.checkExistingAuth()
                }
        }
    }
}
```

### 4. Show Sign-In UI

**Simple (with appearance customization):**

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
    )
)
```

**With callbacks:**

```swift
RxSignInView(
    manager: authManager,
    onAuthSuccess: {
        // Navigate to home, fetch user data, etc.
    },
    onAuthFailed: { error in
        // Log error, show custom alert, etc.
    }
)
```

**Advanced (fully custom header with ViewBuilder):**

```swift
RxSignInView(
    manager: authManager,
    onAuthSuccess: { print("Signed in!") },
    onAuthFailed: { error in print("Failed: \(error)") }
) {
    VStack {
        Image("Logo")
            .resizable()
            .frame(width: 100, height: 100)
        Text("My App")
            .font(.largeTitle.bold())
    }
}
```

### 5. React to Auth State

```swift
switch authManager.authState {
case .unknown:
    ProgressView()
case .unauthenticated:
    RxSignInView(manager: authManager)
case .authenticated:
    HomeView(user: authManager.currentUser)
}
```

### 6. Logout

```swift
await authManager.logout()
```

### 7. Listen for Session Expiry

```swift
NotificationCenter.default.addObserver(
    forName: .rxAuthSessionExpired,
    object: nil,
    queue: .main
) { _ in
    // Handle session expiry
}
```

## Icon Options

The `SignInIcon` enum supports:

```swift
.systemImage("lock.shield.fill")          // SF Symbol
.image(Image("MyLogo"))                    // SwiftUI Image
.assetImage("AppIcon", Bundle.main)        // Asset catalog
.none                                       // No icon
```

## Custom Token Storage

Implement `TokenStorageProtocol` for custom storage backends:

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

## Glass Effect Support

UI components automatically use `.glassEffect` on iOS 26+ / macOS 26+ and fall back to `.ultraThinMaterial` / `.borderedProminent` on older platforms.

## Building

```bash
# macOS
bash scripts/build-macos.sh

# iOS
bash scripts/build-ios.sh
```

## License

MIT
