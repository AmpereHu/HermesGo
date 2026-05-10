import SwiftUI

public struct ComposerView: View {
    @Binding public var text: String
    public let isBusy: Bool
    public let canSend: Bool
    public let onSend: () -> Void
    public let onCancel: () -> Void

    @FocusState private var isFocused: Bool

    public init(
        text: Binding<String>,
        isBusy: Bool,
        canSend: Bool,
        onSend: @escaping () -> Void,
        onCancel: @escaping () -> Void
    ) {
        self._text = text
        self.isBusy = isBusy
        self.canSend = canSend
        self.onSend = onSend
        self.onCancel = onCancel
    }

    public var body: some View {
        HStack(alignment: .bottom, spacing: 8) {
            TextField("傳訊息給 Hermes…", text: $text, axis: .vertical)
                .textFieldStyle(.plain)
                .lineLimit(1...6)
                .focused($isFocused)
                .padding(.horizontal, 12)
                .padding(.vertical, 8)
                .background(AppColors.assistantBubble, in: RoundedRectangle(cornerRadius: 18, style: .continuous))
                .onSubmit(submit)

            if isBusy {
                Button(role: .destructive, action: onCancel) {
                    Image(systemName: "stop.circle.fill")
                        .font(.system(size: 28))
                        .foregroundStyle(.red)
                }
                .accessibilityLabel("取消")
            } else {
                Button(action: submit) {
                    Image(systemName: "paperplane.circle.fill")
                        .font(.system(size: 28))
                        .foregroundStyle(canSend ? AppColors.accent : Color.secondary)
                }
                .disabled(!canSend)
                .accessibilityLabel("傳送")
            }
        }
        .padding(.horizontal, 12)
        .padding(.vertical, 8)
        .background(.bar)
    }

    private func submit() {
        guard canSend, !isBusy else { return }
        onSend()
    }
}
