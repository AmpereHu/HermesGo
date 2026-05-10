import Foundation

public struct HealthResponse: Codable, Sendable {
    public let status: String
    public let sessions: Int?
    public let version: String?
}

public struct ChatStartResponse: Codable, Sendable {
    public let streamId: String
    public let sessionId: String?

    private enum CodingKeys: String, CodingKey {
        case streamId = "stream_id"
        case sessionId = "session_id"
    }
}

public struct StreamStatus: Codable, Sendable {
    public let streamId: String
    public let active: Bool
    public let finished: Bool?

    private enum CodingKeys: String, CodingKey {
        case streamId = "stream_id"
        case active
        case finished
    }
}

public struct AvailableModel: Codable, Hashable, Sendable {
    public let id: String
    public let label: String?

    public var displayName: String { label ?? id }
}

public protocol APIClientProtocol: AnyObject, Sendable {
    func health() async throws -> HealthResponse
    func login(password: String) async throws
    func listSessions() async throws -> [SessionListItem]
    func getSession(id: String) async throws -> Session
    func newSession(model: String?, workspace: String?) async throws -> Session
    func updateSession(id: String, model: String?, workspace: String?) async throws
    func renameSession(id: String, title: String) async throws
    func deleteSession(id: String) async throws
    func startChat(sessionId: String, message: String, model: String?, workspace: String?) async throws -> ChatStartResponse
    func streamChat(streamId: String) -> AsyncThrowingStream<SSEEvent, Error>
    func streamStatus(streamId: String) async throws -> StreamStatus
    func cancelChat(streamId: String) async throws
    func pendingApproval(sessionId: String?) async throws -> Approval?
    func respondApproval(sessionId: String, choice: ApprovalChoice) async throws
}

public final class APIClient: APIClientProtocol, @unchecked Sendable {
    public struct Configuration: Sendable {
        public var baseURL: URL
        public var defaultTimeout: TimeInterval
        public var streamTimeout: TimeInterval

        public init(
            baseURL: URL,
            defaultTimeout: TimeInterval = 15,
            streamTimeout: TimeInterval = .infinity
        ) {
            self.baseURL = baseURL
            self.defaultTimeout = defaultTimeout
            self.streamTimeout = streamTimeout
        }
    }

    private let configuration: Configuration
    private let session: URLSession
    private let sseClient: SSEClient
    private let decoder: JSONDecoder
    private let encoder: JSONEncoder

    public init(
        configuration: Configuration,
        session: URLSession = .makeShared()
    ) {
        self.configuration = configuration
        self.session = session
        self.sseClient = SSEClient(session: session)
        self.decoder = JSONDecoder()
        self.encoder = JSONEncoder()
    }

    public func health() async throws -> HealthResponse {
        try await request(.health)
    }

    public func login(password: String) async throws {
        struct Body: Encodable { let password: String }
        let _: EmptyResponse = try await request(.authLogin, body: Body(password: password))
    }

    public func listSessions() async throws -> [SessionListItem] {
        let response: SessionListResponse = try await request(.sessions)
        return response.sessions ?? []
    }

    public func getSession(id: String) async throws -> Session {
        let response: SessionDetailResponse = try await request(.session(id: id))
        if let session = response.session {
            return session
        }
        throw APIError.sessionNotFound
    }

    public func newSession(model: String?, workspace: String?) async throws -> Session {
        struct Body: Encodable {
            let model: String?
            let workspace: String?
        }
        let response: SessionDetailResponse = try await request(.sessionNew, body: Body(model: model, workspace: workspace))
        guard let session = response.session else {
            throw APIError.unknown("server returned no session for /api/session/new")
        }
        return session
    }

    public func updateSession(id: String, model: String?, workspace: String?) async throws {
        struct Body: Encodable {
            let sessionId: String
            let model: String?
            let workspace: String?
            enum CodingKeys: String, CodingKey {
                case sessionId = "session_id"
                case model
                case workspace
            }
        }
        let _: EmptyResponse = try await request(.sessionUpdate, body: Body(sessionId: id, model: model, workspace: workspace))
    }

    public func renameSession(id: String, title: String) async throws {
        struct Body: Encodable {
            let sessionId: String
            let title: String
            enum CodingKeys: String, CodingKey {
                case sessionId = "session_id"
                case title
            }
        }
        let _: EmptyResponse = try await request(.sessionRename, body: Body(sessionId: id, title: title))
    }

    public func deleteSession(id: String) async throws {
        struct Body: Encodable {
            let sessionId: String
            enum CodingKeys: String, CodingKey {
                case sessionId = "session_id"
            }
        }
        let _: EmptyResponse = try await request(.sessionDelete, body: Body(sessionId: id))
    }

    public func startChat(sessionId: String, message: String, model: String?, workspace: String?) async throws -> ChatStartResponse {
        struct Body: Encodable {
            let sessionId: String
            let message: String
            let model: String?
            let workspace: String?
            enum CodingKeys: String, CodingKey {
                case sessionId = "session_id"
                case message
                case model
                case workspace
            }
        }
        return try await request(.chatStart, body: Body(sessionId: sessionId, message: message, model: model, workspace: workspace))
    }

