import SwiftData
import Foundation

@Model
final class ConversationSession {
    var sessionId: UUID
    var createdAt: Date
    var lastUpdated: Date
    @Relationship(deleteRule: .cascade) var messages: [ChatMessage] = []

    init() {
        self.sessionId = UUID()
        self.createdAt = Date()
        self.lastUpdated = Date()
    }
}

@Model
final class ChatMessage {
    var role: String      // "user" | "assistant"
    var content: String
    var timestamp: Date
    var imageData: Data?

    init(role: String, content: String, imageData: Data? = nil) {
        self.role = role
        self.content = content
        self.timestamp = Date()
        self.imageData = imageData
    }
}
