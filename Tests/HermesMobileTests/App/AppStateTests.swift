@testable import HermesMobile
import XCTest

@MainActor
final class AppStateTests: XCTestCase {

    /// RULE-6: Boot must NOT auto-create a session.
    func test_bootWithoutCredentialsRemainsOnSetup() {
        let suite = "AppStateTests-\(UUID().uuidString)"
        let prefs = Preferences(defaults: UserDefaults(suiteName: suite)!)
        let appState = AppState(preferences: prefs, secrets: InMemorySecretStore())
        appState.boot()
        XCTAssertEqual(appState.screen, .setup)
        XCTAssertNil(appState.apiClient)
    }

    func test_bootWithCredentialsEntersMainWithoutAutoCreatingSession() {
        let suite = "AppStateTests-\(UUID().uuidString)"
        let prefs = Preferences(defaults: UserDefaults(suiteName: suite)!)
        prefs.serverURL = URL(string: "http://100.0.0.1:8787")
        let secrets = InMemorySecretStore()
        secrets.save("password", for: .serverPassword)

        let appState = AppState(preferences: prefs, secrets: secrets)
        appState.boot()

        XCTAssertEqual(appState.screen, .main)
        XCTAssertNotNil(appState.apiClient)
        // RULE-6: boot reads lastSessionId only; never invents one.
        // Without a stored lastSessionId, activeSessionId must remain nil.
        XCTAssertNil(appState.activeSessionId)
    }

    func test_bootRestoresLastSessionIdIfAvailable() {
        let suite = "AppStateTests-\(UUID().uuidString)"
        let prefs = Preferences(defaults: UserDefaults(suiteName: suite)!)
        prefs.serverURL = URL(string: "http://100.0.0.1:8787")
        prefs.lastSessionId = "abc"
        let secrets = InMemorySecretStore()
        secrets.save("password", for: .serverPassword)

        let appState = AppState(preferences: prefs, secrets: secrets)
        appState.boot()

        XCTAssertEqual(appState.activeSessionId, "abc")
    }

    func test_signOutResetsToSetupScreen() {
        let suite = "AppStateTests-\(UUID().uuidString)"
        let prefs = Preferences(defaults: UserDefaults(suiteName: suite)!)
        prefs.serverURL = URL(string: "http://100.0.0.1:8787")
        let secrets = InMemorySecretStore()
        secrets.save("password", for: .serverPassword)
        let appState = AppState(preferences: prefs, secrets: secrets)
        appState.boot()

        appState.signOut()

        XCTAssertEqual(appState.screen, .setup)
        XCTAssertNil(appState.apiClient)
        XCTAssertNil(appState.activeSessionId)
    }
}
