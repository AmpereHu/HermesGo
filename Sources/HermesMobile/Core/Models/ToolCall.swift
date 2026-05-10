import Foundation

public struct ToolCall: Identifiable, Hashable, Sendable {
    public let id: UUID
    public let name: String
    public let preview: String
    public var isCompleted: Bool

    public init(
        id: UUID = UUID(),
        name: String,
        preview: String,
        isCompleted: Bool = false
    ) {
        self.id = id
        self.name = name
        self.preview = preview
        self.isCompleted = isCompleted
    }
}
