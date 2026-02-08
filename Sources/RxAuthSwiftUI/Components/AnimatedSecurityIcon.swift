import SwiftUI

public struct AnimatedSecurityIcon: View {
    public enum Style {
        case lock
        case denied
    }

    let style: Style
    @State private var isPulsing = false
    @State private var shakeOffset: CGFloat = 0

    public init(style: Style = .lock) {
        self.style = style
    }

    public var body: some View {
        ZStack {
            RoundedRectangle(cornerRadius: 16)
                .fill(.ultraThinMaterial)
                .frame(width: 64, height: 64)
                .overlay(
                    RoundedRectangle(cornerRadius: 16)
                        .stroke(iconColor.opacity(0.3), lineWidth: 1)
                )

            Image(systemName: iconName)
                .font(.system(size: 28, weight: .medium))
                .foregroundStyle(iconColor)
                .scaleEffect(isPulsing ? 1.1 : 1.0)
        }
        .offset(x: shakeOffset)
        .onAppear {
            switch style {
            case .lock:
                withAnimation(.easeInOut(duration: 1.8).repeatForever(autoreverses: true)) {
                    isPulsing = true
                }
            case .denied:
                shakeAnimation()
            }
        }
    }

    private var iconName: String {
        switch style {
        case .lock: return "lock.fill"
        case .denied: return "xmark.circle.fill"
        }
    }

    private var iconColor: Color {
        switch style {
        case .lock: return .orange
        case .denied: return .red
        }
    }

    private func shakeAnimation() {
        withAnimation(.default) {
            shakeOffset = 10
        }
        DispatchQueue.main.asyncAfter(deadline: .now() + 0.1) {
            withAnimation(.default) {
                shakeOffset = -8
            }
        }
        DispatchQueue.main.asyncAfter(deadline: .now() + 0.2) {
            withAnimation(.default) {
                shakeOffset = 5
            }
        }
        DispatchQueue.main.asyncAfter(deadline: .now() + 0.3) {
            withAnimation(.spring(response: 0.2, dampingFraction: 0.5)) {
                shakeOffset = 0
            }
        }
    }
}
