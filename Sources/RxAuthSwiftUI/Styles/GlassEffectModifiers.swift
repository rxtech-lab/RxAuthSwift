import SwiftUI

struct GlassBackground: ViewModifier {
    func body(content: Content) -> some View {
        if #available(iOS 26.0, macOS 26.0, *) {
            content.glassEffect(.regular.tint(.white.opacity(0.1)))
        } else {
            content.background(.ultraThinMaterial)
        }
    }
}

struct GlassProminentButtonStyle: ViewModifier {
    func body(content: Content) -> some View {
        if #available(iOS 26.0, macOS 26.0, *) {
            content.buttonStyle(.glassProminent)
        } else {
            content.buttonStyle(.borderedProminent)
        }
    }
}

struct GlassButtonStyle: ViewModifier {
    func body(content: Content) -> some View {
        if #available(iOS 26.0, macOS 26.0, *) {
            content.buttonStyle(.glass)
        } else {
            content.buttonStyle(.bordered)
        }
    }
}

extension View {
    func rxGlassBackground() -> some View {
        modifier(GlassBackground())
    }

    func rxGlassProminentButton() -> some View {
        modifier(GlassProminentButtonStyle())
    }

    func rxGlassButton() -> some View {
        modifier(GlassButtonStyle())
    }
}
