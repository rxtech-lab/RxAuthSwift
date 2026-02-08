import SwiftUI

public struct RxSignInAppearance: Sendable {
    public var icon: SignInIcon
    public var title: String
    public var subtitle: String
    public var signInButtonTitle: String
    public var accentColor: Color
    public var secondaryColor: Color

    public init(
        icon: SignInIcon = .systemImage("lock.shield.fill"),
        title: String = "Welcome",
        subtitle: String = "Sign in to continue",
        signInButtonTitle: String = "Sign In",
        accentColor: Color = .blue,
        secondaryColor: Color = .purple
    ) {
        self.icon = icon
        self.title = title
        self.subtitle = subtitle
        self.signInButtonTitle = signInButtonTitle
        self.accentColor = accentColor
        self.secondaryColor = secondaryColor
    }

    public enum SignInIcon: Sendable {
        case systemImage(String)
        case image(Image)
        case assetImage(String, Bundle?)
        case none
    }
}
