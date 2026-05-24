/*
 * MainChatView — Dual-Mode Root View
 * Iris Live (red) / Agent (blue) + Chat history
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
    @State private var showHistorySheet = false
    @ObservedObject private var liveAI = LiveAIManager.shared
    @State private var siriMessages: [ChatMessage] = []

    // Dual-mode state
    @State private var appMode: AppMode = .idle
    @State private var isPulsing = false

    private var apiKey: String { APIKeyManager.shared.getAPIKey() ?? "" }

    init(streamViewModel: StreamSessionViewModel, wearablesViewModel: WearablesViewModel) {
        self.streamViewModel = streamViewModel
        self.wearablesViewModel = wearablesViewModel
        _visualAI = StateObject(wrappedValue: OpenClawChatViewModel(streamViewModel: streamViewModel))
    }

    var body: some View {
        ZStack {
            // Subtle mode-driven background tint
            modeBackground

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

            // Pulse ring — live 모드 전용
            if appMode == .live {
                VStack {
                    Spacer()
                    Circle()
                        .stroke(Color.red.opacity(0.3), lineWidth: 1.5)
                        .frame(width: 72, height: 72)
                        .scaleEffect(isPulsing ? 2.6 : 1.0)
                        .opacity(isPulsing ? 0 : 0.9)
                        .animation(.easeOut(duration: 1.6).repeatForever(autoreverses: false), value: isPulsing)
                        .padding(.bottom, 110)
                }
                .allowsHitTesting(false)
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
            if !liveAI.isRunning { activateLive() }
        }
        .onReceive(NotificationCenter.default.publisher(for: .voiceAgentDidUpdateMessages)) { _ in
            siriMessages = ConversationMemory.shared.currentMessages
        }
        .onChange(of: liveAI.isRunning) { isRunning in
            if !isRunning && appMode == .live {
                withAnimation(.easeInOut(duration: 0.5)) { appMode = .idle }
                isPulsing = false
            }
        }
    }

    // MARK: - Mode Background

    @ViewBuilder
    private var modeBackground: some View {
        switch appMode {
        case .idle:
            Color.clear
        case .live:
            Color.red.opacity(0.07)
                .ignoresSafeArea()
                .animation(.easeInOut(duration: 0.6), value: appMode)
        case .agent:
            Color.blue.opacity(0.07)
                .ignoresSafeArea()
                .animation(.easeInOut(duration: 0.6), value: appMode)
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

            // Mode control bar
            HStack(spacing: 0) {
                Spacer()

                // Live button
                Button { toggleLive() } label: {
                    VStack(spacing: 6) {
                        ZStack {
                            Circle()
                                .fill(appMode == .live ? Color.red : Color.red.opacity(0.18))
                                .frame(width: 54, height: 54)
                                .shadow(color: appMode == .live ? Color.red.opacity(0.55) : .clear, radius: 14)
                            Image(systemName: appMode == .live ? "stop.fill" : "mic.fill")
                                .font(.system(size: 22, weight: .medium))
                                .foregroundColor(.white)
                        }
                        Text("Live")
                            .font(.caption2)
                            .foregroundColor(appMode == .live ? .red : .white.opacity(0.8))
                    }
                }
                .animation(.spring(response: 0.35, dampingFraction: 0.65), value: appMode)

                Spacer()

                // Agent button
                Button { toggleAgent() } label: {
                    VStack(spacing: 6) {
                        ZStack {
                            Circle()
                                .fill(appMode == .agent ? AppColors.primary : AppColors.primary.opacity(0.18))
                                .frame(width: 54, height: 54)
                                .shadow(color: appMode == .agent ? AppColors.primary.opacity(0.55) : .clear, radius: 14)
                            Image(systemName: "sparkles")
                                .font(.system(size: 22, weight: .medium))
                                .foregroundColor(.white)
                        }
                        Text("에이전트")
                            .font(.caption2)
                            .foregroundColor(appMode == .agent ? AppColors.primary : .white.opacity(0.8))
                    }
                }
                .animation(.spring(response: 0.35, dampingFraction: 0.65), value: appMode)

                Spacer()

                // History
                Button { showHistorySheet = true } label: {
                    VStack(spacing: 6) {
                        Image(systemName: "clock.arrow.circlepath").font(.system(size: 28))
                        Text("대화 기록").font(.caption2)
                    }
                    .foregroundColor(.white.opacity(0.7))
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

    // MARK: - Mode Actions

    private func activateLive() {
        withAnimation(.easeInOut(duration: 0.5)) { appMode = .live }
        isPulsing = false
        DispatchQueue.main.asyncAfter(deadline: .now() + 0.05) { isPulsing = true }
        Task { await liveAI.startLiveAISession() }
    }

    private func toggleLive() {
        if appMode == .live {
            withAnimation(.easeInOut(duration: 0.5)) { appMode = .idle }
            isPulsing = false
            Task { await liveAI.stopSession() }
        } else {
            activateLive()
        }
    }

    private func toggleAgent() {
        if appMode == .agent {
            withAnimation(.easeInOut(duration: 0.5)) { appMode = .idle }
        } else {
            withAnimation(.easeInOut(duration: 0.5)) { appMode = .agent }
            openClawService.connect()
        }
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

    // MARK: - Text Chat

    private func sendText() {
        let text = inputText.trimmingCharacters(in: .whitespacesAndNewlines)
        guard !text.isEmpty else { return }
        flushPendingResponse()
        inputText = ""
        messages.append(OpenClawChatMessage(role: "user", text: text, image: nil))
        let historySnapshot = Array(messages.dropLast())
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
