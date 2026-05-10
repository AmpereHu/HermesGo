import Foundation
import Observation

@Observable
@MainActor
public final class AppState {
    public enum Screen: Equatable {
        case setup
        case main
    }

    public var screen: Screen
    public var activeSessionId: String?
    public var apiClient: APIClientProtocol?

    @ObservationIgnored private let preferences: Preferences
    @ObservationIgnored private let secrets: SecretStoring
    @ObservationIgnored private var chatViewModels: [String: ChatViewModel] = [:]

    public init(
        preferences: Preferences = .shared,
        secrets: SecretStoring = KeychainStore.shared
    ) {
        self.preferences = preferences
        self.secrets = secrets
        self.screen = .setup
        self.apiClient = nil
        self.activeSessionId = preferences.lastSessionId
    }

    /// RULE-6: Boot 流程不自動建立 session。
    /// - 如果 Keychain + Preferences 有完整連線資訊：建立 APIClient、進入 main 畫面、用 lastSessionId（若有）
    /// - 否則：留在 setup
    public func boot() {
        guard let serverURL = preferences.serverURL,
              let password = secrets.load(.serverPassword), !password.isEmpty else {
            screen = .setup
            return
        }
        let client = APIClient(configuration: .init(baseURL: serverURL))
        // Re-login best-effort; SSE/HTTP will surface a 401 if it failed.
        Task {
            try? await client.login(password: password)
        }
        self.apiClient = client
        self.screen = .main
        // RULE-6: do NOT auto-create a session here. Active session stays nil
        // until the user picks one or taps +.
    }

    public func handleSetupCompleted(_ client: APIClientProtocol) {
        self.apiClient = client
        self.screen = .main
        self.activeSessionId = nil // user picks one via list, RULE-6.
    }

    public func signOut() {
        chatViewModels.values.forEach { $0.teardown() }
        chatViewModels.removeAll()
        apiClient = nil
        activeSessionId = nil
        screen = .setup
    }

    public func chatViewModel(for sessionId: String) -> ChatViewModel? {
        guard let api = apiClient else { return nil }
        if let existing = chatViewModels[sessionId] { return existing }
        let new = ChatViewModel(sessionId: sessionId, api: api, preferences: preferences)
        chatViewModels[sessionId] = new
        return new
    }

    public func discardChatViewModel(for sessionId: String) {
        chatViewModels[sessionId]?.teardown()
        chatViewModels.removeValue(forKey: sessionId)
    }

    public func persistActiveSession() {
        preferences.lastSessionId = activeSessionId
    }
}
