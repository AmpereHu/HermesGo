import SwiftUI

public enum AppColors {
    public static let accent = Color(red: 95/255, green: 179/255, blue: 159/255)
    public static let userBubble = Color.accentColor.opacity(0.85)
    public static let assistantBubble = Color(.secondarySystemBackground)
    public static let toolBackground = Color(.tertiarySystemBackground)
    public static let approvalBackground = Color.orange.opacity(0.15)
    public static let approvalBorder = Color.orange
    public static let danger = Color.red
    public static let muted = Color.secondary
}
