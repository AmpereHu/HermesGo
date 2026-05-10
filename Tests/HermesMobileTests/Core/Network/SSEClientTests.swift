@testable import HermesMobile
import XCTest

final class SSEClientTests: XCTestCase {
    private var client: SSEClient!

    override func setUp() {
        super.setUp()
        client = SSEClient()
    }

    func test_parseTokenEvent() {
        let event = client.parseEvent(name: "token", data: #"{"text":"Hello"}"#)
        if case .token(let text) = event {
            XCTAssertEqual(text, "Hello")
        } else {
            XCTFail("Expected token event, got \(String(describing: event))")
        }
    }

    func test_parseToolEvent() {
        let event = client.parseEvent(name: "tool", data: #"{"name":"terminal","preview":"ls -la"}"#)
        if case let .tool(name, preview) = event {
            XCTAssertEqual(name, "terminal")
            XCTAssertEqual(preview, "ls -la")
        } else {
            XCTFail("Expected tool event, got \(String(describing: event))")
        }
    }

    func test_parseApprovalEventUsesPatternKeysPlural() {
        let json = #"""
        {"command":"rm -rf /tmp/x","description":"dangerous","pattern_keys":["rm_rf","sudo"]}
        """#
        let event = client.parseEvent(name: "approval", data: json)
        if case .approval(let approval) = event {
            // RULE-9: must read pattern_keys (plural)
            XCTAssertEqual(approval.patternKeys, ["rm_rf", "sudo"])
            XCTAssertEqual(approval.command, "rm -rf /tmp/x")
        } else {
            XCTFail("Expected approval event, got \(String(describing: event))")
        }
    }

    func test_parseDoneEventWithSessionWrapper() {
        let json = """
        {"session": {"session_id":"abc","title":"hi","workspace":"~","model":"m","messages":[],"created_at":0,"updated_at":0,"pinned":false,"archived":false}}
        """
        let event = client.parseEvent(name: "done", data: json)
        if case .done(let session) = event {
            XCTAssertEqual(session.sessionId, "abc")
        } else {
            XCTFail("Expected done event, got \(String(describing: event))")
        }
    }

    func test_parseErrorEvent() {
        let event = client.parseEvent(name: "error", data: #"{"message":"boom","trace":"line 1"}"#)
        if case let .error(message, trace) = event {
            XCTAssertEqual(message, "boom")
            XCTAssertEqual(trace, "line 1")
        } else {
            XCTFail("Expected error event, got \(String(describing: event))")
        }
    }

    func test_parseUnknownEventReturnsUnknown() {
        let event = client.parseEvent(name: "weird", data: #"{"x":1}"#)
        if case .unknown(let name, _) = event {
            XCTAssertEqual(name, "weird")
        } else {
            XCTFail("Expected unknown event, got \(String(describing: event))")
        }
    }

    func test_parseEventWithMissingNameReturnsNil() {
        XCTAssertNil(client.parseEvent(name: nil, data: "anything"))
    }
}
