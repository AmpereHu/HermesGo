import Foundation

public enum Endpoint {
    case health
    case authLogin
    case sessions
    case session(id: String)
    case sessionNew
    case sessionUpdate
    case sessionRename
    case sessionDelete
    case chatStart
    case chatStream(streamId: String)
    case chatStreamStatus(streamId: String)
    case chatCancel
    case approvalPending(sessionId: String?)
    case approvalRespond

    public var path: String {
        switch self {
        case .health:
            return "/health"
        case .authLogin:
            return "/api/auth/login"
        case .sessions:
            return "/api/sessions"
        case .session(let id):
            return "/api/session?session_id=\(Self.encode(id))"
        case .sessionNew:
            return "/api/session/new"
        case .sessionUpdate:
            return "/api/session/update"
        case .sessionRename:
            return "/api/session/rename"
        case .sessionDelete:
            return "/api/session/delete"
        case .chatStart:
            return "/api/chat/start"
        case .chatStream(let streamId):
            return "/api/chat/stream?stream_id=\(Self.encode(streamId))"
        case .chatStreamStatus(let streamId):
            return "/api/chat/stream/status?stream_id=\(Self.encode(streamId))"
        case .chatCancel:
            return "/api/chat/cancel"
        case .approvalPending(let sessionId):
            if let sessionId {
                return "/api/approval/pending?session_id=\(Self.encode(sessionId))"
            }
            return "/api/approval/pending"
        case .approvalRespond:
            return "/api/approval/respond"
        }
    }

    public var method: String {
        switch self {
        case .health,
             .sessions,
             .session,
             .chatStream,
             .chatStreamStatus,
             .approvalPending:
            return "GET"
        case .authLogin,
             .sessionNew,
             .sessionUpdate,
             .sessionRename,
             .sessionDelete,
             .chatStart,
             .chatCancel,
             .approvalRespond:
            return "POST"
        }
    }

    private static func encode(_ value: String) -> String {
        value.addingPercentEncoding(withAllowedCharacters: .urlQueryAllowed) ?? value
    }
}
