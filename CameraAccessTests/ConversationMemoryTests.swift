/*
 * ConversationMemoryTests
 * Swift Testing: ConversationMemory 세션 & 메시지 관리 검증
 * Uses ConversationMemory.shared — each test calls startNewSession() for isolation.
 */

import Testing
@testable import CameraAccess

@MainActor
struct ConversationMemoryTests {

    @Test("New session starts with zero messages")
    func newSessionIsEmpty() {
        let memory = ConversationMemory.shared
        memory.startNewSession()
        #expect(memory.currentMessageCount == 0)
        #expect(memory.currentSession != nil)
    }

    @Test("Append user message increments count")
    func appendUserMessage() {
        let memory = ConversationMemory.shared
        memory.startNewSession()
        memory.appendMessage(role: "user", content: "안녕하세요")
        #expect(memory.currentMessageCount == 1)
    }

    @Test("Append user + assistant messages both persist")
    func appendBothRoles() {
        let memory = ConversationMemory.shared
        memory.startNewSession()
        memory.appendMessage(role: "user", content: "지금 뭐 보여?")
        memory.appendMessage(role: "assistant", content: "사과가 보입니다.")
        #expect(memory.currentMessageCount == 2)
    }

    @Test("getRecentContext formats roles as User:/Assistant: prefixes")
    func recentContextFormat() {
        let memory = ConversationMemory.shared
        memory.startNewSession()
        memory.appendMessage(role: "user", content: "안녕")
        memory.appendMessage(role: "assistant", content: "안녕하세요!")
        let context = memory.getRecentContext(maxTurns: 12)
        #expect(context.contains("User: 안녕"))
        #expect(context.contains("Assistant: 안녕하세요!"))
    }

    @Test("getRecentContext respects maxTurns limit")
    func recentContextTurnLimit() {
        let memory = ConversationMemory.shared
        memory.startNewSession()
        for i in 0..<10 {
            memory.appendMessage(role: "user", content: "질문 \(i)")
            memory.appendMessage(role: "assistant", content: "답변 \(i)")
        }
        let context = memory.getRecentContext(maxTurns: 3)
        // maxTurns: 3 → suffix(6) → at most 6 non-empty lines
        let lines = context.split(separator: "\n", omittingEmptySubsequences: true)
        #expect(lines.count <= 6)
    }

    @Test("getRecentContext returns empty string with no messages")
    func emptyContextWhenNoMessages() {
        let memory = ConversationMemory.shared
        memory.startNewSession()
        #expect(memory.getRecentContext().isEmpty)
    }

    @Test("endCurrentSession sets currentSession to nil")
    func endSessionClearsState() {
        let memory = ConversationMemory.shared
        memory.startNewSession()
        memory.appendMessage(role: "user", content: "테스트")
        memory.endCurrentSession()
        #expect(memory.currentSession == nil)
    }

    @Test("startNewSession after end yields a fresh empty session")
    func newSessionAfterEndIsEmpty() {
        let memory = ConversationMemory.shared
        memory.startNewSession()
        memory.appendMessage(role: "user", content: "이전 메시지")
        memory.endCurrentSession()
        memory.startNewSession()
        #expect(memory.currentMessageCount == 0)
        #expect(memory.currentSession != nil)
    }

    @Test("Image data attaches to ChatMessage")
    func appendMessageWithImageData() {
        let memory = ConversationMemory.shared
        memory.startNewSession()
        let fakeImageData = Data(repeating: 0xFF, count: 16)
        memory.appendMessage(role: "user", content: "이 사진 설명해줘", imageData: fakeImageData)
        #expect(memory.currentMessageCount == 1)
        #expect(memory.currentSession?.messages.first?.imageData == fakeImageData)
    }
}
