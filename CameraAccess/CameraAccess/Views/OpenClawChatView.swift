import SwiftUI

struct OpenClawChatMessage: Identifiable {
    let id = UUID()
    let role: String
    let text: String
    let image: UIImage?
    let timestamp = Date()
}

// MARK: - App Mode (module-level, shared across views)
// Note: AppMode is defined once in TurboMetaHomeView.swift — reused here

struct OpenClawChatView: View {
    @ObservedObject var streamViewModel: StreamSessionViewModel
    @ObservedObject var openClawService = OpenClawNodeService.shared
    @StateObject private var visualAI: OpenClawChatViewModel
    @ObservedObject private var liveAI = LiveAIManager.shared
    @Environment(\.dismiss) private var dismiss

    @State private var messages: [OpenClawChatMessage] = []
    @State private var inputText = ""
    @State private var pendingResponse = ""
    @State private var showHistorySheet = false

    // ASR (kept for future use)
    @State private var isListening = false
    @State private var asrText = ""
    @State private var asrPartial = ""
    @State private var asrService: OpenClawASRService?

    // Dual-mode
    @State private var appMode: AppMode = .idle
    @State private var isPulsing = false

    init(streamViewModel: StreamSessionViewModel) {
        self.streamViewModel = streamViewModel
        _visualAI = StateObject(wrappedValue: OpenClawChatViewModel(streamViewModel: streamViewModel))
    }

    // MARK: - Background

    private var modeBackgroundColors: [Color] {
        switch appMode {
        case .idle:   return [Color(.systemBackground), Color(.systemBackground)]
        case .live:   return [Color(red: 0.52, green: 0.04, blue: 0.04), Color(red: 0.16, green: 0.01, blue: 0.01)]
        case .agent:  return [Color(red: 0.04, green: 0.07, blue: 0.42), Color(red: 0.02, green: 0.03, blue: 0.24)]
        }
    }

    // MARK: - Body

