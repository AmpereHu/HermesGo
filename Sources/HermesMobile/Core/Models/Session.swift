import Foundation

public struct Session: Codable, Identifiable, Hashable, Sendable {
    public let sessionId: String
    public var title: String
    public var workspace: String
    public var model: String
    public var messages: [Message]
    public let createdAt: Double
    public var updatedAt: Double
    public var pinned: Bool
    public var archived: Bool

    public var id: String { sessionId }

    public init(
        sessionId: String,
        title: String,
        workspace: String,
        model: String,
        messages: [Message] = [],
        createdAt: Double,
        updatedAt: Double,
        pinned: Bool = false,
        archived: Bool = false
    ) {
        self.sessionId = sessionId
        self.title = title
        self.workspace = workspace
        self.model = model
        self.messages = messages
        self.createdAt = createdAt
        self.updatedAt = updatedAt
        self.pinned = pinned
        self.archived = archived
    }

    private enum CodingKeys: String, CodingKey {
        case sessionId = "session_id"
        case title
        case workspace
        case model
        case messages
        case pinned
        case archived
        case createdAt = "created_at"
        case updatedAt = "updated_at"
    }

    public init(from decoder: Decoder) throws {
        let container = try decoder.container(keyedBy: CodingKeys.self)
        self.sessionId = try container.decode(String.self, forKey: .sessionId)
        self.title = try container.decodeIfPresent(String.self, forKey: .title) ?? ""
        self.workspace = try container.decodeIfPresent(String.self, forKey: .workspace) ?? ""
        self.model = try container.decodeIfPresent(String.self, forKey: .model) ?? ""
        self.messages = try container.decodeIfPresent([Message].self, forKey: .messages) ?? []
        self.createdAt = try container.decodeIfPresent(Double.self, forKey: .createdAt) ?? 0
        self.updatedAt = try container.decodeIfPresent(Double.self, forKey: .updatedAt) ?? 0
        self.pinned = try container.decodeIfPresent(Bool.self, forKey: .pinned) ?? false
        self.archived = try container.decodeIfPresent(Bool.self, forKey: .archived) ?? false
    }
}

public struct SessionListItem: Codable, Identifiable, Hashable, Sendable {
    public let sessionId: String
    public var title: String
    public var model: String
    public var workspace: String
    public var updatedAt: Double
    public var pinned: Bool
    public var archived: Bool

    public var id: String { sessionId }

    public init(
        sessionId: String,
        title: String,
        model: String,
        workspace: String,
        updatedAt: Double,
        pinned: Bool = false,
        archived: Bool = false
    ) {
        self.sessionId = sessionId
        self.title = title
        self.model = model
        self.workspace = workspace
        self.updatedAt = updatedAt
        self.pinned = pinned
        self.archived = archived
    }

    private enum CodingKeys: String, CodingKey {
        case sessionId = "session_id"
        case title
        case model
        case workspace
        case pinned
        case archived
        case updatedAt = "updated_at"
    }

    public init(from decoder: Decoder) throws {
        let container = try decoder.container(keyedBy: CodingKeys.self)
        self.sessionId = try container.decode(String.self, forKey: .sessionId)
        self.title = try container.decodeIfPresent(String.self, forKey: .title) ?? ""
        self.model = try container.decodeIfPresent(String.self, forKey: .model) ?? ""
        self.workspace = try container.decodeIfPresent(String.self, forKey: .workspace) ?? ""
        self.updatedAt = try container.decodeIfPresent(Double.self, forKey: .updatedAt) ?? 0
        self.pinned = try container.decodeIfPresent(Bool.self, forKey: .pinned) ?? false
        self.archived = try container.decodeIfPresent(Bool.self, forKey: .archived) ?? false
    }
}
