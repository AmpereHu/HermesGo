import Foundation
import Observation

@Observable
@MainActor
public final class SettingsViewModel {
    public var serverURLText: String
    public var passwordText: String
    public var statusMessage: String?

    private let preferences: Preferences
    private let secrets: SecretStoring
    private let onSignOut: () -> Void

    public init(
        preferences: Preferences = .shared,
        secrets: SecretStoring = KeychainStore.shared,
        onSignOut: @escaping () -> Void
    ) {
        self.preferences = preferences
        self.secrets = secrets
        self.onSignOut = onSignOut
        self.serverURLText = preferences.serverURL?.absoluteString ?? ""
        self.passwordText = ""
    }

    public var serverDisplayURL: String {
        preferences.serverURL?.absoluteString ?? "(未設定)"
    }

    public var hasStoredPassword: Bool {
        secrets.load(.serverPassword) != nil
    }

    public func signOut() {
        secrets.delete(.serverPassword)
        secrets.delete(.authCookie)
        preferences.reset()
        onSignOut()
    }
}
