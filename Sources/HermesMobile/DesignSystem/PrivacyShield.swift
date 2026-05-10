import SwiftUI

private struct PrivacyShieldModifier: ViewModifier {
    @Environment(\.scenePhase) private var scenePhase

    func body(content: Content) -> some View {
        ZStack {
            content
            if scenePhase != .active {
                Rectangle()
                    .fill(.ultraThinMaterial)
                    .ignoresSafeArea()
                    .overlay(
                        Image(systemName: "lock.shield")
                            .font(.system(size: 48))
                            .foregroundStyle(.secondary)
                    )
                    .transition(.opacity)
            }
        }
        .animation(.easeInOut(duration: 0.2), value: scenePhase)
    }
}

public extension View {
    func privacyShield() -> some View {
        modifier(PrivacyShieldModifier())
    }
}
