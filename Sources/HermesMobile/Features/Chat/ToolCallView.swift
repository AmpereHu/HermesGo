import SwiftUI

public struct ToolCallView: View {
    public let toolCall: ToolCall

    public init(toolCall: ToolCall) {
        self.toolCall = toolCall
    }

    public var body: some View {
        HStack(alignment: .top, spacing: 10) {
            Image(systemName: "wrench.and.screwdriver.fill")
                .foregroundStyle(.secondary)
            VStack(alignment: .leading, spacing: 4) {
                Text("Running \(toolCall.name)…")
                    .font(.callout.weight(.medium))
                if !toolCall.preview.isEmpty {
                    Text(toolCall.preview)
                        .font(.footnote.monospaced())
                        .foregroundStyle(.secondary)
                        .lineLimit(3)
                }
            }
            Spacer()
            ProgressView()
                .controlSize(.small)
        }
        .padding(10)
        .background(AppColors.toolBackground, in: RoundedRectangle(cornerRadius: 12, style: .continuous))
    }
}
