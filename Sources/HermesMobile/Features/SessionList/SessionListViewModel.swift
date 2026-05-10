import Foundation
import Observation

@Observable
@MainActor
public final class SessionListViewModel {
    public private(set) var sessions: [SessionListItem] = []
    public private(set) var isLoading: Bool = false
    public var errorMessage: String?
    public var pendingNewSession: Bool = false

    private let api: APIClientProtocol
    private let appState: AppState

    public init(api: APIClientProtocol, appState: AppState) {
        self.api = api
        self.appState = appState
    }

    public func load() async {
        isLoading = true
        defer { isLoading = false }
        do {
            let items = try await api.listSessions()
            self.sessions = items.sorted { $0.updatedAt > $1.updatedAt }
            errorMessage = nil
        } catch let error as APIError {
            errorMessage = error.errorDescription
        } catch {
            errorMessage = error.localizedDescription
        }
    }

    public func refresh() async {
        await load()
    }

    public func createNew() async -> String? {
        pendingNewSession = true
        defer { pendingNewSession = false }
        do {
            let session = try await api.newSession(model: nil, workspace: nil)
            await load()
            appState.activeSessionId = session.sessionId
            return session.sessionId
        } catch let error as APIError {
            errorMessage = error.errorDescription
            return nil
        } catch {
            errorMessage = error.localizedDescription
            return nil
        }
    }

    /// RULE-1: 刪除 session 後絕不自動建立新的。
    /// 若刪掉的是 active session，就切到剩下最新的；都沒了就顯示空狀態（activeSessionId = nil）。
    public func delete(_ sessionId: String) async {
        let wasActive = appState.activeSessionId == sessionId
        do {
            try await api.deleteSession(id: sessionId)
        } catch let error as APIError {
            errorMessage = error.errorDescription
            return
        } catch {
            errorMessage = error.localizedDescription
            return
        }

        await load()

        if wasActive {
            // RULE-1 enforcement: switch to next-most-recent or clear, never auto-create.
            appState.activeSessionId = sessions.first?.sessionId
        }
    }

    public func rename(_ sessionId: String, to title: String) async {
        let trimmed = title.trimmingCharacters(in: .whitespacesAndNewlines)
        guard !trimmed.isEmpty else { return }
        do {
            try await api.renameSession(id: sessionId, title: trimmed)
            await load()
        } catch let error as APIError {
            errorMessage = error.errorDescription
        } catch {
            errorMessage = error.localizedDescription
        }
    }

    public func select(_ sessionId: String) {
        appState.activeSessionId = sessionId
    }
}
