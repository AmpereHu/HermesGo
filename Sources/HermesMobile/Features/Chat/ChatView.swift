import SwiftUI

public struct ChatView: View {
    @Bindable private var viewModel: ChatViewModel
    @Environment(\.scenePhase) private var scenePhase
    @State private var composerText: String = ""

    public init(viewModel: ChatViewModel) {
        self.viewModel = viewModel
    }

    public var body: some View {
        VStack(spacing: 0) {
            if let approval = viewModel.pendingApproval {
                ApprovalCardView(approval: approval) { choice in
                    Task { await viewModel.respondApproval(choice) }
                }
                .padding(.top, 8)
            }

            messagesList

            ComposerView(
                text: $composerText,
                isBusy: viewModel.isStreaming,
                canSend: !composerText.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty,
                onSend: send,
                onCancel: { Task { await viewModel.cancel() } }
            )
        }
        .navigationTitle(viewModel.session?.title ?? "Chat")
        .navigationBarTitleDisplayMode(.inline)
        .task(id: viewModel.sessionId) {
            await viewModel.load()
        }
        .onChange(of: scenePhase) { _, newPhase in
            switch newPhase {
            case .background, .inactive:
                viewModel.handleBackground()
            case .active:
                Task { await viewModel.handleForeground() }
            @unknown default:
                break
            }
        }
        .alert("錯誤", isPresented: .init(
            get: { viewModel.errorMessage != nil },
            set: { if !$0 { viewModel.errorMessage = nil } }
        )) {
            Button("OK") { viewModel.errorMessage = nil }
        } message: {
            if let message = viewModel.errorMessage {
                Text(message)
            }
        }
    }

    private var messagesList: some View {
        ScrollViewReader { proxy in
            ScrollView {
                LazyVStack(alignment: .leading, spacing: 10) {
                    ForEach(viewModel.messages) { message in
                        MessageBubbleView(message: message)
                            .id(message.id)
                    }
                    if viewModel.isStreaming, !viewModel.streamingMessage.isEmpty {
                        MessageBubbleView(
                            message: Message(role: .assistant, content: viewModel.streamingMessage),
                            isStreaming: true
                        )
                        .id("streaming")
                    }
                    if let toolCall = viewModel.currentToolCall {
                        ToolCallView(toolCall: toolCall)
                    }
                }
                .padding(.horizontal, 12)
                .padding(.vertical, 12)
            }
            .onChange(of: viewModel.messages.count) { _, _ in
                scrollToBottom(proxy)
            }
            .onChange(of: viewModel.streamingMessage) { _, _ in
                scrollToBottom(proxy)
            }
        }
    }

    private func scrollToBottom(_ proxy: ScrollViewProxy) {
        if viewModel.isStreaming, !viewModel.streamingMessage.isEmpty {
            withAnimation(.easeOut(duration: 0.15)) {
                proxy.scrollTo("streaming", anchor: .bottom)
            }
        } else if let last = viewModel.messages.last {
            withAnimation(.easeOut(duration: 0.15)) {
                proxy.scrollTo(last.id, anchor: .bottom)
            }
        }
    }

    private func send() {
        let text = composerText
        composerText = ""
        Task { await viewModel.send(text) }
    }
}
