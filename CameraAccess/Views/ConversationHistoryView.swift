/*
 * ConversationHistoryView
 * 과거 ConversationSession 목록 + 세션 상세 보기
 * ConversationMemory.shared.allSessions 으로 SwiftData 컨텍스트 직접 조회 — @Query 불필요
 */

import SwiftUI

struct ConversationHistoryView: View {
    @State private var sessions: [ConversationSession] = []

    var body: some View {
        List {
            if sessions.isEmpty {
                Text("저장된 대화가 없습니다.")
                    .foregroundStyle(.secondary)
                    .frame(maxWidth: .infinity, alignment: .center)
                    .listRowBackground(Color.clear)
            }
            ForEach(sessions) { session in
                NavigationLink {
                    SessionDetailView(session: session)
                } label: {
                    VStack(alignment: .leading, spacing: 4) {
                        Text(session.messages.first.map { String($0.content.prefix(60)) } ?? "빈 대화")
                            .font(.body)
                            .lineLimit(2)
                        Text(session.lastUpdated, style: .relative)
                            .font(.caption)
                            .foregroundStyle(.secondary)
                    }
                    .padding(.vertical, 4)
                }
            }
        }
        .navigationTitle("대화 기록")
        .onAppear {
            sessions = ConversationMemory.shared.allSessions
        }
    }
}

private struct SessionDetailView: View {
    let session: ConversationSession

    var body: some View {
        ScrollView {
            LazyVStack(spacing: 12) {
                ForEach(session.messages) { msg in
                    ChatMessageView(message: msg)
                }
            }
            .padding(.vertical)
        }
        .navigationTitle(session.createdAt.formatted(.dateTime.month().day().hour().minute()))
        .navigationBarTitleDisplayMode(.inline)
    }
}
