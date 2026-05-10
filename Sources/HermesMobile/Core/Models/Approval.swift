import Foundation

public struct Approval: Codable, Identifiable, Hashable, Sendable {
    public let id: String
    public let command: String
    public let description: String?
    public let patternKeys: [String]
    public let sessionId: String?

    public init(
        id: String = UUID().uuidString,
        command: String,
        description: String? = nil,
        patternKeys: [String],
        sessionId: String? = nil
    ) {
        self.id = id
        self.command = command
        self.description = description
        self.patternKeys = patternKeys
        self.sessionId = sessionId
    }

    private enum CodingKeys: String, CodingKey {
        case id
        case command
        case description
        case patternKeys = "pattern_keys"
        case sessionId = "session_id"
    }

    public init(from decoder: Decoder) throws {
        let container = try decoder.container(keyedBy: CodingKeys.self)
        self.id = try container.decodeIfPresent(String.self, forKey: .id) ?? UUID().uuidString
        self.command = try container.decodeIfPresent(String.self, forKey: .command) ?? ""
        self.description = try container.decodeIfPresent(String.self, forKey: .description)
        self.patternKeys = try container.decodeIfPresent([String].self, forKey: .patternKeys) ?? []
        self.sessionId = try container.decodeIfPresent(String.self, forKey: .sessionId)
    }
}

public enum ApprovalChoice: String, Codable, CaseIterable, Sendable {
    case allowOnce = "allow_once"
    case allowSession = "allow_session"
    case allowAlways = "allow_always"
    case deny

    public var displayName: String {
        switch self {
        case .allowOnce: return "允許這次"
        case .allowSession: return "本 Session 允許"
        case .allowAlways: return "永遠允許"
        case .deny: return "拒絕"
        }
    }

    public var isAllow: Bool { self != .deny }
}
