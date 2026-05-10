import SwiftUI
import MarkdownUI

public struct MessageBubbleView: View {
    public let message: Message
    public var isStreaming: Bool

    public init(message: Message, isStreaming: Bool = false) {
        self.message = message
        self.isStreaming = isStreaming
    }

    public var body: some View {
        HStack {
            if message.role == .user {
                Spacer(minLength: 40)
            }
            content
            if message.role != .user {
                Spacer(minLength: 40)
            }
        }
        .contextMenu {
            Button {
                #if canImport(UIKit)
                UIPasteboard.general.string = message.content
                #endif
            } label: {
                Label("複製", systemImage: "doc.on.doc")
            }
        }
    }

    @ViewBuilder
    private var content: some View {
        switch message.role {
        case .user:
            userBubble
        case .assistant:
            assistantBubble
        case .system, .tool:
            systemBubble
        }
    }

    private var userBubble: some View {
        Text(message.content)
            .padding(.vertical, 10)
            .padding(.horizontal, 14)
            .background(AppColors.userBubble, in: RoundedRectangle(cornerRadius: 18, style: .continuous))
            .foregroundStyle(.white)
            .textSelection(.enabled)
    }

    private var assistantBubble: some View {
        Group {
            if isStreaming {
                Text(message.content)
                    .padding(.vertical, 10)
                    .padding(.horizontal, 14)
                    .frame(maxWidth: .infinity, alignment: .leading)
                    .background(AppColors.assistantBubble, in: RoundedRectangle(cornerRadius: 18, style: .continuous))
                    .textSelection(.enabled)
            } else {
                Markdown(message.content)
                    .padding(.vertical, 10)
                    .padding(.horizontal, 14)
                    .frame(maxWidth: .infinity, alignment: .leading)
                    .background(AppColors.assistantBubble, in: RoundedRectangle(cornerRadius: 18, style: .continuous))
                    .textSelection(.enabled)
            }
        }
    }

    private var systemBubble: some View {
        Text(message.content)
            .font(.footnote)
            .foregroundStyle(.secondary)
            .padding(.vertical, 6)
            .padding(.horizontal, 12)
            .background(AppColors.toolBackground, in: RoundedRectangle(cornerRadius: 12, style: .continuous))
            .frame(maxWidth: .infinity, alignment: .leading)
    }
}
