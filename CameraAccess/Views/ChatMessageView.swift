/*
 * ChatMessageView
 * iMessage 스타일 말풍선 — ChatMessage(SwiftData) 렌더링
 * 사용처: MainChatView (Siri/UnifiedVoiceAgent 경로), ConversationHistoryView
 */

import SwiftUI

struct ChatMessageView: View {
    let message: ChatMessage

    var body: some View {
        HStack(alignment: .bottom, spacing: 0) {
            if message.role == "user" { Spacer(minLength: 48) }
            Text(message.content)
                .padding(.horizontal, 14)
                .padding(.vertical, 10)
                .background(message.role == "user" ? Color.blue : Color(.systemGray6))
                .foregroundStyle(message.role == "user" ? Color.white : Color.primary)
                .clipShape(RoundedRectangle(cornerRadius: 18))
                .frame(maxWidth: UIScreen.main.bounds.width * 0.75,
                       alignment: message.role == "user" ? .trailing : .leading)
            if message.role == "assistant" { Spacer(minLength: 48) }
        }
        .padding(.horizontal, 16)
        .accessibilityLabel("\(message.role == "user" ? "나" : "터보메타"): \(message.content)")
    }
}
