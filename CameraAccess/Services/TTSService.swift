/*
 * TTS Service
 * 文本转语音服务 - 使用阿里云 qwen3-tts-flash API
 * 使用和 OmniRealtimeService 相同的 AVAudioEngine 方式播放
 */

import AVFoundation
import Foundation

@MainActor
class TTSService: NSObject, ObservableObject {
    static let shared = TTSService()
    
    @Published var isSpeaking = false
    
    private let baseURL = "https://dashscope.aliyuncs.com/api/v1/services/aigc/multimodal-generation/generation"
    private let model = "qwen3-tts-flash"
    
    // 根据当前语言设置获取语音
    private var voice: String {
        return LanguageManager.staticTtsVoice
    }
    
    // 根据当前语言设置获取语言类型
    private var languageType: String {
        return LanguageManager.staticApiLanguageCode
    }
    
    // 使用和 OmniRealtimeService 一样的 AVAudioEngine 方式
    private var playbackEngine: AVAudioEngine?
    private var playerNode: AVAudioPlayerNode?
    // 使用 Float32 标准格式，兼容 iOS 18+
    private let playbackFormat = AVAudioFormat(standardFormatWithSampleRate: 24000, channels: 1)
    private var isPlaybackEngineRunning = false
    
    private var currentTask: Task<Void, Never>?
    private var systemSynthesizer: AVSpeechSynthesizer?
    
    private override init() {
        super.init()
        setupPlaybackEngine()
    }
    
    // MARK: - Audio Engine Setup (和 OmniRealtimeService 一样)
    
    private func setupPlaybackEngine() {
        playbackEngine = AVAudioEngine()
        playerNode = AVAudioPlayerNode()
        
        guard let playbackEngine = playbackEngine,
              let playerNode = playerNode,
              let playbackFormat = playbackFormat else {
            print("❌ [TTS] 无法初始化播放引擎")
            return
        }
        
        playbackEngine.attach(playerNode)
        playbackEngine.connect(playerNode, to: playbackEngine.mainMixerNode, format: playbackFormat)
        playbackEngine.prepare()
        
        print("✅ [TTS] 播放引擎初始化完成: Float32 @ 24kHz")
    }
    
    /// 配置音频会话（需要在启动播放引擎之前调用）
    private func configureAudioSession() {
        do {
            let audioSession = AVAudioSession.sharedInstance()
            
            // 检查当前会话状态
            print("🔊 [TTS] 当前音频会话: category=\(audioSession.category.rawValue), mode=\(audioSession.mode.rawValue)")
            
            // 只在需要时配置，避免与现有会话冲突
            // 使用和 OmniRealtimeService 完全一样的设置（不要 defaultToSpeaker）
            try audioSession.setCategory(.playAndRecord, mode: .voiceChat, options: [.allowBluetoothHFP, .allowBluetoothA2DP])
            try audioSession.setPreferredSampleRate(24000)
            try audioSession.setActive(true, options: [.notifyOthersOnDeactivation])
            print("✅ [TTS] Audio session 已配置")
        } catch {
            print("⚠️ [TTS] Audio session 配置失败: \(error), 继续尝试播放...")
            // 不要抛出错误，尝试使用现有会话播放
        }
    }
    
    private func startPlaybackEngine() {
        guard let playbackEngine = playbackEngine, !isPlaybackEngineRunning else { return }
        
        configureAudioSession()
        do {
            try playbackEngine.start()
            playerNode?.play()
            isPlaybackEngineRunning = true
            print("✅ [TTS] 播放引擎已启动")
        } catch {
            print("❌ [TTS] 播放引擎启动失败: \(error)")
        }
    }
    
    private func stopPlaybackEngine() {
        playerNode?.stop()
        playerNode?.reset()
        playbackEngine?.stop()
        isPlaybackEngineRunning = false
    }
    
    // MARK: - API Request Models
    
    struct TTSRequest: Codable {
        let model: String
        let input: Input
        
