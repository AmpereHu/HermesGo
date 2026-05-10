import SwiftUI

public struct ApprovalCardView: View {
    public let approval: Approval
    public let onChoice: (ApprovalChoice) -> Void

    public init(approval: Approval, onChoice: @escaping (ApprovalChoice) -> Void) {
        self.approval = approval
        self.onChoice = onChoice
    }

    public var body: some View {
        VStack(alignment: .leading, spacing: 10) {
            HStack {
                Image(systemName: "exclamationmark.shield.fill")
                    .foregroundStyle(AppColors.approvalBorder)
                Text("需要核准")
                    .font(.headline)
                Spacer()
            }
            Text(approval.command)
                .font(.system(.callout, design: .monospaced))
                .padding(8)
                .frame(maxWidth: .infinity, alignment: .leading)
                .background(AppColors.toolBackground, in: RoundedRectangle(cornerRadius: 8, style: .continuous))
                .textSelection(.enabled)

            if let description = approval.description, !description.isEmpty {
                Text(description)
                    .font(.footnote)
                    .foregroundStyle(.secondary)
            }

            // RULE-9: pattern_keys plural - render every key.
            if !approval.patternKeys.isEmpty {
                ScrollView(.horizontal, showsIndicators: false) {
                    HStack(spacing: 6) {
                        ForEach(approval.patternKeys, id: \.self) { key in
                            Text(key)
                                .font(.caption2.monospaced())
                                .padding(.horizontal, 6)
                                .padding(.vertical, 2)
                                .background(AppColors.toolBackground, in: Capsule())
                                .foregroundStyle(.secondary)
                        }
                    }
                }
            }

            VStack(spacing: 8) {
                HStack(spacing: 8) {
                    actionButton(.allowOnce, color: AppColors.accent)
                    actionButton(.allowSession, color: AppColors.accent.opacity(0.85))
                }
                HStack(spacing: 8) {
                    actionButton(.allowAlways, color: AppColors.accent.opacity(0.7))
                    actionButton(.deny, color: AppColors.danger)
                }
            }
        }
        .padding(14)
        .background(AppColors.approvalBackground, in: RoundedRectangle(cornerRadius: 16, style: .continuous))
        .overlay(
            RoundedRectangle(cornerRadius: 16, style: .continuous)
                .stroke(AppColors.approvalBorder, lineWidth: 1)
        )
        .padding(.horizontal)
    }

    private func actionButton(_ choice: ApprovalChoice, color: Color) -> some View {
        Button {
            onChoice(choice)
        } label: {
            Text(choice.displayName)
                .font(.callout.weight(.semibold))
                .frame(maxWidth: .infinity)
                .padding(.vertical, 10)
                .background(color, in: RoundedRectangle(cornerRadius: 10, style: .continuous))
                .foregroundStyle(.white)
        }
        .buttonStyle(.plain)
    }
}
