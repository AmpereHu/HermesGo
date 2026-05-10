@testable import HermesMobile
import XCTest

final class APIClientTests: XCTestCase {

    // MARK: - Endpoint paths

    func test_endpointPaths() {
        XCTAssertEqual(Endpoint.health.path, "/health")
        XCTAssertEqual(Endpoint.sessions.path, "/api/sessions")
        XCTAssertEqual(Endpoint.session(id: "abc").path, "/api/session?session_id=abc")
        XCTAssertEqual(Endpoint.sessionNew.path, "/api/session/new")
        XCTAssertEqual(Endpoint.sessionDelete.path, "/api/session/delete")
        XCTAssertEqual(Endpoint.chatStart.path, "/api/chat/start")
        XCTAssertEqual(Endpoint.chatStream(streamId: "s1").path, "/api/chat/stream?stream_id=s1")
        XCTAssertEqual(Endpoint.chatStreamStatus(streamId: "s1").path, "/api/chat/stream/status?stream_id=s1")
        XCTAssertEqual(Endpoint.approvalRespond.path, "/api/approval/respond")
        XCTAssertEqual(Endpoint.approvalPending(sessionId: nil).path, "/api/approval/pending")
        XCTAssertEqual(Endpoint.approvalPending(sessionId: "abc").path, "/api/approval/pending?session_id=abc")
    }

    func test_endpointMethods() {
        XCTAssertEqual(Endpoint.health.method, "GET")
        XCTAssertEqual(Endpoint.sessions.method, "GET")
        XCTAssertEqual(Endpoint.sessionNew.method, "POST")
        XCTAssertEqual(Endpoint.sessionDelete.method, "POST")
        XCTAssertEqual(Endpoint.chatStart.method, "POST")
        XCTAssertEqual(Endpoint.approvalRespond.method, "POST")
    }

    // MARK: - Decoding contracts

    func test_sessionDecodingWithSnakeCase() throws {
        let json = """
        {
          "session_id": "abc",
          "title": "hello",
          "workspace": "~/work",
          "model": "claude-opus-4",
          "messages": [],
          "created_at": 1000.0,
          "updated_at": 2000.0,
          "pinned": false,
          "archived": false
        }
        """.data(using: .utf8)!
        let session = try JSONDecoder().decode(Session.self, from: json)
        XCTAssertEqual(session.sessionId, "abc")
        XCTAssertEqual(session.workspace, "~/work")
        XCTAssertEqual(session.createdAt, 1000.0)
        XCTAssertEqual(session.updatedAt, 2000.0)
    }

    func test_messageDecodingPreservesId() throws {
        let json = """
        {
          "id": "m1",
          "role": "assistant",
          "content": "hi"
        }
        """.data(using: .utf8)!
        let message = try JSONDecoder().decode(Message.self, from: json)
        XCTAssertEqual(message.id, "m1")
        XCTAssertEqual(message.role, .assistant)
    }

    func test_approvalDecodesPatternKeysPlural() throws {
        let json = """
        {
          "command": "rm -rf",
          "pattern_keys": ["rm_rf", "destructive"]
        }
        """.data(using: .utf8)!
        let approval = try JSONDecoder().decode(Approval.self, from: json)
        XCTAssertEqual(approval.patternKeys, ["rm_rf", "destructive"])
    }

    func test_chatStartResponseDecoding() throws {
        let json = """
        {"stream_id": "s1", "session_id": "abc"}
        """.data(using: .utf8)!
        let response = try JSONDecoder().decode(ChatStartResponse.self, from: json)
        XCTAssertEqual(response.streamId, "s1")
        XCTAssertEqual(response.sessionId, "abc")
    }

    // MARK: - Validation

    func test_validateSuccess() throws {
        let url = URL(string: "http://example.com")!
        let response = HTTPURLResponse(url: url, statusCode: 200, httpVersion: nil, headerFields: nil)!
        XCTAssertNoThrow(try APIClient.validate(response: response, data: Data()))
    }

    func test_validateUnauthorized() {
        let url = URL(string: "http://example.com")!
        let response = HTTPURLResponse(url: url, statusCode: 401, httpVersion: nil, headerFields: nil)!
        XCTAssertThrowsError(try APIClient.validate(response: response, data: Data())) { error in
            guard let api = error as? APIError, case .unauthorized = api else {
                XCTFail("Expected unauthorized")
                return
            }
        }
    }

    func test_validateServerErrorExtractsDetail() {
        let url = URL(string: "http://example.com")!
        let response = HTTPURLResponse(url: url, statusCode: 500, httpVersion: nil, headerFields: nil)!
        let body = #"{"detail":"db down"}"#.data(using: .utf8)!
        XCTAssertThrowsError(try APIClient.validate(response: response, data: body)) { error in
            guard let api = error as? APIError,
                  case let .serverError(status, message) = api else {
                XCTFail("Expected serverError")
                return
            }
            XCTAssertEqual(status, 500)
            XCTAssertEqual(message, "db down")
        }
    }
}
