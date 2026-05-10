import Foundation
import Observation

@Observable
@MainActor
public final class SetupViewModel {
    public enum TestStatus: Equatable {
        case idle
        case testing
        case success(sessions: Int, version: String?)
        case failure(String)
    }

    public var serverURLText: String
    public var passwordText: String
    public var testStatus: TestStatus = .idle
    public var isSaving: Bool = false

    public var errorMessage: String?

    private let preferences: Preferences
    private let secrets: SecretStoring
    private let clientFactory: (URL) -> APIClientProtocol
    private let onCompleted: (APIClientProtocol) -> Void

    public init(
        preferences: Preferences = .shared,
        secrets: SecretStoring = KeychainStore.shared,
        clientFactory: @escaping (URL) -> APIClientProtocol = { url in
            APIClient(configuration: .init(baseURL: url))
        },
        onCompleted: @escaping (APIClientProtocol) -> Void
    ) {
        self.preferences = preferences
        self.secrets = secrets
        self.clientFactory = clientFactory
        self.onCompleted = onCompleted
        self.serverURLText = preferences.serverURL?.absoluteString ?? ""
        self.passwordText = secrets.load(.serverPassword) ?? ""
    }

    public var canSubmit: Bool {
        guard !serverURLText.trimmingCharacters(in: .whitespaces).isEmpty,
              !passwordText.isEmpty,
              normalizedURL() != nil else {
            return false
        }
        return true
    }

    public func testConnection() async {
        guard let url = normalizedURL() else {
            testStatus = .failure("URL 格式錯誤")
            return
        }
        testStatus = .testing
        let client = clientFactory(url)
        do {
            try await client.login(password: passwordText)
            let health = try await client.health()
            testStatus = .success(sessions: health.sessions ?? 0, version: health.version)
        } catch let error as APIError {
            testStatus = .failure(error.errorDescription ?? "連線失敗")
        } catch {
            testStatus = .failure(error.localizedDescription)
        }
    }

    public func save() async {
        guard let url = normalizedURL() else {
            errorMessage = "URL 格式錯誤"
            return
        }
        isSaving = true
        defer { isSaving = false }

        let client = clientFactory(url)
        do {
            try await client.login(password: passwordText)
            // RULE-iOS-A: secrets only in Keychain.
            _ = secrets.save(passwordText, for: .serverPassword)
            preferences.serverURL = url
            errorMessage = nil
            onCompleted(client)
        } catch let error as APIError {
            errorMessage = error.errorDescription
        } catch {
            errorMessage = error.localizedDescription
        }
    }

    private func normalizedURL() -> URL? {
        var raw = serverURLText.trimmingCharacters(in: .whitespacesAndNewlines)
        guard !raw.isEmpty else { return nil }
        if !raw.contains("://") {
            raw = "http://" + raw
        }
        guard let url = URL(string: raw),
              let scheme = url.scheme,
              ["http", "https"].contains(scheme.lowercased()),
              url.host != nil else {
            return nil
        }
        return url
    }
}
