import SwiftUI

public struct SessionRowView: View {
    public let session: SessionListItem

    public init(session: SessionListItem) {
        self.session = session
    }

    public var body: some View {
        VStack(alignment: .leading, spacing: 4) {
            HStack(alignment: .firstTextBaseline) {
                Text(session.title.isEmpty ? "(未命名)" : session.title)
                    .font(.body.weight(.semibold))
                    .lineLimit(1)
                Spacer(minLength: 8)
                if session.pinned {
                    Image(systemName: "pin.fill")
                        .font(.caption2)
                        .foregroundStyle(.tertiary)
                }
            }
            HStack(spacing: 8) {
                Text(DateFormatters.relativeText(from: session.updatedAt))
                    .font(.caption)
                    .foregroundStyle(.secondary)
                if !session.model.isEmpty {
                    Text(session.model)
                        .font(.caption2.monospaced())
                        .padding(.horizontal, 6)
                        .padding(.vertical, 2)
                        .background(AppColors.toolBackground, in: Capsule())
                        .foregroundStyle(.secondary)
                }
            }
        }
        .padding(.vertical, 4)
    }
}
