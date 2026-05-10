import Foundation

public enum SSEEvent: Sendable, Equatable {
    case token(String)
    case tool(name: String, preview: String)
    case approval(Approval)
    case done(Session)
    case error(message: String, trace: String?)
    case unknown(name: String, raw: String)
}

struct SSETokenPayload: Decodable {
    let text: String
}

struct SSEToolPayload: Decodable {
    let name: String
    let preview: String?
}

struct SSEDonePayload: Decodable {
    let session: Session?
}

struct SSEErrorPayload: Decodable {
    let message: String
    let trace: String?
}
