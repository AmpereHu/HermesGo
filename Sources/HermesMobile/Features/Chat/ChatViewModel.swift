import Foundation
import Observation

@Observable
@MainActor
public final class ChatViewModel {
    public let sessionId: String
    public private(set) var session: Session?
    public private(set) var messages: [Message] = []
    public private(set) var pendingApproval: Approval?
    public private(set) var currentToolCall: ToolCall?
    public private(set) var streamingMessage: String = ""
    public private(set) var isStreaming: Bool = false
    public private(set) var isLoading: Bool = false
    public private(set) var activeStreamId: String?
    public var errorMessage: String?

    private let api: APIClientProtocol
    private let preferences: Preferences
    private var streamTask: Task<Void, Never>?
    private var approvalPollTask: Task<Void, Never>?
    private var reconnectAttempt: Int = 0
    private let maxReconnectDelay: UInt64 = 30 * 1_000_000_000

    public init(
        sessionId: String,
        api: APIClientProtocol,
        preferences: Preferences = .shared
    ) {
        self.sessionId = sessionId
        self.api = api
        self.preferences = preferences
    }

    public func load() async {
        guard !isLoading else { return }
        isLoading = true
        defer { isLoading = false }
        do {
            let session = try await api.getSession(id: sessionId)
            apply(session)
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

    public func send(_ text: String) async {
        let trimmed = text.trimmingCharacters(in: .whitespacesAndNewlines)
        guard !trimmed.isEmpty, !isStreaming else { return }

        // RULE-5: capture activeSid before any await; refuse if already changed.
        let activeSid = sessionId

        // Optimistic user message so the user sees their message immediately.
        let pendingUser = Message(role: .user, content: trimmed, createdAt: Date().timeIntervalSince1970)
        messages.append(pendingUser)

        isStreaming = true
        streamingMessage = ""
        errorMessage = nil
        currentToolCall = nil

        let model = session?.model.isEmpty == false ? session?.model : preferences.preferredModel
        let workspace = session?.workspace.isEmpty == false ? session?.workspace : nil

        let response: ChatStartResponse
        do {
            response = try await api.startChat(
                sessionId: activeSid,
                message: trimmed,
                model: model,
                workspace: workspace
            )
        } catch let error as APIError {
            isStreaming = false
            errorMessage = error.errorDescription
            // Roll back optimistic user message so the server's `done` payload doesn't double it.
            messages.removeAll { $0.id == pendingUser.id }
            return
        } catch {
            isStreaming = false
            errorMessage = error.localizedDescription
            messages.removeAll { $0.id == pendingUser.id }
            return
        }

        guard sessionId == activeSid else { return }
        activeStreamId = response.streamId
        preferences.lastStreamId = response.streamId
        startStream(streamId: response.streamId, allowReconnect: true)
    }

    public func cancel() async {
        guard let streamId = activeStreamId else {
            stopStream()
            return
        }
        do {
            try await api.cancelChat(streamId: streamId)
        } catch {
            // Falls back to client-side stop. Cancel endpoint may be pending upstream.
        }
        stopStream()
    }

    public func respondApproval(_ choice: ApprovalChoice) async {
        guard pendingApproval != nil else { return }
        do {
            try await api.respondApproval(sessionId: sessionId, choice: choice)
            pendingApproval = nil
        } catch let error as APIError {
            errorMessage = error.errorDescription
        } catch {
            errorMessage = error.localizedDescription
        }
    }

    /// Called when the app returns to the foreground.
    /// Determines whether to resume the SSE stream or refetch the session.
    public func handleForeground() async {
        if let streamId = activeStreamId {
            do {
                let status = try await api.streamStatus(streamId: streamId)
                if status.active {
                    startStream(streamId: streamId, allowReconnect: true)
                } else {
                    stopStream()
                    await load()
                }
            } catch {
                stopStream()
                await load()
            }
        } else if isStreaming, let streamId = preferences.lastStreamId {
            // Edge case: ViewModel lost activeStreamId but UI still thinks streaming.
            startStream(streamId: streamId, allowReconnect: true)
        }
        // F-04.6: always re-check pending approvals when foregrounding.
        await pollPendingApprovalOnce()
    }

    public func handleBackground() {
        preferences.lastBackgroundDate = Date()
        // Don't cancel the SSE task: iOS will pause it naturally; if we explicitly cancel
        // we'd lose the chance to resume on quick foreground returns.
    }

    public func teardown() {
        stopStream()
        stopApprovalPolling()
    }

    // MARK: - Streaming

    private func startStream(streamId: String, allowReconnect: Bool) {
        streamTask?.cancel()
        let stream = api.streamChat(streamId: streamId)
        let activeSid = sessionId

        streamTask = Task { [weak self] in
            guard let self else { return }
            await self.consume(stream: stream, streamId: streamId, sessionId: activeSid, allowReconnect: allowReconnect)
        }
    }

    private func consume(
        stream: AsyncThrowingStream<SSEEvent, Error>,
        streamId: String,
        sessionId activeSid: String,
        allowReconnect: Bool
    ) async {
        stopApprovalPolling()
        do {
            for try await event in stream {
                guard sessionId == activeSid else { break }
                handle(event: event)
                if case .done = event { break }
                if case .error = event { break }
            }
            // Stream ended normally.
            if isStreaming {
                isStreaming = false
                activeStreamId = nil
            }
            reconnectAttempt = 0
        } catch is CancellationError {
            // No-op: cancellation is intentional.
        } catch let apiError as APIError {
            await handleStreamFailure(apiError, streamId: streamId, allowReconnect: allowReconnect)
        } catch {
            await handleStreamFailure(.streamFailed(error.localizedDescription), streamId: streamId, allowReconnect: allowReconnect)
        }
    }

    private func handle(event: SSEEvent) {
        switch event {
        case .token(let chunk):
            streamingMessage.append(chunk)
            if currentToolCall != nil {
                currentToolCall = nil
            }
        case .tool(let name, let preview):
            currentToolCall = ToolCall(name: name, preview: preview)
        case .approval(let approval):
            pendingApproval = approval
        case .done(let session):
            apply(session)
            streamingMessage = ""
            currentToolCall = nil
            isStreaming = false
            activeStreamId = nil
        case .error(let message, _):
            errorMessage = message
            isStreaming = false
            activeStreamId = nil
            currentToolCall = nil
            streamingMessage = ""
            startApprovalPolling()
        case .unknown:
            break
        }
    }

    private func handleStreamFailure(_ error: APIError, streamId: String, allowReconnect: Bool) async {
        guard allowReconnect, error.isRetryable else {
            isStreaming = false
            activeStreamId = nil
            errorMessage = error.errorDescription
            startApprovalPolling()
            return
        }
        let attempt = min(reconnectAttempt, 5)
        reconnectAttempt += 1
        let baseDelay: UInt64 = 1_000_000_000 << attempt
        let delay = min(baseDelay, maxReconnectDelay)
        try? await Task.sleep(nanoseconds: delay)
        guard !Task.isCancelled, isStreaming else { return }
        do {
            let status = try await api.streamStatus(streamId: streamId)
            if status.active {
                startStream(streamId: streamId, allowReconnect: true)
            } else {
                isStreaming = false
                activeStreamId = nil
                await load()
            }
        } catch {
            isStreaming = false
            activeStreamId = nil
            errorMessage = error.localizedDescription
        }
    }

    private func stopStream() {
        streamTask?.cancel()
        streamTask = nil
        isStreaming = false
        activeStreamId = nil
        streamingMessage = ""
        currentToolCall = nil
    }

    // MARK: - Approval polling fallback (F-04.5)

    private func startApprovalPolling() {
        guard approvalPollTask == nil else { return }
        approvalPollTask = Task { [weak self] in
            guard let self else { return }
            while !Task.isCancelled {
                await self.pollPendingApprovalOnce()
                try? await Task.sleep(nanoseconds: 1_500_000_000)
            }
        }
    }

    private func stopApprovalPolling() {
        approvalPollTask?.cancel()
        approvalPollTask = nil
    }

    private func pollPendingApprovalOnce() async {
        do {
            if let approval = try await api.pendingApproval(sessionId: sessionId) {
                pendingApproval = approval
            }
        } catch {
            // Polling errors are silent; user already sees stream error if any.
        }
    }

    // MARK: - Helpers

    private func apply(_ session: Session) {
        self.session = session
        self.messages = session.messages
        self.pendingApproval = nil
    }
}