        struct Input: Codable {
            let text: String
            let voice: String
            let language_type: String
        }
    }
    
    // MARK: - Public Methods
    
    /// 预配置音频会话（在停止流之前调用）
    func prepareAudioSession() {
        configureAudioSession()
        print("🔊 [TTS] 音频会话已预配置")
    }
    
    /// 播报文本
    /// - 阿里云 API：使用阿里云 qwen3-tts-flash
    /// - OpenRouter API：使用系统 TTS
    func speak(_ text: String, apiKey: String? = nil) {
        // 取消之前的任务
        currentTask?.cancel()
        stop()
        
        // OpenRouter: Google Cloud TTS 시도 → 실패 시 시스템 TTS
        if APIProviderManager.staticCurrentProvider == .openrouter {
            if let googleKey = APIKeyManager.shared.getGoogleAPIKey(), !googleKey.isEmpty {
                print("🔊 [TTS] OpenRouter mode → Google Cloud TTS")
                isSpeaking = true
                currentTask = Task {
                    do {
                        try await synthesizeWithGoogleTTS(text: text, apiKey: googleKey)
                    } catch {
                        if !Task.isCancelled {
                            print("❌ [TTS] Google TTS failed: \(error) → system TTS fallback")
                            await fallbackToSystemTTS(text: text)
                        }
                    }
                    if !Task.isCancelled { isSpeaking = false }
                }
            } else {
                print("🔊 [TTS] No Google API key → system TTS")
                isSpeaking = true
                currentTask = Task {
                    await fallbackToSystemTTS(text: text)
                    isSpeaking = false
                }
            }
            return
        }
        
        // 阿里云：使用阿里云 TTS
        let key = apiKey ?? APIKeyManager.shared.getAPIKey(for: .alibaba)
        
        guard let finalKey = key, !finalKey.isEmpty else {
            print("❌ [TTS] No Alibaba API key, falling back to system TTS")
            isSpeaking = true
            currentTask = Task {
                await fallbackToSystemTTS(text: text)
                isSpeaking = false
            }
            return
        }
        
        print("🔊 [TTS] Speaking with qwen3-tts-flash: \(text.prefix(50))...")
        
        isSpeaking = true
        
        currentTask = Task {
            do {
                try await synthesizeAndPlay(text: text, apiKey: finalKey)
            } catch {
                if !Task.isCancelled {
                    print("❌ [TTS] Error: \(error)")
                    // 失败时回退到系统 TTS
                    await fallbackToSystemTTS(text: text)
                }
            }
            if !Task.isCancelled {
                isSpeaking = false
            }
        }
    }
    
    /// Low-latency TTS: always uses system AVSpeechSynthesizer — no API round-trip.
    /// Ideal for continuous conversation mode where < 500ms response is required.
    func speakFast(_ text: String) {
        currentTask?.cancel()
        stop()
        isSpeaking = true
        currentTask = Task {
            await speakSystemFast(text: text)
            if !Task.isCancelled { isSpeaking = false }
        }
    }

    /// Pre-warm the system synthesizer to eliminate cold-start latency on first call.
    func prewarm() {
        if systemSynthesizer == nil {
            systemSynthesizer = AVSpeechSynthesizer()
        }
    }

