@testable import HermesMobile
import XCTest

@MainActor
final class ChatViewModelTests: XCTestCase {

    private var preferences: Preferences!
    private var defaults: UserDefaults!
    private var suiteName: String!

    override func setUp() {
        super.setUp()
        suiteName = "ChatVMTests-\(UUID().uuidString)"
        defaults = UserDefaults(suiteName: suiteName)!
        preferences = Preferences(defaults: defaults)
    }

    override func tearDown() {
        defaults.removePersistentDomain(forName: suiteName)
        preferences = nil
        defaults = nil
        suiteName = nil
        super.tearDown()
    }

    // MARK: - load

    func test_loadPopulatesMessages() async {
        let api = MockAPIClient()
        api.getSessionHandler = { id in
            Session(
                sessionId: id,
                title: "S",
                workspace: "",
                model: "claude",
                messages: [Message(id: "m1", role: .user, content: "hi")],
                createdAt: 0,
                updatedAt: 0
            )
        }
        let vm = ChatViewModel(sessionId: "s1", api: api, preferences: preferences)
        await vm.load()
        XCTAssertEqual(vm.messages.count, 1)
        XCTAssertEqual(vm.messages.first?.content, "hi")
    }

    // MARK: - send (RULE-5 happy path)

    func test_sendStartsStreamAndAppliesDoneSession() async {
        let api = MockAPIClient()
        api.startChatHandler = { _, _, _, _ in
            ChatStartResponse(streamId: "s1", sessionId: "session-1")
        }
        api.streamChatHandler = { _ in
            AsyncThrowingStream { continuation in
                continuation.yield(.token("Hel"))
                continuation.yield(.token("lo"))
                let session = Session(
                    sessionId: "session-1",
                    title: "S",
                    workspace: "",
                    model: "",
                    messages: [
                        Message(id: "u", role: .user, content: "Hi"),
                        Message(id: "a", role: .assistant, content: "Hello")
                    ],
                    createdAt: 0,
                    updatedAt: 0
                )
                continuation.yield(.done(session))
                continuation.finish()
            }
        }
        let vm = ChatViewModel(sessionId: "session-1", api: api, preferences: preferences)
        await vm.send("Hi")

        // Wait for the streaming task to complete.
        try? await Task.sleep(nanoseconds: 200_000_000)

        XCTAssertFalse(vm.isStreaming)
        XCTAssertEqual(vm.streamingMessage, "")
        XCTAssertEqual(vm.messages.map(\.content), ["Hi", "Hello"])
    }

    // MARK: - approval

    func test_approvalEventSetsPendingApprovalUsingPatternKeys() async {
        let api = MockAPIClient()
        api.startChatHandler = { _, _, _, _ in
            ChatStartResponse(streamId: "s1", sessionId: "session-1")
        }
        api.streamChatHandler = { _ in
            AsyncThrowingStream { continuation in
                let approval = Approval(
                    command: "rm -rf /tmp/x",
                    description: "danger",
                    patternKeys: ["rm_rf"],
                    sessionId: "session-1"
                )
                continuation.yield(.approval(approval))
                continuation.finish()
            }
        }
        let vm = ChatViewModel(sessionId: "session-1", api: api, preferences: preferences)
        await vm.send("nuke")
        try? await Task.sleep(nanoseconds: 200_000_000)

        XCTAssertNotNil(vm.pendingApproval)
        // RULE-9: pattern_keys plural.
        XCTAssertEqual(vm.pendingApproval?.patternKeys, ["rm_rf"])
    }

    func test_respondApprovalCallsAPIAndClearsState() async {
        let api = MockAPIClient()
        let vm = ChatViewModel(sessionId: "s", api: api, preferences: preferences)
        // Simulate an existing pending approval by injecting through send.
        api.startChatHandler = { _, _, _, _ in ChatStartResponse(streamId: "s1", sessionId: "s") }
        api.streamChatHandler = { _ in
            AsyncThrowingStream { c in
                c.yield(.approval(Approval(command: "rm", patternKeys: ["rm_rf"])))
                c.finish()
            }
        }
        await vm.send("hi")
        try? await Task.sleep(nanoseconds: 200_000_000)
        XCTAssertNotNil(vm.pendingApproval)

        await vm.respondApproval(.allowOnce)

        XCTAssertNil(vm.pendingApproval)
        XCTAssertEqual(api.respondApprovalCalls.count, 1)
        XCTAssertEqual(api.respondApprovalCalls.first?.1, .allowOnce)
    }

    // MARK: - error handling

    func test_streamErrorEventSetsErrorMessage() async {
        let api = MockAPIClient()
        api.startChatHandler = { _, _, _, _ in
            ChatStartResponse(streamId: "s1", sessionId: "s")
        }
        api.streamChatHandler = { _ in
            AsyncThrowingStream { c in
                c.yield(.error(message: "boom", trace: nil))
                c.finish()
            }
        }
        let vm = ChatViewModel(sessionId: "s", api: api, preferences: preferences)
        await vm.send("hello")
        try? await Task.sleep(nanoseconds: 200_000_000)

        XCTAssertEqual(vm.errorMessage, "boom")
        XCTAssertFalse(vm.isStreaming)
    }
}
