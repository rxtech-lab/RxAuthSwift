import SwiftUI

struct GlassBackground: ViewModifier {
    func body(content: Content) -> some View {
        #if os(visionOS)
            content.background(.ultraThinMaterial)
        #else
        if #available(iOS 26.0, macOS 26.0, *) {
            content.glassEffect(.regular.tint(.white.opacity(0.1)))
        } else {
            content.background(.ultraThinMaterial)
        }
        #endif
    }
}

struct GlassProminentButtonStyle: ViewModifier {
    func body(content: Content) -> some View {
        #if os(visionOS)
            content.buttonStyle(.borderedProminent)
        #else
        if #available(iOS 26.0, macOS 26.0, *) {
            content.buttonStyle(.glassProminent)
        } else {
            content.buttonStyle(.borderedProminent)
        }
        #endif
    }
}

struct GlassButtonStyle: ViewModifier {
    func body(content: Content) -> some View {
        #if os(visionOS)
            content.buttonStyle(.bordered)
        #else
        if #available(iOS 26.0, macOS 26.0, *) {
            content.buttonStyle(.glass)
        } else {
            content.buttonStyle(.bordered)
        }
        #endif
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
