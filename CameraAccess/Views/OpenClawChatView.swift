
import SwiftUI

enum AppMode {
    case idle, live, agent
}

struct OpenClawChatMessage: Identifiable {
    let id = UUID()
    let role: String
    var text: String
    let image: UIImage?
    let timestamp = Date()
}

struct OpenClawChatView: View {
    @ObservedObject var streamViewModel: StreamSessionViewModel
    @ObservedObject var openClawService = OpenClawNodeService.shared
    @StateObject private var visualAI: OpenClawChatViewModel
    @Environment(\.dismiss) private var dismiss

    @State private var messages: [OpenClawChatMessage] = []
    @State private var inputText = ""
    @State private var pendingResponse = ""

    // Dual-Mode State
    @State private var currentMode: AppMode = .idle
    @State private var isPulsing = false

    // History
    @State private var showHistorySheet = false

    // ASR
    @State private var isListening = false
    @State private var asrText = ""
    @State private var asrPartial = ""
    @State private var asrService: OpenClawASRService?

    init(streamViewModel: StreamSessionViewModel) {
        self.streamViewModel = streamViewModel
        _visualAI = StateObject(wrappedValue: OpenClawChatViewModel(streamViewModel: streamViewModel))
    }

    var body: some View {
        NavigationView {
            ZStack {
                // 1. 듀얼 모드 반응형 배경
                modeBackground

                VStack(spacing: 0) {
                    connectionBanner
                    messagesList
                    Divider()
                    
                    VStack(spacing: 16) {
                        // 처리 상태 및 ASR 텍스트 뷰
                        statusArea
                        
                        // 2. 새로운 듀얼 모드 핵심 컨트롤
                        dualModeControls
                        
                        // 3. 텍스트 입력창
                        textInputArea
                    }
                    .padding(.top, 10)
                    .padding(.bottom, 16)
                    .background(Color(.systemBackground).opacity(0.8))
                }
            }
            .navigationTitle("아이리스 (Iris)")
            .navigationBarTitleDisplayMode(.inline)
            .toolbar {
                ToolbarItem(placement: .navigationBarLeading) {
                    Button { dismiss() } label: { Image(systemName: "xmark") }
                }
                ToolbarItem(placement: .navigationBarTrailing) {
                    HStack(spacing: 10) {
                        Button { startNewConversation() } label: {
                            Image(systemName: "square.and.pencil").font(.system(size: 14))
                        }
                        Circle()
                            .fill(openClawService.connectionState == .connected ? Color.green : Color.gray)
                            .frame(width: 8, height: 8)
                        NavigationLink { OpenClawSettingsView() } label: {
                            Image(systemName: "gear").font(.system(size: 14))
                        }
                    }
                }
            }
        }
        .onAppear {
            setupHandlers()
            // 맥박 애니메이션 시작
            withAnimation(.easeInOut(duration: 1.0).repeatForever(autoreverses: true)) {
                isPulsing = true
            }
        }
        .onDisappear { cleanup() }
        .sheet(isPresented: $showHistorySheet) {
            ChatHistoryView { loadedMessages in
                saveCurrentSession()
                messages = loadedMessages
            }
        }
    }

    // MARK: - Sub-views

    @ViewBuilder
    private var modeBackground: some View {
        Group {
            switch currentMode {
            case .live:
                RadialGradient(gradient: Gradient(colors: [Color.red.opacity(0.25), Color(.systemBackground)]), center: .center, startRadius: 10, endRadius: 500)
                    .ignoresSafeArea()
            case .agent:
                RadialGradient(gradient: Gradient(colors: [Color.blue.opacity(0.25), Color(.systemBackground)]), center: .center, startRadius: 10, endRadius: 500)
                    .ignoresSafeArea()
            case .idle:
                Color(.systemBackground).ignoresSafeArea()
            }
        }
    }

    private var dualModeControls: some View {
        HStack(spacing: 40) {
            // 1. 아이리스 라이브 버튼 (Red)
            Button {
                toggleLiveMode()
            } label: {
                VStack(spacing: 8) {
                    Image(systemName: currentMode == .live ? "waveform.circle.fill" : "mic.circle.fill")
                        .font(.system(size: 50))
                    Text("Live")
                        .font(.headline)
                }
                .foregroundColor(currentMode == .live ? .red : .primary)
                .scaleEffect(currentMode == .live && isPulsing ? 1.05 : 1.0)
                .shadow(color: currentMode == .live ? .red.opacity(0.5) : .clear, radius: 10)
            }

            // 2. 에이전트 버튼 (Blue)
            Button {
                toggleAgentMode()
            } label: {
                VStack(spacing: 8) {
                    Image(systemName: "sparkles")
                        .font(.system(size: 50))
                    Text("에이전트")
                        .font(.headline)
                }
                .foregroundColor(currentMode == .agent ? .blue : .primary)
                .scaleEffect(currentMode == .agent && isPulsing ? 1.05 : 1.0)
                .shadow(color: currentMode == .agent ? .blue.opacity(0.5) : .clear, radius: 10)
            }
        }
        .padding(.vertical, 12)
        .padding(.horizontal, 30)
        .background(Color(.systemGray6).opacity(0.9))
        .cornerRadius(25)
    }