    public func streamChat(streamId: String) -> AsyncThrowingStream<SSEEvent, Error> {
        do {
            let request = try makeRequest(for: .chatStream(streamId: streamId), timeout: configuration.streamTimeout)
            return sseClient.stream(request: request)
        } catch {
            return AsyncThrowingStream { continuation in
                continuation.finish(throwing: error)
            }
        }
    }

    public func streamStatus(streamId: String) async throws -> StreamStatus {
        try await request(.chatStreamStatus(streamId: streamId))
    }

    public func cancelChat(streamId: String) async throws {
        struct Body: Encodable {
            let streamId: String
            enum CodingKeys: String, CodingKey {
                case streamId = "stream_id"
            }
        }
        let _: EmptyResponse = try await request(.chatCancel, body: Body(streamId: streamId))
    }

    public func pendingApproval(sessionId: String?) async throws -> Approval? {
        struct Response: Decodable {
            let approval: Approval?
            let pending: Approval?
        }
        let response: Response = try await request(.approvalPending(sessionId: sessionId))
        return response.approval ?? response.pending
    }

    public func respondApproval(sessionId: String, choice: ApprovalChoice) async throws {
        struct Body: Encodable {
            let sessionId: String
            let choice: String
            enum CodingKeys: String, CodingKey {
                case sessionId = "session_id"
                case choice
            }
        }
        let _: EmptyResponse = try await request(.approvalRespond, body: Body(sessionId: sessionId, choice: choice.rawValue))
    }

    // MARK: - Internals

    private struct EmptyResponse: Decodable {}

    private struct SessionListResponse: Decodable {
        let sessions: [SessionListItem]?
    }

    private struct SessionDetailResponse: Decodable {
        let session: Session?
    }

    private func request<Response: Decodable>(_ endpoint: Endpoint) async throws -> Response {
        let request = try makeRequest(for: endpoint)
        return try await perform(request)
    }

    private func request<Body: Encodable, Response: Decodable>(_ endpoint: Endpoint, body: Body) async throws -> Response {
        var request = try makeRequest(for: endpoint)
        request.httpBody = try encoder.encode(body)
        request.setValue("application/json", forHTTPHeaderField: "Content-Type")
        return try await perform(request)
    }

    private func makeRequest(for endpoint: Endpoint, timeout: TimeInterval? = nil) throws -> URLRequest {
        guard let url = URL(string: endpoint.path, relativeTo: configuration.baseURL)?.absoluteURL else {
            throw APIError.invalidURL(endpoint.path)
        }
        var request = URLRequest(url: url)
        request.httpMethod = endpoint.method
        request.timeoutInterval = timeout ?? configuration.defaultTimeout
        request.setValue("application/json", forHTTPHeaderField: "Accept")
        return request
    }

    private func perform<Response: Decodable>(_ request: URLRequest) async throws -> Response {
        let data: Data
        let response: URLResponse
        do {
            (data, response) = try await session.data(for: request)
        } catch let urlError as URLError {
            throw APIError.networkFailure(urlError)
        } catch {
            throw APIError.unknown(error.localizedDescription)
        }
        try Self.validate(response: response, data: data)
        if Response.self == EmptyResponse.self {
            return EmptyResponse() as! Response
        }
        if data.isEmpty {
            throw APIError.decoding("empty response body")
        }
        do {
            return try decoder.decode(Response.self, from: data)
        } catch let decodingError as DecodingError {
            throw APIError.decoding(String(describing: decodingError))
        } catch {
            throw APIError.decoding(error.localizedDescription)
        }
    }

    static func validate(response: URLResponse, data: Data) throws {
        guard let http = response as? HTTPURLResponse else {
            throw APIError.unknown("non-HTTP response")
        }
        switch http.statusCode {
        case 200...299:
            return
        case 401:
            throw APIError.unauthorized
        case 403:
            throw APIError.forbidden
        case 404:
            throw APIError.sessionNotFound
        default:
            let message = extractServerMessage(from: data)
            throw APIError.serverError(status: http.statusCode, message: message)
        }
    }

    static func extractServerMessage(from data: Data) -> String? {
        guard !data.isEmpty,
              let json = try? JSONSerialization.jsonObject(with: data) as? [String: Any] else {
            return nil
        }
        if let detail = json["detail"] as? String { return detail }
        if let error = json["error"] as? String { return error }
        if let message = json["message"] as? String { return message }
        return nil
    }
}

extension URLSession {
    public static func makeShared() -> URLSession {
        let configuration = URLSessionConfiguration.default
        configuration.httpCookieAcceptPolicy = .always
        configuration.httpShouldSetCookies = true
        configuration.httpCookieStorage = HTTPCookieStorage.shared
        configuration.requestCachePolicy = .reloadIgnoringLocalCacheData
        configuration.waitsForConnectivity = true
        configuration.timeoutIntervalForRequest = 30
        configuration.timeoutIntervalForResource = 60 * 60
        return URLSession(configuration: configuration)
    }
}
