/*
 * ConversationMemory
 * SwiftData-backed session memory for continuous conversation context.
 * Keeps the last N turns to send as history with each new Gemini request.
 */

import SwiftData
import Foundation
import Observation

@Observable
@MainActor
final class ConversationMemory {
    static let shared = ConversationMemory()

    private let container: ModelContainer
    private let context: ModelContext
    private(set) var currentSession: ConversationSession?

    private init() {
        let schema = Schema([ConversationSession.self, ChatMessage.self])
        let persistConfig = ModelConfiguration(schema: schema, isStoredInMemoryOnly: false)
        do {
            container = try ModelContainer(for: schema, configurations: [persistConfig])
        } catch {
            // Fallback to in-memory if persistent store migration fails
            print("[ConversationMemory] Falling back to in-memory store: \(error)")
            let memConfig = ModelConfiguration(schema: schema, isStoredInMemoryOnly: true)
            container = try! ModelContainer(for: schema, configurations: [memConfig])
        }
        context = ModelContext(container)
        startNewSession()
    }

    // MARK: - Session Lifecycle

    func startNewSession() {
        let session = ConversationSession()
        context.insert(session)
        try? context.save()
        currentSession = session
        print("[ConversationMemory] New session started: \(session.sessionId)")
    }

    func endCurrentSession() {
        try? context.save()
        currentSession = nil
    }

    // MARK: - Message Management

    func appendMessage(role: String, content: String, imageData: Data? = nil) {
        if currentSession == nil { startNewSession() }
        guard let session = currentSession else { return }
        let msg = ChatMessage(role: role, content: content, imageData: imageData)
        context.insert(msg)
        session.messages.append(msg)
        session.lastUpdated = Date()
        try? context.save()
    }

    // MARK: - Context Building

    /// Returns the last `maxTurns` conversation turns formatted for LLM context injection.
    func getRecentContext(maxTurns: Int = 12) -> String {
        guard let session = currentSession, !session.messages.isEmpty else { return "" }
        let recent = Array(session.messages.suffix(maxTurns * 2))
        return recent
            .map { "\($0.role == "user" ? "User" : "Assistant"): \($0.content)" }
            .joined(separator: "\n")
    }

    /// Total message count in the current session.
    var currentMessageCount: Int {
        currentSession?.messages.count ?? 0
    }

    /// All messages in the current session — observed by MainChatView for real-time display.
    var currentMessages: [ChatMessage] { currentSession?.messages ?? [] }

    /// All sessions sorted by most recently updated — used by ConversationHistoryView.
    var allSessions: [ConversationSession] {
        let descriptor = FetchDescriptor<ConversationSession>(
            sortBy: [SortDescriptor(\ConversationSession.lastUpdated, order: .reverse)]
        )
        return (try? context.fetch(descriptor)) ?? []
    }
}
