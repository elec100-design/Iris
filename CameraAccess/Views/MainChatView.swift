/*
 * MainChatView — Chat-Centric Root View (UI-02)
 * Image 3 형태: 챗 영역 + 하단 액션 바 + Toolbar 설정 아이콘
 * Tab Bar 제거 — Settings는 우상단 gear 아이콘으로 이동
 */

import SwiftUI

struct MainChatView: View {
    @ObservedObject var streamViewModel: StreamSessionViewModel
    @ObservedObject var wearablesViewModel: WearablesViewModel
    @ObservedObject private var openClawService = OpenClawNodeService.shared
    @StateObject private var visualAI: OpenClawChatViewModel

    @State private var messages: [OpenClawChatMessage] = []
    @State private var inputText = ""
    @State private var pendingResponse = ""
    @State private var showSettings = false
    @State private var showNavInput = false
    @State private var navDestination = ""
    @State private var showHistorySheet = false
    @ObservedObject private var liveAI = LiveAIManager.shared
    @State private var siriMessages: [ChatMessage] = []

    private var apiKey: String { APIKeyManager.shared.getAPIKey() ?? "" }

    init(streamViewModel: StreamSessionViewModel, wearablesViewModel: WearablesViewModel) {
        self.streamViewModel = streamViewModel
        self.wearablesViewModel = wearablesViewModel
        _visualAI = StateObject(wrappedValue: OpenClawChatViewModel(streamViewModel: streamViewModel))
    }

    var body: some View {
        NavigationStack {
            VStack(spacing: 0) {
                connectionBanner
                messagesList
                Divider()
                bottomControls
            }
            .navigationTitle("터보메타")
            .navigationBarTitleDisplayMode(.inline)
            .toolbar {
                ToolbarItem(placement: .topBarLeading) {
                    Button { startNewConversation() } label: {
                        Image(systemName: "square.and.pencil")
                            .font(.system(size: 14))
                    }
                }
                ToolbarItemGroup(placement: .topBarTrailing) {
                    Circle()
                        .fill(openClawService.connectionState == .connected ? Color.green : Color.gray)
                        .frame(width: 8, height: 8)
                    Button { showSettings = true } label: {
                        Image(systemName: "gear")
                            .font(.system(size: 14))
                    }
                }
            }
        }
        .sheet(isPresented: $showSettings) {
            SettingsView(streamViewModel: streamViewModel, apiKey: apiKey)
        }
        .sheet(isPresented: $showHistorySheet) {
            ChatHistoryView { loadedMessages in
                saveCurrentSession()
                messages = loadedMessages
            }
        }
        .onAppear { setupHandlers() }
        .onDisappear { cleanup() }
        .onReceive(NotificationCenter.default.publisher(for: .voiceAgentRequestsListening)) { _ in
            if !liveAI.isRunning { Task { await liveAI.startLiveAISession() } }
        }
        .onReceive(NotificationCenter.default.publisher(for: .voiceAgentDidUpdateMessages)) { _ in
            siriMessages = ConversationMemory.shared.currentMessages
        }
    }

    // MARK: - Connection Banner

    @ViewBuilder
    private var connectionBanner: some View {
        if openClawService.connectionState != .connected {
            HStack(spacing: 8) {
                ProgressView().scaleEffect(0.8)
                Text("openclaw.status.connecting".localized).font(.system(size: 13))
            }
            .frame(maxWidth: .infinity)
            .padding(.vertical, 8)
            .background(Color.orange.opacity(0.15))
        }
    }

    // MARK: - Messages List