    private func speakSystemFast(text: String) async {
        if systemSynthesizer == nil { systemSynthesizer = AVSpeechSynthesizer() }
        guard let synthesizer = systemSynthesizer else { return }

        do {
            let session = AVAudioSession.sharedInstance()
            try session.setCategory(.playback, mode: .default, options: [.duckOthers])
            try session.setActive(true)
        } catch {
            print("⚠️ [TTS Fast] Audio session: \(error)")
        }

        let utterance = AVSpeechUtterance(string: text)
        let voiceLanguage = LanguageManager.staticTtsLanguageCode
        if let voiceId = UserDefaults.standard.string(forKey: "tts_voice_identifier"),
           let savedVoice = AVSpeechSynthesisVoice(identifier: voiceId) {
            utterance.voice = savedVoice
        } else {
            utterance.voice = AVSpeechSynthesisVoice(language: voiceLanguage)
        }
        utterance.rate = min((UserDefaults.standard.object(forKey: "tts_rate") as? Float ?? 0.48) + 0.04, 0.60)
        utterance.pitchMultiplier = 1.05
        utterance.volume = 0.9

        synthesizer.speak(utterance)
        try? await Task.sleep(nanoseconds: 80_000_000)

        while synthesizer.isSpeaking {
            if Task.isCancelled {
                synthesizer.stopSpeaking(at: .immediate)
                systemSynthesizer = nil
                return
            }
            try? await Task.sleep(nanoseconds: 100_000_000)
        }
        systemSynthesizer = nil
    }

    /// 停止播报
    func stop() {
        currentTask?.cancel()
        currentTask = nil
        stopPlaybackEngine()
        isSpeaking = false
        print("🔊 [TTS] Stopped")
    }
    
    // MARK: - Private Methods

    /// Google Cloud TTS — Neural2 한국어 고품질 음성
    /// 응답: base64 PCM16 @ 24kHz → 기존 Alibaba 오디오 엔진 재사용
    private func synthesizeWithGoogleTTS(text: String, apiKey: String) async throws {
        let urlString = "https://texttospeech.googleapis.com/v1/text:synthesize?key=\(apiKey)"
        guard let url = URL(string: urlString) else { throw TTSError.invalidResponse }

        var request = URLRequest(url: url)
        request.httpMethod = "POST"
        request.setValue("application/json", forHTTPHeaderField: "Content-Type")
        request.timeoutInterval = 15

        let body: [String: Any] = [
            "input": ["text": text],
            "voice": [
                "languageCode": "ko-KR",
                "name": "ko-KR-Neural2-A"
            ],
            "audioConfig": [
                "audioEncoding": "LINEAR16",
                "sampleRateHertz": 24000
            ]
        ]
        request.httpBody = try JSONSerialization.data(withJSONObject: body)

        let (data, response) = try await URLSession.shared.data(for: request)

        guard let httpResponse = response as? HTTPURLResponse else {
            throw TTSError.invalidResponse
        }
        guard httpResponse.statusCode == 200 else {
            let body = String(data: data, encoding: .utf8) ?? ""
            print("❌ [TTS] Google TTS \(httpResponse.statusCode): \(body.prefix(300))")
            throw TTSError.apiError(statusCode: httpResponse.statusCode)
        }

        guard let json = try? JSONSerialization.jsonObject(with: data) as? [String: Any],
              let audioContent = json["audioContent"] as? String,
              let audioData = Data(base64Encoded: audioContent),
              !audioData.isEmpty else {
            throw TTSError.noAudioData
        }

        print("🔊 [TTS] Google TTS received \(audioData.count) bytes")

        playerNode?.stop()
        playerNode?.reset()
        if !isPlaybackEngineRunning { startPlaybackEngine() }
        playerNode?.play()

        guard isPlaybackEngineRunning else { throw TTSError.playbackFailed }

        playAudioChunk(audioData)
        await waitForPlaybackCompletion()
        print("🔊 [TTS] Google TTS finished")
    }

