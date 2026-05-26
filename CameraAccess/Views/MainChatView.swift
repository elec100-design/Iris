/*
 * MainChatView — Iris Dual-Mode Root View
 * 아이리스 라이브 (Live AI) vs 에이전트 (Apple ASR/Flash) 통합 및 TTS 오디오 통제 마스터본
 */

import SwiftUI
import AVFoundation
import Speech
import MediaPlayer
import PhotosUI
import UniformTypeIdentifiers

struct MainChatView: View {
    // 듀얼 모드 상태 정의
    enum AppMode {
        case idle, live, agent
    }

    @ObservedObject var streamViewModel: StreamSessionViewModel
    @ObservedObject var wearablesViewModel: WearablesViewModel
    @ObservedObject private var openClawService = OpenClawNodeService.shared
    @StateObject private var visualAI: OpenClawChatViewModel

    // 통합 대화 배열
    @State private var messages: [OpenClawChatMessage] = []
    
    // UI 및 네비게이션 상태
    @State private var inputText = ""
    @State private var pendingResponse = ""
    @State private var showSettings = false
    @State private var showHistorySheet = false
    @State private var showFileImporter = false
    
    // 듀얼 모드 관리자
    @ObservedObject private var liveAI = LiveAIManager.shared
    @State private var currentMode: AppMode = .idle
    @State private var isPulsing = false

    // 에이전트 모드 (Apple 내장 음성 인식)
    @State private var isListeningAgent = false
    @State private var asrText = ""
    @State private var asrPartial = ""
    @State private var speechRecognizer = SFSpeechRecognizer(locale: Locale(identifier: "ko-KR"))
    @State private var recognitionRequest: SFSpeechAudioBufferRecognitionRequest?
    @State private var recognitionTask: SFSpeechRecognitionTask?
    @State private var audioEngine = AVAudioEngine()
    
    // 에이전트 침묵 감지 자동 전송 타이머
    @State private var silenceTimer: Timer?
    
    // 에이전트 음성 출력용 TTS
    private let synthesizer = AVSpeechSynthesizer()

    private var apiKey: String { APIKeyManager.shared.getAPIKey() ?? "" }

    init(streamViewModel: StreamSessionViewModel, wearablesViewModel: WearablesViewModel) {
        self.streamViewModel = streamViewModel
        self.wearablesViewModel = wearablesViewModel
        _visualAI = StateObject(wrappedValue: OpenClawChatViewModel(streamViewModel: streamViewModel))
    }

    var body: some View {
        NavigationStack {
            ZStack {
                // 상태별 반응형 테마 배경 (Red / Blue Glow)
                modeBackground

                VStack(spacing: 0) {
                    connectionBanner
                    messagesList // 말풍선 대화창 리스트
                    Divider()
                    bottomControls // 하단 제어 바
                }
            }
            .navigationTitle("아이리스")
            .navigationBarTitleDisplayMode(.inline)
            .toolbar {
                // 새 채팅창 버튼
                ToolbarItem(placement: .topBarLeading) {
                    Button { startNewConversation() } label: {
                        Image(systemName: "square.and.pencil").font(.system(size: 14))
                    }
                }
                // 연결 상태 및 설정 버튼
                ToolbarItemGroup(placement: .topBarTrailing) {
                    Circle()
                        .fill(openClawService.connectionState == .connected ? Color.green : Color.gray)
                        .frame(width: 8, height: 8)
                    Button { showSettings = true } label: {
                        Image(systemName: "gear").font(.system(size: 14))
                    }
                }
            }
        }
        .sheet(isPresented: $showSettings) {
            SettingsView(streamViewModel: streamViewModel, apiKey: apiKey)
        }
        // 대화 기록 시트
        .sheet(isPresented: $showHistorySheet) {
            ChatHistoryView { loadedMessages in
                saveCurrentSession()
                messages = loadedMessages
            }
        }
        .onAppear {
            setupHandlers()
            setupRemoteCommandCenter() // 안경 터치패드 리모컨 활성화
            withAnimation(.easeInOut(duration: 1.0).repeatForever(autoreverses: true)) {
                isPulsing = true
            }
        }
        .onDisappear {
            cleanup()
        }
        
        // 아이리스 라이브 상태 연동
        .onChange(of: liveAI.isRunning) {
            if liveAI.isRunning { currentMode = .live }
            else if currentMode == .live { currentMode = .idle }
        }
        
        // 시리(Siri) 단축어 구동 신호 감지
        .onReceive(NotificationCenter.default.publisher(for: .voiceAgentRequestsListening)) { _ in
            if !liveAI.isRunning {
                currentMode = .live
                Task { await liveAI.startLiveAISession() }
            }
        }
        .onReceive(NotificationCenter.default.publisher(for: NSNotification.Name("agentRequestsListening"))) { _ in
            if currentMode != .agent { toggleAgentMode() }
        }
        
        // 아이리스 라이브 대화 로깅 동기화
        .onReceive(NotificationCenter.default.publisher(for: .voiceAgentDidUpdateMessages)) { _ in
            let liveMessages = ConversationMemory.shared.currentMessages
            for siriMsg in liveMessages {
                let roleStr = String(describing: siriMsg.role).lowercased().contains("user") ? "user" : "assistant"
                let msgText = siriMsg.content
                
                if !messages.contains(where: { $0.text == msgText && $0.role == roleStr }) {
                    DispatchQueue.main.async {
                        messages.append(OpenClawChatMessage(role: roleStr, text: msgText, image: nil))
                    }
                }
            }
        }
    }