    var body: some View {
        ZStack {
            // Mode-driven background
            LinearGradient(colors: modeBackgroundColors, startPoint: .topLeading, endPoint: .bottomTrailing)
                .ignoresSafeArea()
                .animation(.easeInOut(duration: 0.65), value: appMode)

            // Pulse ring — live 전용
            if appMode == .live {
                VStack {
                    Spacer()
                    Circle()
                        .stroke(Color.red.opacity(0.35), lineWidth: 1.5)
                        .frame(width: 76, height: 76)
                        .scaleEffect(isPulsing ? 2.8 : 1.0)
                        .opacity(isPulsing ? 0 : 0.9)
                        .animation(.easeOut(duration: 1.7).repeatForever(autoreverses: false), value: isPulsing)
                        .padding(.bottom, 120)
                }
                .allowsHitTesting(false)
            }

            // Agent glow — agent 전용
            if appMode == .agent {
                VStack {
                    Spacer()
                    Circle()
                        .fill(
                            RadialGradient(
                                colors: [AppColors.primary.opacity(0.35), .clear],
                                center: .center,
                                startRadius: 0,
                                endRadius: 80
                            )
                        )
                        .frame(width: 160, height: 160)
                        .padding(.bottom, 100)
                }
                .allowsHitTesting(false)
            }

            NavigationView {
                VStack(spacing: 0) {
                    connectionBanner
                    messagesList
                    Divider()
                        .background(appMode == .idle ? Color.primary.opacity(0.2) : Color.white.opacity(0.15))
                    bottomControls
                }
                .navigationTitle("터보메타")
                .navigationBarTitleDisplayMode(.inline)
                .toolbar {
                    ToolbarItem(placement: .navigationBarLeading) {
                        Button { dismiss() } label: {
                            Image(systemName: "xmark")
                                .foregroundColor(appMode == .idle ? .primary : .white)
                        }
                    }
                    ToolbarItem(placement: .navigationBarTrailing) {
                        HStack(spacing: 10) {
                            Button { startNewConversation() } label: {
                                Image(systemName: "square.and.pencil")
                                    .font(.system(size: 14))
                                    .foregroundColor(appMode == .idle ? .primary : .white)
                            }
                            Circle()
                                .fill(openClawService.connectionState == .connected ? Color.green : Color.gray)
                                .frame(width: 8, height: 8)
                            NavigationLink { OpenClawSettingsView() } label: {
                                Image(systemName: "gear")
                                    .font(.system(size: 14))
                                    .foregroundColor(appMode == .idle ? .primary : .white)
                            }
                        }
                    }
                }
            }
        }
        .onAppear { setupHandlers() }
        .onDisappear { cleanup() }
        .sheet(isPresented: $showHistorySheet) {
            ChatHistoryView { loadedMessages in
                saveCurrentSession()
                messages = loadedMessages
            }
        }
        .onChange(of: liveAI.isRunning) { isRunning in
            if !isRunning && appMode == .live {
                withAnimation(.easeInOut(duration: 0.65)) { appMode = .idle }
                isPulsing = false
            }
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
                    Color.clear.frame(height: 1).id("bottom")
                }
                .padding()
            }
            .onChange(of: messages.count) {
                withAnimation { proxy.scrollTo("bottom") }
            }
        }
    }

    // MARK: - Bottom Controls

    private var bottomControls: some View {
        VStack(spacing: 10) {
            if visualAI.isProcessing {
                HStack(spacing: 8) {
                    ProgressView().scaleEffect(0.8)
                    Text(visualAI.statusMessage)
                        .font(.system(size: 13))
                        .foregroundColor(appMode == .idle ? .secondary : .white.opacity(0.7))
                }
                .frame(maxWidth: .infinity)
                .padding(.horizontal, 16)
                .padding(.vertical, 4)
            }

            if liveAI.isRunning {
                listeningIndicator
            }

            // Dual-mode action bar
            HStack(spacing: 0) {
                Spacer()

                // Live button
                Button { toggleLive() } label: {
                    VStack(spacing: 6) {
                        ZStack {
                            Circle()
                                .fill(appMode == .live ? Color.red : Color.red.opacity(0.18))
                                .frame(width: 56, height: 56)
                                .shadow(color: appMode == .live ? Color.red.opacity(0.6) : .clear, radius: 16)
                            Image(systemName: appMode == .live ? "stop.fill" : "mic.fill")
                                .font(.system(size: 24, weight: .medium))
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
                                .frame(width: 56, height: 56)
                                .shadow(color: appMode == .agent ? AppColors.primary.opacity(0.6) : .clear, radius: 16)
                            Image(systemName: "sparkles")
                                .font(.system(size: 24, weight: .medium))
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
                        .foregroundColor(inputText.isEmpty ? .gray : .purple)
                }
                .disabled(inputText.isEmpty || openClawService.connectionState != .connected)
            }
            .padding(.horizontal, 16)
        }
        .padding(.vertical, 10)
        .background(appMode == .idle ? Color(.systemBackground) : Color.black.opacity(0.6))
    }

    // MARK: - Listening Indicator

    private var listeningIndicator: some View {
        HStack(spacing: 8) {
            Image(systemName: "waveform").foregroundColor(.red)
            Text("openclaw.chat.listening".localized)
                .font(.system(size: 14))
                .foregroundColor(appMode == .idle ? .secondary : .white.opacity(0.7))
        }
        .frame(maxWidth: .infinity, alignment: .leading)
        .padding(.horizontal, 16)
        .padding(.vertical, 4)
    }

    // MARK: - Mode Actions

    private func toggleLive() {
        if appMode == .live {
            withAnimation(.easeInOut(duration: 0.65)) { appMode = .idle }
            isPulsing = false
            liveAI.triggerStop()
        } else {
            withAnimation(.easeInOut(duration: 0.65)) { appMode = .live }
            isPulsing = false
            DispatchQueue.main.asyncAfter(deadline: .now() + 0.05) { isPulsing = true }
            liveAI.setStreamViewModel(streamViewModel)
            Task { await liveAI.startLiveAISession() }
        }
    }

    private func toggleAgent() {
        if appMode == .agent {
            withAnimation(.easeInOut(duration: 0.65)) { appMode = .idle }
        } else {
            withAnimation(.easeInOut(duration: 0.65)) { appMode = .agent }
            openClawService.connect()
        }
    }

    // MARK: - Setup

    private func setupHandlers() {
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
        stopListening()
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
        messages.append(OpenClawChatMessage(role: "user", text: text, image: nil))
        flushPendingResponse()
        inputText = ""
        openClawService.sendChatMessage(text)
    }

    // MARK: - Voice (ASR)

    private func toggleListening() {
        if isListening { stopListening() } else { startListening() }
    }

    private func startListening() {
        guard let apiKey = APIKeyManager.shared.getAPIKey(for: .openrouter), !apiKey.isEmpty else {
            let errorMsg = NSLocalizedString("livetranslate.error.noApiKey", comment: "")
            messages.append(OpenClawChatMessage(role: "assistant", text: errorMsg, image: nil))
            return
        }
        asrText = ""
        asrPartial = ""
        let service = OpenClawASRService(apiKey: apiKey)
        self.asrService = service
        service.onPartialResult = { (text: String) in
            DispatchQueue.main.async { self.asrPartial = text }
        }
        service.onFinalResult = { (text: String) in
            DispatchQueue.main.async {
                self.asrText += text
                self.asrPartial = ""
            }
        }
        service.onError = { (error: String) in
            DispatchQueue.main.async {
                self.isListening = false
                print("[ASR] Error: \(error)")
            }
        }
        service.start()
        isListening = true
    }

    private func stopListening() {
        asrService?.stop()
        asrService = nil
        isListening = false
        asrPartial = ""
    }

    private func flushPendingResponse() {
        if !pendingResponse.isEmpty {
            messages.append(OpenClawChatMessage(role: "assistant", text: pendingResponse, image: nil))
            pendingResponse = ""
        }
    }
}

// MARK: - Chat Bubble

struct ChatBubble: View {
    let message: OpenClawChatMessage

    var body: some View {
        if message.role == "notice" {
            Text(message.text)
                .font(.system(size: 12))
                .foregroundColor(.orange)
                .padding(.horizontal, 12)
                .padding(.vertical, 6)
                .background(Color.orange.opacity(0.12))
                .cornerRadius(10)
                .frame(maxWidth: .infinity, alignment: .center)
        } else {
            HStack {
                if message.role == "user" { Spacer(minLength: 60) }

                VStack(alignment: message.role == "user" ? .trailing : .leading, spacing: 6) {
                    if let image = message.image {
                        Image(uiImage: image)
                            .resizable()
                            .aspectRatio(contentMode: .fill)
                            .frame(maxWidth: 200, maxHeight: 150)
                            .cornerRadius(12)
                            .clipped()
                    }

                    Text(message.text)
                        .font(.system(size: 15))
                        .foregroundColor(message.role == "user" ? .white : .primary)
                        .padding(.horizontal, 14)
                        .padding(.vertical, 10)
                        .background(
                            message.role == "user"
                                ? AnyShapeStyle(LinearGradient(colors: [.purple, .indigo], startPoint: .leading, endPoint: .trailing))
                                : AnyShapeStyle(Color(.systemGray5))
                        )
                        .cornerRadius(18)
                }

                if message.role == "assistant" { Spacer(minLength: 60) }
            }
        }
    }
}
