@testable import HermesMobile
import XCTest

@MainActor
final class SessionListViewModelTests: XCTestCase {

    private func makeAppState() -> AppState {
        let suite = "SessionListVMTests-\(UUID().uuidString)"
        let prefs = Preferences(defaults: UserDefaults(suiteName: suite)!)
        return AppState(preferences: prefs, secrets: InMemorySecretStore())
    }

    func test_loadSortsByUpdatedAtDesc() async {
        let api = MockAPIClient()
        api.listSessionsHandler = {
            [
                SessionListItem(sessionId: "a", title: "old", model: "", workspace: "", updatedAt: 100),
                SessionListItem(sessionId: "b", title: "new", model: "", workspace: "", updatedAt: 200),
                SessionListItem(sessionId: "c", title: "mid", model: "", workspace: "", updatedAt: 150)
            ]
        }
        let vm = SessionListViewModel(api: api, appState: makeAppState())
        await vm.load()
        XCTAssertEqual(vm.sessions.map(\.sessionId), ["b", "c", "a"])
    }

    /// RULE-1: deleting active session must NOT auto-create a new one.
    func test_deleteActiveSessionSwitchesToLatestNeverAutoCreates() async {
        let appState = makeAppState()
        let api = MockAPIClient()
        var nextList: [SessionListItem] = [
            SessionListItem(sessionId: "active", title: "A", model: "", workspace: "", updatedAt: 200),
            SessionListItem(sessionId: "other", title: "B", model: "", workspace: "", updatedAt: 100)
        ]
        api.listSessionsHandler = { nextList }
        api.deleteSessionHandler = { id in
            nextList.removeAll { $0.sessionId == id }
        }

        let vm = SessionListViewModel(api: api, appState: appState)
        await vm.load()
        appState.activeSessionId = "active"

        await vm.delete("active")

        XCTAssertEqual(api.deleteCalls, ["active"])
        XCTAssertEqual(api.newSessionCalls, 0, "RULE-1: must not auto-create after delete")
        XCTAssertEqual(appState.activeSessionId, "other")
    }

    /// RULE-1: when deleting the LAST session, activeSessionId becomes nil — never new session.
    func test_deleteLastSessionResultsInNilActiveAndNoNewSession() async {
        let appState = makeAppState()
        let api = MockAPIClient()
        var nextList: [SessionListItem] = [
            SessionListItem(sessionId: "only", title: "A", model: "", workspace: "", updatedAt: 200)
        ]
        api.listSessionsHandler = { nextList }
        api.deleteSessionHandler = { _ in nextList.removeAll() }

        let vm = SessionListViewModel(api: api, appState: appState)
        await vm.load()
        appState.activeSessionId = "only"

        await vm.delete("only")

        XCTAssertEqual(api.newSessionCalls, 0, "RULE-1: never auto-create")
        XCTAssertNil(appState.activeSessionId)
        XCTAssertTrue(vm.sessions.isEmpty)
    }

    /// RULE-1: deleting a non-active session must not change activeSessionId.
    func test_deleteNonActiveSessionKeepsActive() async {
        let appState = makeAppState()
        let api = MockAPIClient()
        var nextList: [SessionListItem] = [
            SessionListItem(sessionId: "active", title: "A", model: "", workspace: "", updatedAt: 200),
            SessionListItem(sessionId: "other", title: "B", model: "", workspace: "", updatedAt: 100)
        ]
        api.listSessionsHandler = { nextList }
        api.deleteSessionHandler = { id in nextList.removeAll { $0.sessionId == id } }

        let vm = SessionListViewModel(api: api, appState: appState)
        await vm.load()
        appState.activeSessionId = "active"

        await vm.delete("other")

        XCTAssertEqual(appState.activeSessionId, "active")
        XCTAssertEqual(api.newSessionCalls, 0)
    }
}
