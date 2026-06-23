import SwiftUI

/// Controls how `RxSignInView` collects credentials.
///
/// On iOS this is honored directly; `.web` (the default) launches the system
/// web authentication session, while `.native` renders the in-app credential
/// form. On macOS the view always uses the native form regardless of this
/// value, since that is its only supported presentation.
public enum RxSignInStyle: Sendable {
    /// Presents the system web authentication session (`ASWebAuthenticationSession`).
    case web
    /// Presents an in-app native credential form (email / password, plus
    /// passkeys on platforms where they are available).
    case native
}

public struct RxSignInAppearance: @unchecked Sendable {
    public var icon: SignInIcon
    public var title: LocalizedStringKey
    public var subtitle: LocalizedStringKey
    public var signInButtonTitle: LocalizedStringKey
    public var signUpButtonTitle: LocalizedStringKey
    public var usernamePlaceholder: LocalizedStringKey
    public var passwordPlaceholder: LocalizedStringKey
    public var namePlaceholder: LocalizedStringKey
    public var passkeyButtonTitle: LocalizedStringKey
    public var passkeySignupButtonTitle: LocalizedStringKey
    public var accentColor: Color
    public var secondaryColor: Color
    public var showsAnimatedBackground: Bool

    public init(
        icon: SignInIcon = .systemImage("lock.shield.fill"),
        title: LocalizedStringKey = "Welcome",
        subtitle: LocalizedStringKey = "Sign in to continue",
        signInButtonTitle: LocalizedStringKey = "Sign In",
        signUpButtonTitle: LocalizedStringKey = "Create Account",
        usernamePlaceholder: LocalizedStringKey = "Username",
        passwordPlaceholder: LocalizedStringKey = "Password",
        namePlaceholder: LocalizedStringKey = "Name",
        passkeyButtonTitle: LocalizedStringKey = "Continue with Passkey",
        passkeySignupButtonTitle: LocalizedStringKey = "Create Passkey Account",
        accentColor: Color = .blue,
        secondaryColor: Color = .purple,
        showsAnimatedBackground: Bool = true
    ) {
        self.icon = icon
        self.title = title
        self.subtitle = subtitle
        self.signInButtonTitle = signInButtonTitle
        self.signUpButtonTitle = signUpButtonTitle
        self.usernamePlaceholder = usernamePlaceholder
        self.passwordPlaceholder = passwordPlaceholder
        self.namePlaceholder = namePlaceholder
        self.passkeyButtonTitle = passkeyButtonTitle
        self.passkeySignupButtonTitle = passkeySignupButtonTitle
        self.accentColor = accentColor
        self.secondaryColor = secondaryColor
        self.showsAnimatedBackground = showsAnimatedBackground
    }

    public enum SignInIcon: Sendable {
        case systemImage(String)
        case image(Image)
        case assetImage(String, Bundle?)
        case none
    }
}