    // MARK: - UI Components

    @ViewBuilder
    private var modeBackground: some View {
        Group {
            switch currentMode {
            case .live:
                RadialGradient(gradient: Gradient(colors: [Color.red.opacity(0.15), Color(.systemBackground)]), center: .bottom, startRadius: 10, endRadius: 600).ignoresSafeArea()
            case .agent:
                RadialGradient(gradient: Gradient(colors: [Color.blue.opacity(0.15), Color(.systemBackground)]), center: .bottom, startRadius: 10, endRadius: 600).ignoresSafeArea()
            case .idle:
                Color(.systemBackground).ignoresSafeArea()
            }
        }
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
                        // [기능 추가] 말풍선을 누를 때마다 읽기 / 중단이 토글되도록 처리
                        ChatBubble(message: msg)
                            .id(msg.id)
                            .contentShape(Rectangle())
                            .onTapGesture {
                                toggleSpeech(for: msg.text)
                            }
                    }
                    if !pendingResponse.isEmpty {
                        ChatBubble(message: OpenClawChatMessage(role: "assistant", text: pendingResponse, image: nil))
                    }
                    Color.clear.frame(height: 1).id("chat_bottom")
                }
                .padding()
            }
            .onChange(of: messages.count) { withAnimation { proxy.scrollTo("chat_bottom") } }
        }
    }

    private var bottomControls: some View {
        VStack(spacing: 12) {
            if visualAI.isProcessing {
                HStack(spacing: 8) {
                    ProgressView().scaleEffect(0.8)
                    Text(visualAI.statusMessage).font(.system(size: 13)).foregroundColor(.secondary)
                }
                .frame(maxWidth: .infinity)
                .padding(.horizontal, 16).padding(.vertical, 4)
            }

            if currentMode == .live || liveAI.isRunning {
                listeningIndicator(text: "아이리스 라이브 스트리밍 중...", color: .red)
            }

            if isListeningAgent || !asrText.isEmpty {
                agentASRPreviewArea
            }

            // 듀얼 모드 통합 액션 바
            HStack(spacing: 20) {
                Spacer()
                // 버튼 1: 아이리스 라이브 (Red)
                Button { Task { await toggleLiveMode() } } label: {
                    VStack(spacing: 6) {
                        Image(systemName: currentMode == .live ? "waveform.circle.fill" : "mic.circle.fill").font(.system(size: 45))
                        Text("Live").font(.caption).fontWeight(.bold)
                    }
                    .foregroundColor(currentMode == .live ? .red : .white)
                    .scaleEffect(currentMode == .live && isPulsing ? 1.05 : 1.0)
                    .shadow(color: currentMode == .live ? .red.opacity(0.5) : .clear, radius: 10)
                }

                Spacer()
                // 버튼 2: 에이전트 호출 및 읽기 중단 제어 (Blue)
                Button { toggleAgentMode() } label: {
                    VStack(spacing: 6) {
                        // AI가 떠들고 있을 때는 정지 모양 아이콘(stop.fill)으로 변형해 시각적 피드백 제공
                        Image(systemName: synthesizer.isSpeaking ? "stop.fill" : (currentMode == .agent ? "sparkles" : "sparkles")).font(.system(size: 45))
                        Text(synthesizer.isSpeaking ? "정지" : "에이전트").font(.caption).fontWeight(.bold)
                    }
                    .foregroundColor(synthesizer.isSpeaking ? .orange : (currentMode == .agent ? .blue : .white))
                    .scaleEffect(currentMode == .agent && isPulsing ? 1.05 : 1.0)
                    .shadow(color: currentMode == .agent ? .blue.opacity(0.5) : .clear, radius: 10)
                }

                Spacer()
                // 버튼 3: 대화 기록 열기
                Button { showHistorySheet = true } label: {
                    VStack(spacing: 6) {
                        Image(systemName: "clock.arrow.circlepath").font(.system(size: 30))
                        Text("대화 기록").font(.caption2)
                    }
                    .foregroundColor(.white)
                }
                Spacer()
            }
            .frame(maxWidth: .infinity)
            .padding(.vertical, 16)
            .background(Color.black.opacity(0.85))
            .cornerRadius(24)
            .padding(.horizontal, 16)

            // 텍스트 입력 영역
            VStack(spacing: 8) {
                // [기능 추가] 사진 미리보기 썸네일
                if let image = visualAI.attachedImage {
                    HStack {
                        Image(uiImage: image)
                            .resizable()
                            .scaledToFill()
                            .frame(width: 60, height: 60)
                            .cornerRadius(8)
                            .overlay(alignment: .topTrailing) {
                                Button {
                                    visualAI.attachedImage = nil
                                    visualAI.selectedPhotoItem = nil
                                } label: {
                                    Image(systemName: "xmark.circle.fill").foregroundColor(.white).background(Color.black.opacity(0.5)).clipShape(Circle())
                                }
                                .offset(x: 5, y: -5)
                            }
                        Spacer()
                    }
                    .padding(.horizontal, 16)
                }
                
                // [기능 추가] 문서 파일 미리보기
                if let fileURL = visualAI.attachedFileURL {
                    HStack {
                        Image(systemName: "doc.text.fill").font(.system(size: 30)).foregroundColor(.blue)
                        Text(fileURL.lastPathComponent).font(.caption).lineLimit(1)
                        Button {
                            visualAI.attachedFileURL = nil
                        } label: {
                            Image(systemName: "xmark.circle.fill").foregroundColor(.gray)
                        }
                    }
                    .padding(8).background(Color(.systemGray6)).cornerRadius(8).padding(.horizontal, 16)
                }

                HStack(spacing: 10) {
                    // [기능 추가] 파일 및 사진 추가 버튼
                    PhotosPicker(selection: $visualAI.selectedPhotoItem, matching: .images) {
                        Image(systemName: "photo.badge.plus").font(.system(size: 24)).foregroundColor(.gray)
                    }
                    
                    Button { showFileImporter = true } label: {
                        Image(systemName: "doc.badge.plus").font(.system(size: 24)).foregroundColor(.gray)
                    }

                    TextField(currentMode == .live ? "🎤 아이리스와 대화 중..." : "아이리스에게 말하기...", text: $inputText)
                        .textFieldStyle(.roundedBorder)
                        .submitLabel(.send)
                        .onSubmit { sendText() }
                        .disabled(visualAI.isAnalyzing)

                    if visualAI.isAnalyzing {
                        ProgressView().padding(.horizontal, 4)
                    } else {
                        Button { sendText() } label: {
                            Image(systemName: "arrow.up.circle.fill")
                                .font(.system(size: 30))
                                .foregroundColor(inputText.isEmpty && visualAI.attachedImage == nil && visualAI.attachedFileURL == nil ? .gray : (currentMode == .agent ? .blue : .red))
                        }
                        .disabled(inputText.isEmpty && visualAI.attachedImage == nil && visualAI.attachedFileURL == nil)
                    }
                }
                .padding(.horizontal, 16)
            }
            .fileImporter(isPresented: $showFileImporter, allowedContentTypes: [.plainText, .pdf]) { result in
                switch result {
                case .success(let url):
                    _ = url.startAccessingSecurityScopedResource()
                    visualAI.attachedFileURL = url
                    // Note: 파일을 전송하거나 사용한 후에는 아래 코드를 반드시 호출해야 함:
                    // url.stopAccessingSecurityScopedResource()
                case .failure(let error): print(error)
                }
            }
            .padding(.bottom, 8)
        }
        .padding(.vertical, 10)
        .background(Color(.systemBackground).opacity(0.9))
    }

    private func listeningIndicator(text: String, color: Color) -> some View {
        HStack(spacing: 8) {
            Image(systemName: "waveform").foregroundColor(color)
            Text(text).font(.system(size: 14)).foregroundColor(.secondary)
        }
        .frame(maxWidth: .infinity, alignment: .leading)
        .padding(.horizontal, 16).padding(.vertical, 4)
    }

    private var agentASRPreviewArea: some View {
        VStack(alignment: .leading, spacing: 8) {
            Text(displayASRText)
                .font(.system(size: 15))
                .foregroundColor(.blue)
                .padding(12)
                .frame(maxWidth: .infinity, alignment: .leading)
                .background(Color(.systemGray6))
                .cornerRadius(12)
            
            if !isListeningAgent && !asrText.isEmpty {
                HStack(spacing: 12) {
                    Button {
                        asrText = ""
                        asrPartial = ""
                        currentMode = .idle
                    } label: {
                        Text("취소").foregroundColor(.gray).frame(maxWidth: .infinity).padding(.vertical, 12).background(Color(.systemGray5)).cornerRadius(10)
                    }
                    Button { sendASRTextToAgent() } label: {
                        Text("지시하기").bold().foregroundColor(.white).frame(maxWidth: .infinity).padding(.vertical, 12).background(Color.blue).cornerRadius(10)
                    }
                }
            }
        }
        .padding(.horizontal, 16)
    }

    private var displayASRText: String {
        if asrText.isEmpty && asrPartial.isEmpty { return isListeningAgent ? "에이전트가 듣고 있습니다..." : "" }
        return asrText + (asrPartial.isEmpty ? "" : asrPartial)
    }

    // MARK: - 안경 터치패드 리모컨 제어

    private func setupRemoteCommandCenter() {
        let commandCenter = MPRemoteCommandCenter.shared()
        
        commandCenter.playCommand.isEnabled = true
        commandCenter.playCommand.addTarget { _ in
            Task { @MainActor in if currentMode != .live { await toggleLiveMode() } }
            return .success
        }
        
        commandCenter.pauseCommand.isEnabled = true
        commandCenter.pauseCommand.addTarget { _ in
            Task { @MainActor in if currentMode == .live { await toggleLiveMode() } }
            return .success
        }
        
        commandCenter.nextTrackCommand.isEnabled = true
        commandCenter.nextTrackCommand.addTarget { _ in
            DispatchQueue.main.async {
                if isListeningAgent {
                    autoSendAgentCommand()
                } else {
                    toggleAgentMode()
                }
            }
            return .success
        }
    }

    // MARK: - Dual Mode Toggles & Logic

    private func toggleLiveMode() async {
        withAnimation {
            if currentMode == .live {
                currentMode = .idle
                Task { await liveAI.stopSession() }
            } else {
                currentMode = .live
                if isListeningAgent { stopAgentListening() }
                if synthesizer.isSpeaking { synthesizer.stopSpeaking(at: .immediate) }
                Task { await liveAI.startLiveAISession() }
            }
        }
    }

    // [기능 개편] 에이전트 버튼 액션 분기
    private func toggleAgentMode() {
        // 중요: 에이전트가 현재 긴 대화를 읽고 있는 중이라면, 모드 변경 대신 읽기 강제 정지 처리!
        if synthesizer.isSpeaking {
            synthesizer.stopSpeaking(at: .immediate)
            return
        }
        
        withAnimation {
            if currentMode == .agent {
                currentMode = .idle
                stopAgentListening()
            } else {
                currentMode = .agent
                if liveAI.isRunning { Task { await liveAI.stopSession() } }
                startAgentListening()
            }
        }
    }

    // MARK: - Apple 네이티브 음성 인식 및 침묵 감지

    private func startAgentListening() {
        guard let recognizer = speechRecognizer, recognizer.isAvailable else {
            receiveAgentResponse("음성 인식을 사용할 수 없는 환경입니다.")
            return
        }
        if recognitionTask != nil {
            recognitionTask?.cancel()
            recognitionTask = nil
        }
        
        silenceTimer?.invalidate()
        let audioSession = AVAudioSession.sharedInstance()
        try? audioSession.setCategory(.playAndRecord, mode: .default, options: [.allowBluetoothHFP, .allowBluetoothA2DP])
        try? audioSession.setActive(true, options: .notifyOthersOnDeactivation)
        
        let inputNode = audioEngine.inputNode
        inputNode.removeTap(onBus: 0)
        
        recognitionRequest = SFSpeechAudioBufferRecognitionRequest()
        guard let recognitionRequest = recognitionRequest else { return }
        recognitionRequest.shouldReportPartialResults = true
        
        let recordingFormat = inputNode.outputFormat(forBus: 0)
        inputNode.installTap(onBus: 0, bufferSize: 1024, format: recordingFormat) { buffer, _ in
            self.recognitionRequest?.append(buffer)
        }
        
        audioEngine.prepare()
        try? audioEngine.start()
        
        asrText = ""
        isListeningAgent = true
        
        recognitionTask = recognizer.recognitionTask(with: recognitionRequest) { result, error in
            var isFinal = false
            if let result = result {
                DispatchQueue.main.async {
                    self.asrText = result.bestTranscription.formattedString
                    isFinal = result.isFinal
                    
                    // 침묵 감지 자동 전송 (1.5초 타이머)
                    self.silenceTimer?.invalidate()
                    self.silenceTimer = Timer.scheduledTimer(withTimeInterval: 1.5, repeats: false) { _ in
                        self.autoSendAgentCommand()
                    }
                }
            }
            if error != nil || isFinal {
                self.stopAgentListening()
            }
        }
    }

    private func stopAgentListening() {
        silenceTimer?.invalidate()
        silenceTimer = nil
        if audioEngine.isRunning {
            audioEngine.stop()
            audioEngine.inputNode.removeTap(onBus: 0)
        }
        recognitionRequest?.endAudio()
        recognitionTask?.cancel()
        recognitionRequest = nil
        recognitionTask = nil
        isListeningAgent = false
        asrPartial = ""
    }

    private func autoSendAgentCommand() {
        stopAgentListening()
        sendASRTextToAgent()
    }

    private func sendASRTextToAgent() {
        let text = asrText.trimmingCharacters(in: .whitespacesAndNewlines)
        guard !text.isEmpty else { return }
        asrText = ""
        currentMode = .idle
        processAgentCommand(text)
    }

    // 에이전트 지능형 라우터 및 "사진 촬영 전송" 처리 파이프라인
    // 기존 동작을 유지하는 원본 함수
    private func processAgentCommand(_ command: String) {
        let historySnapshot = Array(messages.suffix(10))
        messages.append(OpenClawChatMessage(role: "user", text: command, image: nil))
        flushPendingResponse()

        let lowerCmd = command.lowercased()

        if lowerCmd.contains("사진 촬영 전송") || lowerCmd.contains("사진촬영전송") || lowerCmd.contains("사진 촬영") {
            if lowerCmd.contains("번역") {
                Task { await visualAI.captureAndTranslate() }
            } else {
                Task { await visualAI.captureAndDescribe() }
            }
        } else if lowerCmd.contains("길찾기") || lowerCmd.contains("안내") {
            let dest = command.replacingOccurrences(of: "길찾기", with: "").replacingOccurrences(of: "안내해줘", with: "").trimmingCharacters(in: .whitespacesAndNewlines)
            if !dest.isEmpty {
                Task {
                    let result = await GoogleMapsNavigator.shared.openWithNaturalLanguage(text: dest)
                    receiveAgentResponse(result)
                }
            } else {
                receiveAgentResponse("어디로 안내할까요? 목적지를 말씀해 주세요.")
            }
        } else if openClawService.connectionState == .connected {
            openClawService.sendChatMessage(command)
        } else {
            messages.append(OpenClawChatMessage(role: "notice", text: "⚠️ 맥미니 미연결 — 외부 AI로 응답합니다", image: nil))
            Task {
                let response = await visualAI.processTextChat(text: command, history: historySnapshot)
                receiveAgentResponse(response)
            }
        }
    }

    // 기능 확장용 오버로딩 함수 (기존 코드 영향 없음)
    private func processAgentCommand(_ command: String, image: UIImage) {
        messages.append(OpenClawChatMessage(role: "user", text: command, image: image))
        flushPendingResponse()
        
        Task {
            let response = await visualAI.processImageChat(image: image, text: command)
            receiveAgentResponse(response)
        }
    }

    private func receiveAgentResponse(_ text: String) {
        let clean = visualAI.sanitizeResponse(text)
        messages.append(OpenClawChatMessage(role: "assistant", text: clean, image: nil))
        speakText(clean)
    }

    // [기능 개편] 말풍선 터치 대응 및 TTS 관리 전용 함수
    private func toggleSpeech(for text: String) {
        if synthesizer.isSpeaking {
            // 재생 중일 때 터치하면 즉시 무조건 정지!
            synthesizer.stopSpeaking(at: .immediate)
        } else {
            // 조용할 때 터치하면 해당 텍스트를 처음부터 재생
            speakText(text)
        }
    }

    private func speakText(_ text: String) {
        if synthesizer.isSpeaking {
            synthesizer.stopSpeaking(at: .immediate)
        }
        let cleanText = text.replacingOccurrences(of: "*", with: "").replacingOccurrences(of: "#", with: "")
        let utterance = AVSpeechUtterance(string: cleanText)
        utterance.voice = AVSpeechSynthesisVoice(language: "ko-KR")
        synthesizer.speak(utterance)
    }

    // MARK: - 영구 저장 및 핸들러 관리

    private func setupHandlers() {
        LiveAIManager.shared.setStreamViewModel(streamViewModel)

        openClawService.onChatEvent = { (text: String) in
            if text.hasPrefix("[[FINAL]]") {
                let fullText = String(text.dropFirst(9))
                pendingResponse = ""
                if !fullText.isEmpty {
                    messages.append(OpenClawChatMessage(role: "assistant", text: fullText, image: nil))
                    if let lastIndex = messages.indices.last {
                        let rawText = messages[lastIndex].text
                        messages[lastIndex].text = visualAI.sanitizeResponse(rawText)
                    }
                    speakText(messages.last?.text ?? "")
                }
            } else {
                pendingResponse = text
            }
        }
        visualAI.onDescribeResult = { result in
            receiveAgentResponse(result)
        }
        if openClawService.connectionState != .connected, openClawService.loadGatewayToken() != nil {
            openClawService.connect()
        }
    }

    private func cleanup() {
        liveAI.triggerStop()
        stopAgentListening()
        flushPendingResponse()
        saveCurrentSession()
        openClawService.onChatEvent = nil
        visualAI.onDescribeResult = nil
        synthesizer.stopSpeaking(at: .immediate)
    }

    private func saveCurrentSession() {
        guard !messages.isEmpty else { return }
        OpenClawSessionStorage.shared.saveSession(messages: messages)
    }

    private func startNewConversation() {
        saveCurrentSession()
        messages = []
        pendingResponse = ""
    }

    private func sendText() {
        let text = inputText.trimmingCharacters(in: .whitespacesAndNewlines)
        guard !text.isEmpty || visualAI.attachedImage != nil else { return }
        
        inputText = ""
        
        if let image = visualAI.attachedImage {
            processAgentCommand(text, image: image)
            visualAI.attachedImage = nil
            visualAI.selectedPhotoItem = nil
        } else {
            processAgentCommand(text)
        }
    }

    private func flushPendingResponse() {
        if !pendingResponse.isEmpty {
            messages.append(OpenClawChatMessage(role: "assistant", text: pendingResponse, image: nil))
            pendingResponse = ""
        }
    }
}