    private var messagesList: some View {
        ScrollViewReader { proxy in
            ScrollView {
                LazyVStack(alignment: .leading, spacing: 12) {
                    ForEach(messages) { msg in
                        ChatBubble(message: msg).id(msg.id)
                    }
                    if !pendingResponse.isEmpty {
                        ChatBubble(message: OpenClawChatMessage(role: "assistant", text: pendingResponse, image: nil))
                    }
                    if !siriMessages.isEmpty {
                        Divider()
                            .padding(.horizontal, 16)
                            .padding(.vertical, 4)
                        ForEach(siriMessages) { msg in
                            ChatMessageView(message: msg)
                        }
                    }
                    Color.clear.frame(height: 1).id("chat_bottom")
                }
                .padding()
            }
            .onChange(of: messages.count) {
                withAnimation { proxy.scrollTo("chat_bottom") }
            }
            .onChange(of: siriMessages.count) {
                withAnimation { proxy.scrollTo("chat_bottom") }
            }
        }
    }

    // MARK: - Bottom Controls

    private var bottomControls: some View {
        VStack(spacing: 10) {
            if visualAI.isProcessing {
                HStack(spacing: 8) {
                    ProgressView().scaleEffect(0.8)
                    Text(visualAI.statusMessage).font(.system(size: 13)).foregroundColor(.secondary)
                }
                .frame(maxWidth: .infinity)
                .padding(.horizontal, 16)
                .padding(.vertical, 4)
            }

            if liveAI.isRunning {
                listeningIndicator
            }

            if showNavInput {
                navInputArea
                    .transition(.move(edge: .top).combined(with: .opacity))
            }

            // Action bar: 촬영 분석 | 마이크 | 길찾기 | 대화 기록
            HStack {
                Spacer()

                Button {
                    Task { await triggerSceneDescription() }
                } label: {
                    VStack(spacing: 6) {
                        Image(systemName: "camera.fill").font(.system(size: 28))
                        Text("촬영 분석").font(.caption2)
                    }
                    .foregroundColor(visualAI.isProcessing ? .gray : .white)
                }
                .disabled(visualAI.isProcessing)

                Spacer()

                Button {
                    Task {
                        if liveAI.isRunning { await liveAI.stopSession() }
                        else { await liveAI.startLiveAISession() }
                    }
                } label: {
                    Image(systemName: liveAI.isRunning ? "stop.circle.fill" : "mic.circle.fill")
                        .font(.system(size: 52))
                        .foregroundColor(liveAI.isRunning ? .red : .blue)
                        .shadow(radius: 5)
                }

                Spacer()

                Button {
                    withAnimation(.easeInOut(duration: 0.2)) {
                        showNavInput.toggle()
                        if !showNavInput { navDestination = "" }
                    }
                } label: {
                    VStack(spacing: 6) {
                        Image(systemName: "location.north.circle.fill").font(.system(size: 28))
                        Text("길찾기").font(.caption2)
                    }
                    .foregroundColor(showNavInput ? .yellow : .white)
                }

                Spacer()

                Button { showHistorySheet = true } label: {
                    VStack(spacing: 6) {
                        Image(systemName: "clock.arrow.circlepath").font(.system(size: 28))
                        Text("대화 기록").font(.caption2)
                    }
                    .foregroundColor(.white)
                }

                Spacer()
            }
            .frame(maxWidth: .infinity)
            .padding(.vertical, 12)
            .background(Color.black.opacity(0.85))
            .cornerRadius(16)

            // Text input
            HStack(spacing: 10) {
                TextField(liveAI.isRunning ? "🎤 AI와 대화 중..." : "터보메타에게 말하기...", text: $inputText)
                    .textFieldStyle(.roundedBorder)
                    .submitLabel(.send)
                    .onSubmit { sendText() }

                Button { sendText() } label: {
                    Image(systemName: "arrow.up.circle.fill")
                        .font(.system(size: 30))
                        .foregroundColor(inputText.isEmpty || visualAI.isProcessing ? .gray : .purple)
                }
                .disabled(inputText.isEmpty || visualAI.isProcessing)
            }
            .padding(.horizontal, 16)
        }
        .padding(.vertical, 10)
        .background(Color(.systemBackground))
    }

    // MARK: - Listening Indicator

    private var listeningIndicator: some View {
        HStack(spacing: 8) {
            Image(systemName: "waveform").foregroundColor(.red)
            Text("openclaw.chat.listening".localized)
                .font(.system(size: 14))
                .foregroundColor(.secondary)
        }
        .frame(maxWidth: .infinity, alignment: .leading)
        .padding(.horizontal, 16)
        .padding(.vertical, 4)
    }

