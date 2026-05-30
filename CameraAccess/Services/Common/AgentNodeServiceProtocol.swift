import Foundation

// MARK: - Backend Provider

enum BackendProvider: String, CaseIterable, Identifiable {
    case openClaw = "OpenClaw"
    case hermes = "Hermes"

    var id: String { rawValue }
}

// MARK: - Common Connection State

enum AgentConnectionState: Equatable {
    case disconnected
    case connecting
    case connected
    case error(String)

    static func == (lhs: AgentConnectionState, rhs: AgentConnectionState) -> Bool {
        switch (lhs, rhs) {
        case (.disconnected, .disconnected),
             (.connecting, .connecting),
             (.connected, .connected):
            return true
        case (.error(let a), .error(let b)):
            return a == b
        default:
            return false
        }
    }
}

// MARK: - Protocol

/// Pluggable interface for AI agent backends (OpenClaw, Hermes, …).
/// Conforming services expose a unified connection lifecycle and both
/// callback-style (onAgentChunk) and streaming (processAgentCommand) APIs.
protocol AgentNodeServiceProtocol: AnyObject {

    /// Unified connection state across backends.
    var agentConnectionState: AgentConnectionState { get }

    /// Called with each streamed token/chunk as it arrives.
    var onAgentChunk: ((String) -> Void)? { get set }

    /// Send a multimodal payload; response tokens arrive via `onAgentChunk`.
    func sendAgentPayload(_ payload: AgentPayload) async throws

    /// Returns an AsyncThrowingStream that yields response tokens one-by-one.
    func processAgentCommand(_ command: String, imageData: Data?) async throws -> AsyncThrowingStream<String, Error>

    func connect()
    func disconnect()
}