    private func synthesizeAndPlay(text: String, apiKey: String) async throws {
        guard let url = URL(string: baseURL) else {
            throw TTSError.invalidResponse
        }
        var request = URLRequest(url: url)
        request.httpMethod = "POST"
        request.setValue("Bearer \(apiKey)", forHTTPHeaderField: "Authorization")
        request.setValue("application/json", forHTTPHeaderField: "Content-Type")
        request.setValue("enable", forHTTPHeaderField: "X-DashScope-SSE")
        request.timeoutInterval = 30
        
        let ttsRequest = TTSRequest(
            model: model,
            input: TTSRequest.Input(
                text: text,
                voice: voice,
                language_type: languageType
            )
        )
        
        request.httpBody = try JSONEncoder().encode(ttsRequest)
        
        print("📡 [TTS] Sending request to qwen3-tts-flash...")
        
        // 使用 URLSession 的 bytes API 处理 SSE
        let (bytes, response) = try await URLSession.shared.bytes(for: request)
        
        guard let httpResponse = response as? HTTPURLResponse else {
            throw TTSError.invalidResponse
        }
        
        guard httpResponse.statusCode == 200 else {
            print("❌ [TTS] API error: \(httpResponse.statusCode)")
            throw TTSError.apiError(statusCode: httpResponse.statusCode)
        }
        
        // 停止当前播放并重置 playerNode 队列
        playerNode?.stop()
        playerNode?.reset()
        
        // 确保播放引擎在运行
        if !isPlaybackEngineRunning {
            startPlaybackEngine()
        }
        
        // 提前调用 play()，让 playerNode 准备好接收 buffer
        playerNode?.play()
        print("▶️ [TTS] 播放引擎和 playerNode 已就绪")
        
        guard isPlaybackEngineRunning else {
            print("❌ [TTS] 播放引擎未运行")
            throw TTSError.playbackFailed
        }
        
        var chunkCount = 0
        var totalBytes = 0
        
        for try await line in bytes.lines {
            if Task.isCancelled { return }
            
            // SSE 格式: "data: {...}"
            if line.hasPrefix("data:") {
                let jsonString = String(line.dropFirst(5)).trimmingCharacters(in: .whitespaces)
                
                if jsonString == "[DONE]" {
                    break
                }
                
                if let jsonData = jsonString.data(using: .utf8),
                   let json = try? JSONSerialization.jsonObject(with: jsonData) as? [String: Any],
                   let output = json["output"] as? [String: Any],
                   let audio = output["audio"] as? [String: Any],
                   let audioString = audio["data"] as? String,
                   !audioString.isEmpty,
                   let audioData = Data(base64Encoded: audioString),
                   !audioData.isEmpty {
                    chunkCount += 1
                    totalBytes += audioData.count
                    if chunkCount == 1 {
                        print("🔊 [TTS] 收到第一个音频片段: \(audioData.count) bytes")
                    }
                    // 流式播放每个音频片段
                    playAudioChunk(audioData)
                }
            }
        }
        
        if Task.isCancelled { return }
        
        print("🔊 [TTS] Received \(chunkCount) chunks, \(totalBytes) bytes total")
        
        // 等待播放完成
        await waitForPlaybackCompletion()
        
        print("🔊 [TTS] Finished playing")
    }
    
    private func playAudioChunk(_ audioData: Data) {
        // 跳过空数据
        guard !audioData.isEmpty else {
            return
        }
        
        guard let playerNode = playerNode,
              let playbackFormat = playbackFormat else {
            print("⚠️ [TTS] playerNode 或 playbackFormat 未初始化")
            return
        }
        
        guard let pcmBuffer = createPCMBuffer(from: audioData, format: playbackFormat) else {
            print("⚠️ [TTS] 无法创建 PCM buffer, audioData.count=\(audioData.count)")
            return
        }
        
        // 确保播放引擎运行中
        if !isPlaybackEngineRunning {
            startPlaybackEngine()
        }
        
        // 确保 playerNode 在播放状态（和 OmniRealtimeService 一致）
        if !playerNode.isPlaying {
            playerNode.play()
            print("▶️ [TTS] playerNode.play() 已调用")
        }
        
        // 调度音频缓冲区播放
        playerNode.scheduleBuffer(pcmBuffer)
    }
    