    // MARK: - Nav Input

    private var navInputArea: some View {
        HStack(spacing: 10) {
            Image(systemName: "mappin.circle.fill")
                .foregroundColor(.blue)
                .font(.system(size: 20))

            TextField("목적지를 입력하세요...", text: $navDestination)
                .textFieldStyle(.roundedBorder)
                .submitLabel(.go)
                .onSubmit { startNavigation() }

            Button { startNavigation() } label: {
                Text("시작")
                    .font(.system(size: 14, weight: .semibold))
                    .foregroundColor(.white)
                    .padding(.horizontal, 14)
                    .padding(.vertical, 8)
                    .background(navDestination.isEmpty ? Color.gray : Color.blue)
                    .cornerRadius(8)
            }
            .disabled(navDestination.isEmpty)
        }
        .padding(.horizontal, 16)
    }

    // MARK: - Setup

    private func setupHandlers() {
        LiveAIManager.shared.setStreamViewModel(streamViewModel)

        openClawService.onChatEvent = { (text: String) in
            if text.hasPrefix("[[FINAL]]") {
                let fullText = String(text.dropFirst(9))
                pendingResponse = ""
                if !fullText.isEmpty {
                    messages.append(OpenClawChatMessage(role: "assistant", text: fullText, image: nil))
                }
            } else {
                pendingResponse = text
            }
        }
        visualAI.onDescribeResult = { result in
            messages.append(OpenClawChatMessage(role: "assistant", text: result, image: nil))
        }
        if openClawService.connectionState != .connected,
           openClawService.loadGatewayToken() != nil {
            openClawService.connect()
        }
    }

    private func cleanup() {
        liveAI.triggerStop()
        if !pendingResponse.isEmpty {
            messages.append(OpenClawChatMessage(role: "assistant", text: pendingResponse, image: nil))
            pendingResponse = ""
        }
        saveCurrentSession()
        openClawService.onChatEvent = nil
        visualAI.onDescribeResult = nil
    }

    private func saveCurrentSession() {
        OpenClawSessionStorage.shared.saveSession(messages: messages)
    }

    private func startNewConversation() {
        saveCurrentSession()
        messages = []
        pendingResponse = ""
    }

    // MARK: - Actions

    private func triggerSceneDescription() async {
        messages.append(OpenClawChatMessage(role: "user", text: "📷 지금 보는 거 설명해줘", image: nil))
        flushPendingResponse()
        await visualAI.captureAndDescribe()
    }

    private func startNavigation() {
        let dest = navDestination.trimmingCharacters(in: .whitespacesAndNewlines)
        guard !dest.isEmpty else { return }
        messages.append(OpenClawChatMessage(role: "user", text: "🗺️ \(dest) 로 안내해줘", image: nil))
        flushPendingResponse()
        withAnimation { showNavInput = false }
        navDestination = ""
        Task {
            let result = await GoogleMapsNavigator.shared.openWithNaturalLanguage(text: dest)
            messages.append(OpenClawChatMessage(role: "assistant", text: result, image: nil))
        }
    }

    private func sendText() {
        let text = inputText.trimmingCharacters(in: .whitespacesAndNewlines)
        guard !text.isEmpty else { return }
        flushPendingResponse()
        inputText = ""
        messages.append(OpenClawChatMessage(role: "user", text: text, image: nil))
        let historySnapshot = Array(messages.dropLast()) // 방금 추가한 메시지 제외
        Task {
            let response = await visualAI.processTextChat(text: text, history: historySnapshot)
            messages.append(OpenClawChatMessage(role: "assistant", text: response, image: nil))
        }
    }

    private func flushPendingResponse() {
        if !pendingResponse.isEmpty {
            messages.append(OpenClawChatMessage(role: "assistant", text: pendingResponse, image: nil))
            pendingResponse = ""
        }
    }
}