    @ViewBuilder
    private var statusArea: some View {
        if visualAI.isProcessing {
            HStack(spacing: 8) {
                ProgressView().scaleEffect(0.8)
                Text(visualAI.statusMessage).font(.system(size: 13)).foregroundColor(.secondary)
            }
        }
        
        if isListening || !asrText.isEmpty {
            VStack(alignment: .leading, spacing: 8) {
                Text(displayASRText)
                    .font(.system(size: 15))
                    .padding(12)
                    .frame(maxWidth: .infinity, alignment: .leading)
                    .background(Color(.systemGray5))
                    .cornerRadius(12)
                
                if !isListening && !asrText.isEmpty {
                    HStack(spacing: 12) {
                        Button {
                            asrText = ""
                            asrPartial = ""
                        } label: {
                            Text("cancel".localized).foregroundColor(.gray).frame(maxWidth: .infinity).padding(.vertical, 12).background(Color(.systemGray4)).cornerRadius(10)
                        }
                        Button { sendASRText() } label: {
                            Text("openclaw.chat.sendvoice".localized).foregroundColor(.white).frame(maxWidth: .infinity).padding(.vertical, 12).background(Color.purple).cornerRadius(10)
                        }
                    }
                }
            }
            .padding(.horizontal, 16)
        }
    }

    private var textInputArea: some View {
        HStack(spacing: 10) {
            TextField("아이리스에게 말하기...", text: $inputText)
                .textFieldStyle(.roundedBorder)
                .submitLabel(.send)
                .onSubmit { sendText() }

            Button { sendText() } label: {
                Image(systemName: "arrow.up.circle.fill")
                    .font(.system(size: 30))
                    .foregroundColor(inputText.isEmpty ? .gray : (currentMode == .agent ? .blue : .red))
            }
            .disabled(inputText.isEmpty || openClawService.connectionState != .connected)
        }
        .padding(.horizontal, 16)
    }

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
                }
                .padding()
            }
            .onChange(of: messages.count) {
                if let last = messages.last {
                    withAnimation { proxy.scrollTo(last.id, anchor: .bottom) }
                }
            }
        }
    }

    // MARK: - Computed

    private var displayASRText: String {
        if asrText.isEmpty && asrPartial.isEmpty {
            return isListening ? "openclaw.chat.listening".localized : ""
        }
        return asrText + (asrPartial.isEmpty ? "" : asrPartial)
    }

    // MARK: - Mode Toggles
    
    private func toggleLiveMode() {
        withAnimation {
            if currentMode == .live {
                currentMode = .idle
                // TODO: LiveAIManager.shared.stopLiveSession()
            } else {
                currentMode = .live
                // TODO: LiveAIManager.shared.startLiveSession()
            }
        }
    }

    private func toggleAgentMode() {
        withAnimation {
            currentMode = (currentMode == .agent) ? .idle : .agent
            // 에이전트 모드 활성화 시 필요한 로직 추가
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
        flushPendingResponse()
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

    private func sendText() {
        let text = inputText.trimmingCharacters(in: .whitespacesAndNewlines)
        guard !text.isEmpty else { return }
        messages.append(OpenClawChatMessage(role: "user", text: text, image: nil))
        flushPendingResponse()
        inputText = ""
        openClawService.sendChatMessage(text)
    }

    // MARK: - Voice (ASR)

    private func startListening() {
        guard let apiKey = APIKeyManager.shared.getAPIKey(for: .openrouter), !apiKey.isEmpty else {
            messages.append(OpenClawChatMessage(role: "assistant", text: NSLocalizedString("livetranslate.error.noApiKey", comment: ""), image: nil))
            return
        }
        asrText = ""
        asrPartial = ""
        let service = OpenClawASRService(apiKey: apiKey)
        self.asrService = service
        service.onPartialResult = { text in DispatchQueue.main.async { self.asrPartial = text } }
        service.onFinalResult = { text in DispatchQueue.main.async { self.asrText += text; self.asrPartial = "" } }
        service.onError = { error in DispatchQueue.main.async { self.isListening = false; print("[ASR] Error: \(error)") } }
        service.start()
        isListening = true
    }

    private func stopListening() {
        asrService?.stop()
        asrService = nil
        isListening = false
        asrPartial = ""
    }

    private func sendASRText() {
        let text = asrText.trimmingCharacters(in: .whitespacesAndNewlines)
        guard !text.isEmpty else { return }
        messages.append(OpenClawChatMessage(role: "user", text: text, image: nil))
        flushPendingResponse()
        openClawService.sendChatMessage(text)
        asrText = ""
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
        HStack {
            if message.role == "user" { Spacer(minLength: 60) }
            VStack(alignment: message.role == "user" ? .trailing : .leading, spacing: 6) {
                if let image = message.image {
                    Image(uiImage: image).resizable().aspectRatio(contentMode: .fill).frame(maxWidth: 200, maxHeight: 150).cornerRadius(12).clipped()
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