    private func createPCMBuffer(from data: Data, format: AVAudioFormat) -> AVAudioPCMBuffer? {
        // 服务器发送的是 PCM16 格式，每帧 2 字节
        let frameCount = data.count / 2
        guard frameCount > 0 else {
            print("⚠️ [TTS] createPCMBuffer: frameCount is 0, data.count=\(data.count)")
            return nil
        }
        
        guard let buffer = AVAudioPCMBuffer(pcmFormat: format, frameCapacity: AVAudioFrameCount(frameCount)) else {
            print("⚠️ [TTS] createPCMBuffer: Failed to create AVAudioPCMBuffer, format=\(format), frameCount=\(frameCount)")
            return nil
        }
        
        guard let channelData = buffer.floatChannelData else {
            print("⚠️ [TTS] createPCMBuffer: floatChannelData is nil")
            return nil
        }
        
        buffer.frameLength = AVAudioFrameCount(frameCount)
        
        // 将 PCM16 转换为 Float32（兼容 iOS 18+）
        data.withUnsafeBytes { (bytes: UnsafeRawBufferPointer) in
            guard let baseAddress = bytes.baseAddress else { return }
            let int16Pointer = baseAddress.assumingMemoryBound(to: Int16.self)
            let floatData = channelData[0]
            for i in 0..<frameCount {
                // Int16 范围 -32768 到 32767，转换为 -1.0 到 1.0
                floatData[i] = Float(int16Pointer[i]) / 32768.0
            }
        }
        
        return buffer
    }
    
    private func waitForPlaybackCompletion() async {
        guard let playerNode = playerNode else { return }
        
        // 等待所有音频播放完成
        while playerNode.isPlaying {
            if Task.isCancelled { return }
            try? await Task.sleep(nanoseconds: 100_000_000) // 0.1秒
        }
        
        // 额外等待确保完全播放
        try? await Task.sleep(nanoseconds: 300_000_000) // 0.3秒
    }
    
    /// 回退到系统 TTS
    /// 回退到系统 TTS (시스템 TTS로 읽어주기)
    private func fallbackToSystemTTS(text: String) async {
        print("🔊 [TTS] Falling back to system TTS")
        
        do {
            let audioSession = AVAudioSession.sharedInstance()
            try audioSession.setCategory(.playback, mode: .default, options: [.duckOthers])
            try audioSession.setActive(true)
        } catch {
            print("⚠️ [TTS] Audio session error: \(error)")
        }
        
        systemSynthesizer = AVSpeechSynthesizer()
        guard let synthesizer = systemSynthesizer else { return }
        
        let utterance = AVSpeechUtterance(string: text)
        
        let voiceLanguage = LanguageManager.staticTtsLanguageCode
        if let voiceId = UserDefaults.standard.string(forKey: "tts_voice_identifier"),
           let savedVoice = AVSpeechSynthesisVoice(identifier: voiceId) {
            utterance.voice = savedVoice
        } else {
            utterance.voice = AVSpeechSynthesisVoice(language: voiceLanguage)
        }

        utterance.rate = UserDefaults.standard.object(forKey: "tts_rate") as? Float ?? 0.48
        utterance.pitchMultiplier = 1.05
        utterance.volume = 0.9
        
        print("🔊 [TTS] System TTS speaking (\(voiceLanguage)): \(text.prefix(30))...")
        synthesizer.speak(utterance)
        
        try? await Task.sleep(nanoseconds: 100_000_000)
        
        while synthesizer.isSpeaking {
            if Task.isCancelled {
                synthesizer.stopSpeaking(at: .immediate)
                systemSynthesizer = nil
                return
            }
            try? await Task.sleep(nanoseconds: 100_000_000)
        }
        
        systemSynthesizer = nil
    }
}

// MARK: - Error Types

enum TTSError: LocalizedError {
    case noAPIKey
    case invalidResponse
    case apiError(statusCode: Int)
    case noAudioData
    case playbackFailed

    var errorDescription: String? {
        switch self {
        case .noAPIKey:
            return "未配置 API Key"
        case .invalidResponse:
            return "无效的响应"
        case .apiError(let statusCode):
            return "API 错误: \(statusCode)"
        case .noAudioData:
            return "未收到音频数据"
        case .playbackFailed:
            return "音频播放失败"
        }
    }
}
