@testable import HermesMobile
import Foundation

final class MockAPIClient: APIClientProtocol, @unchecked Sendable {
    var healthHandler: () async throws -> HealthResponse = {
        HealthResponse(status: "ok", sessions: 0, version: "test")
    }
    var loginHandler: (String) async throws -> Void = { _ in }
    var listSessionsHandler: () async throws -> [SessionListItem] = { [] }
    var getSessionHandler: (String) async throws -> Session = { id in
        Session(sessionId: id, title: "Mock", workspace: "", model: "", messages: [], createdAt: 0, updatedAt: 0)
    }
    var newSessionHandler: (String?, String?) async throws -> Session = { _, _ in
        Session(sessionId: "new", title: "New", workspace: "", model: "", messages: [], createdAt: 0, updatedAt: 0)
    }
    var updateSessionHandler: (String, String?, String?) async throws -> Void = { _, _, _ in }
    var renameSessionHandler: (String, String) async throws -> Void = { _, _ in }
    var deleteSessionHandler: (String) async throws -> Void = { _ in }
    var startChatHandler: (String, String, String?, String?) async throws -> ChatStartResponse = { sid, _, _, _ in
        ChatStartResponse(streamId: "stream-\(sid)", sessionId: sid)
    }
    var streamChatHandler: (String) -> AsyncThrowingStream<SSEEvent, Error> = { _ in
        AsyncThrowingStream { continuation in continuation.finish() }
    }
    var streamStatusHandler: (String) async throws -> StreamStatus = { sid in
        StreamStatus(streamId: sid, active: false, finished: true)
    }
    var cancelChatHandler: (String) async throws -> Void = { _ in }
    var pendingApprovalHandler: (String?) async throws -> Approval? = { _ in nil }
    var respondApprovalHandler: (String, ApprovalChoice) async throws -> Void = { _, _ in }

    private(set) var deleteCalls: [String] = []
    private(set) var newSessionCalls: Int = 0
    private(set) var startChatCalls: [(String, String)] = []
    private(set) var respondApprovalCalls: [(String, ApprovalChoice)] = []

    func health() async throws -> HealthResponse { try await healthHandler() }
    func login(password: String) async throws { try await loginHandler(password) }
    func listSessions() async throws -> [SessionListItem] { try await listSessionsHandler() }
    func getSession(id: String) async throws -> Session { try await getSessionHandler(id) }
    func newSession(model: String?, workspace: String?) async throws -> Session {
        newSessionCalls += 1
        return try await newSessionHandler(model, workspace)
    }
    func updateSession(id: String, model: String?, workspace: String?) async throws {
        try await updateSessionHandler(id, model, workspace)
    }
    func renameSession(id: String, title: String) async throws {
        try await renameSessionHandler(id, title)
    }
    func deleteSession(id: String) async throws {
        deleteCalls.append(id)
        try await deleteSessionHandler(id)
    }
    func startChat(sessionId: String, message: String, model: String?, workspace: String?) async throws -> ChatStartResponse {
        startChatCalls.append((sessionId, message))
        return try await startChatHandler(sessionId, message, model, workspace)
    }
    func streamChat(streamId: String) -> AsyncThrowingStream<SSEEvent, Error> {
        streamChatHandler(streamId)
    }
    func streamStatus(streamId: String) async throws -> StreamStatus {
        try await streamStatusHandler(streamId)
    }
    func cancelChat(streamId: String) async throws {
        try await cancelChatHandler(streamId)
    }
    func pendingApproval(sessionId: String?) async throws -> Approval? {
        try await pendingApprovalHandler(sessionId)
    }
    func respondApproval(sessionId: String, choice: ApprovalChoice) async throws {
        respondApprovalCalls.append((sessionId, choice))
        try await respondApprovalHandler(sessionId, choice)
    }
}
