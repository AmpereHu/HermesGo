import SwiftUI

public enum AppTypography {
    public static let title = Font.title2.weight(.semibold)
    public static let body = Font.body
    public static let caption = Font.caption.weight(.regular)
    public static let codeMono = Font.system(.callout, design: .monospaced)
}

public extension View {
    func sectionHeader() -> some View {
        self
            .font(.subheadline.weight(.semibold))
            .foregroundStyle(.secondary)
            .textCase(.uppercase)
    }
}
