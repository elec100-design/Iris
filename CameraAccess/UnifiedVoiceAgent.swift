/*
 * UnifiedVoiceAgent
 * Thin facade that chains:
 *   ConversationMemory (context) → AI routing → TTSService → memory persist → continuous-listen signal
 */

import Foundation

extension Notification.Name {
    /// Posted after each AI response. MainChatView observes this to auto-restart the mic.
    static let voiceAgentRequestsListening = Notification.Name("voiceAgentRequestsListening")
    /// Posted after memory is updated. MainChatView mirrors ConversationMemory messages into the bubble list.
    static let voiceAgentDidUpdateMessages = Notification.Name("voiceAgentDidUpdateMessages")
}

@MainActor
final class UnifiedVoiceAgent {
    static let shared = UnifiedVoiceAgent()

    private static let sceneKeywords: [String] = [
        "지금", "보이는", "장면", "번역", "분석", "현재", "찍어", "사진", "카메라"
    ]

    private init() {
        // Pre-warm system TTS to eliminate cold-start latency
        TTSService.shared.prewarm()
    }

    // MARK: - Main Entry Point

    /// Process a voice command with full conversation context, TTS output, and memory persistence.
    func processVoiceCommand(_ command: String, imageData: Data? = nil) async {
        let memory = ConversationMemory.shared

        // 1. Build context-aware prompt
        let history = memory.getRecentContext(maxTurns: 12)
        let fullPrompt: String
        if history.isEmpty {
            fullPrompt = command
        } else {
            fullPrompt = """
이전 대화:
\(history)

위 대화 문맥을 바탕으로 다음 질문에 답해:
\(command)
"""
        }

        // 2. Route: vision capture vs text chat
        let isSceneCommand = Self.sceneKeywords.contains { command.contains($0) }
        let response: String

        if isSceneCommand {
            // Vision path — captures a frame and runs Gemini vision with the full prompt
            await QuickVisionManager.shared.performQuickVisionWithMode(.standard, customPrompt: fullPrompt)
            response = QuickVisionManager.shared.lastResult ?? command
        } else if let chatVM = OpenClawChatViewModel.shared {
            // Text chat path — Gemini text with conversation history embedded
            await chatVM.processNaturalCommand(text: fullPrompt)
            response = chatVM.lastAnalysisResult
        } else {
            // App not yet initialized — use fast system TTS directly
            response = "앱을 먼저 실행해 주세요."
            TTSService.shared.speakFast(response)
        }

        // 3. Persist to memory
        memory.appendMessage(role: "user", content: command, imageData: imageData)
        if !response.isEmpty {
            memory.appendMessage(role: "assistant", content: response)
        }

        // 4. Notify UI to mirror updated ConversationMemory messages as bubbles
        NotificationCenter.default.post(name: .voiceAgentDidUpdateMessages, object: nil)

        // 5. Signal in-app continuous listening (MainChatView observes this)
        NotificationCenter.default.post(name: .voiceAgentRequestsListening, object: nil)
    }
}
