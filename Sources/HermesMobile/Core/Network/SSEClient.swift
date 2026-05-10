import Foundation

public final class SSEClient: @unchecked Sendable {
    private let session: URLSession
    private let decoder: JSONDecoder

    public init(session: URLSession = .makeShared()) {
        self.session = session
        self.decoder = JSONDecoder()
    }

    public func stream(request: URLRequest) -> AsyncThrowingStream<SSEEvent, Error> {
        AsyncThrowingStream { continuation in
            let task = Task {
                do {
                    var sseRequest = request
                    sseRequest.setValue("text/event-stream", forHTTPHeaderField: "Accept")
                    sseRequest.setValue("no-cache", forHTTPHeaderField: "Cache-Control")
                    sseRequest.timeoutInterval = .infinity
                    let (bytes, response) = try await session.bytes(for: sseRequest)
                    if let http = response as? HTTPURLResponse {
                        guard (200...299).contains(http.statusCode) else {
                            switch http.statusCode {
                            case 401: throw APIError.unauthorized
                            case 403: throw APIError.forbidden
                            case 404: throw APIError.sessionNotFound
                            default: throw APIError.serverError(status: http.statusCode, message: nil)
                            }
                        }
                    }

                    var currentEvent: String?
                    var dataBuffer = ""

                    for try await line in bytes.lines {
                        if Task.isCancelled { break }

                        // RULE-iOS-B: comment / heartbeat line, ignore.
                        if line.hasPrefix(":") {
                            continue
                        }

                        if line.isEmpty {
                            if let event = self.parseEvent(name: currentEvent, data: dataBuffer) {
                                continuation.yield(event)
                            }
                            currentEvent = nil
                            dataBuffer = ""
                            continue
                        }

                        if line.hasPrefix("event:") {
                            currentEvent = String(line.dropFirst("event:".count))
                                .trimmingCharacters(in: .whitespaces)
                        } else if line.hasPrefix("data:") {
                            let chunk = String(line.dropFirst("data:".count))
                                .trimmingCharacters(in: .whitespaces)
                            if !dataBuffer.isEmpty { dataBuffer += "\n" }
                            dataBuffer += chunk
                        } else if line.hasPrefix("id:") || line.hasPrefix("retry:") {
                            // Ignored: not used by hermes-webui contract.
                            continue
                        }
                    }

                    // Flush trailing event if stream ended without final blank line.
                    if currentEvent != nil || !dataBuffer.isEmpty,
                       let event = self.parseEvent(name: currentEvent, data: dataBuffer) {
                        continuation.yield(event)
                    }
                    continuation.finish()
                } catch is CancellationError {
                    continuation.finish()
                } catch let urlError as URLError {
                    continuation.finish(throwing: APIError.networkFailure(urlError))
                } catch let apiError as APIError {
                    continuation.finish(throwing: apiError)
                } catch {
                    continuation.finish(throwing: APIError.streamFailed(error.localizedDescription))
                }
            }

            continuation.onTermination = { _ in
                task.cancel()
            }
        }
    }

    func parseEvent(name: String?, data: String) -> SSEEvent? {
        guard let name, !data.isEmpty else { return nil }
        guard let payloadData = data.data(using: .utf8) else {
            return .unknown(name: name, raw: data)
        }
        switch name {
        case "token":
            if let payload = try? decoder.decode(SSETokenPayload.self, from: payloadData) {
                return .token(payload.text)
            }
        case "tool":
            if let payload = try? decoder.decode(SSEToolPayload.self, from: payloadData) {
                return .tool(name: payload.name, preview: payload.preview ?? "")
            }
        case "approval":
            if let approval = try? decoder.decode(Approval.self, from: payloadData) {
                return .approval(approval)
            }
        case "done":
            if let payload = try? decoder.decode(SSEDonePayload.self, from: payloadData),
               let session = payload.session {
                return .done(session)
            }
            if let session = try? decoder.decode(Session.self, from: payloadData) {
                return .done(session)
            }
        case "error":
            if let payload = try? decoder.decode(SSEErrorPayload.self, from: payloadData) {
                return .error(message: payload.message, trace: payload.trace)
            }
        default:
            break
        }
        return .unknown(name: name, raw: data)
    }
}
