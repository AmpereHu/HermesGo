import Foundation

public struct Message: Codable, Identifiable, Hashable, Sendable {
    public enum Role: String, Codable, Sendable {
        case user
        case assistant
        case system
        case tool
    }

    public var id: String
    public var role: Role
    public var content: String
    public var attachments: [String]?
    public var createdAt: Double?

    public init(
        id: String = UUID().uuidString,
        role: Role,
        content: String,
        attachments: [String]? = nil,
        createdAt: Double? = nil
    ) {
        self.id = id
        self.role = role
        self.content = content
        self.attachments = attachments
        self.createdAt = createdAt
    }

    private enum CodingKeys: String, CodingKey {
        case id
        case role
        case content
        case attachments
        case createdAt = "created_at"
    }

    public init(from decoder: Decoder) throws {
        let container = try decoder.container(keyedBy: CodingKeys.self)
        let decodedId = try container.decodeIfPresent(String.self, forKey: .id)
        self.id = decodedId ?? UUID().uuidString
        self.role = try container.decode(Role.self, forKey: .role)
        self.content = try container.decodeIfPresent(String.self, forKey: .content) ?? ""
        self.attachments = try container.decodeIfPresent([String].self, forKey: .attachments)
        self.createdAt = try container.decodeIfPresent(Double.self, forKey: .createdAt)
    }

    public func encode(to encoder: Encoder) throws {
        var container = encoder.container(keyedBy: CodingKeys.self)
        try container.encode(id, forKey: .id)
        try container.encode(role, forKey: .role)
        try container.encode(content, forKey: .content)
        try container.encodeIfPresent(attachments, forKey: .attachments)
        try container.encodeIfPresent(createdAt, forKey: .createdAt)
    }
}
