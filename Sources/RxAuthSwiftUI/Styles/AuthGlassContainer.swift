import SwiftUI

struct AuthGlassContainer<Content: View>: View {
    let spacing: CGFloat
    @ViewBuilder var content: () -> Content

    var body: some View {
        #if os(visionOS)
        content()
        #else
        GlassEffectContainer(spacing: spacing, content: content)
        #endif
    }
}
