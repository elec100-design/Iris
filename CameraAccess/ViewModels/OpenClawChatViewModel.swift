/*
 * OpenClaw Chat ViewModel
 * 앱 주도 촬영 → 이미지 수신 → Gemini 분석 → TTS 출력
 * App-Initiated Visual AI Workflow
 */

import Foundation
import UIKit
import CoreLocation

import Network

// 앱이 켜지는 순간 로컬 네트워크 권한 팝업을 강제로 띄우는 완전 격리 코드
import Network

func forceTriggerLocalNetworkPopup() {
    let host = NWEndpoint.Host("255.255.255.255")
    // 🌟 에러 해결: 포트를 명확히 지정 (.any 또는 구체적인 포트 번호)
    let port = NWEndpoint.Port(integerLiteral: 80)
    
    let connection = NWConnection(host: host, port: port, using: .udp)
    
    // 🌟 에러 해결: state의 타입을 NWConnection.State로 명시
    connection.stateUpdateHandler = { (state: NWConnection.State) in
        print("⚡️ 강제 네트워크 노크 상태: \(state)")
    }
    
    // 🌟 에러 해결: DispatchQueue.main을 정확히 지정
    connection.start(queue: DispatchQueue.main)
}

@MainActor
class OpenClawChatViewModel: ObservableObject {

    // 🌟 Siri App Intent 연동을 위한 싱글톤 공유 인스턴스
    static var shared: OpenClawChatViewModel?

    @Published var isProcessing = false
    @Published var statusMessage = ""
    @Published var lastAnalysisResult = ""

    var onDescribeResult: ((String) -> Void)?

    private let service = OpenClawNodeService.shared
    private weak var streamViewModel: StreamSessionViewModel?

    init(streamViewModel: StreamSessionViewModel) {
        self.streamViewModel = streamViewModel
        // 🌟 앱 실행 시 초기화되면서 자신을 shared에 등록
        OpenClawChatViewModel.shared = self
    }

    // MARK: - App-Initiated Visual AI Session

    func startVisualAISession() async {
        guard !isProcessing else {
            print("[VisualAI] Already processing, skipping")
            return
        }
        isProcessing = true
        statusMessage = "준비 중..."
        lastAnalysisResult = ""

        let t0 = CFAbsoluteTimeGetCurrent()

        // ── Step 1: WSS 촬영 명령 전송 ──
        service.sendManualCaptureCommand()
        print("[VisualAI] [1/5] WSS 촬영 명령 전송 완료 (\(elapsed(t0)))")

        // ── Step 2: 스트림 활성화 및 프레임 수신 대기 ──
        statusMessage = "프레임 수신 대기..."
        guard let vm = streamViewModel else {
            fail("StreamViewModel 미초기화", t0: t0)
            return
        }

        if !vm.isStreaming {
            statusMessage = "스트림 시작 중..."
            await vm.handleStartStreaming()

            let deadline = Date().addingTimeInterval(5.0)
            while vm.currentVideoFrame == nil && Date() < deadline {
                try? await Task.sleep(nanoseconds: 200_000_000)
            }
        }

        guard let frame = vm.currentVideoFrame else {
            fail("프레임 수신 실패 (타임아웃 5초)", t0: t0)
            return
        }
        print("[VisualAI] [2/5] 프레임 수신 완료 \(Int(frame.size.width))x\(Int(frame.size.height)) (\(elapsed(t0)))")

        // ── Step 3: 이미지 리사이징 ──
        statusMessage = "이미지 최적화..."
        let resized = Self.resizeForAnalysis(frame, maxDimension: 1024)
        print("[VisualAI] [3/5] 리사이징 완료 \(Int(resized.size.width))x\(Int(resized.size.height)) (\(elapsed(t0)))")

        // ── Step 4: Gemini Vision API 호출 ──
        statusMessage = "AI 분석 중..."
        let visionService = QuickVisionService()
        let prompt = """
내가 레이반 메타 안경으로 지금 보고 있는 장면이야.
한국어로 자연스럽고 자세하게 설명해줘.
불필요한 변명이나 "이미지가 잘 안보인다" 같은 말은 절대 하지 말고,
바로 본론부터 설명해.
"""

        do {
            let result = try await visionService.analyzeImage(resized, customPrompt: prompt)
            print("[VisualAI] [4/5] AI 분석 완료: \(result.prefix(80))... (\(elapsed(t0)))")
            lastAnalysisResult = result

            // ── Step 5: TTS 출력 ──
            statusMessage = "음성 출력 중..."
            TTSService.shared.speak(result)
            print("[VisualAI] [5/5] TTS 출력 시작 (\(elapsed(t0)))")

            statusMessage = "완료"
        } catch {
            let msg = "AI 분석 실패: \(error.localizedDescription)"
            print("[VisualAI] [4/5] \(msg) (\(elapsed(t0)))")
            lastAnalysisResult = msg
            statusMessage = msg
        }

        isProcessing = false
    }

    // MARK: - Chat View Entry Points

    func captureAndDescribe() async {
        await startVisualAISession()
        if !lastAnalysisResult.isEmpty {
            onDescribeResult?(lastAnalysisResult)
        }
    }

    func captureAndTranslate() async {
        guard !isProcessing else { return }
        isProcessing = true
        statusMessage = "번역 준비 중..."
        lastAnalysisResult = ""

        let t0 = CFAbsoluteTimeGetCurrent()
        service.sendManualCaptureCommand()

        guard let vm = streamViewModel else {
            fail("StreamViewModel 미초기화", t0: t0)
            return
        }

        if !vm.isStreaming {
            statusMessage = "스트림 시작 중..."
            await vm.handleStartStreaming()
            let deadline = Date().addingTimeInterval(5.0)
            while vm.currentVideoFrame == nil && Date() < deadline {
                try? await Task.sleep(nanoseconds: 200_000_000)
            }
        }

        guard let frame = vm.currentVideoFrame else {
            fail("프레임 수신 실패", t0: t0)
            return
        }

        statusMessage = "번역 중..."
        let resized = Self.resizeForAnalysis(frame, maxDimension: 1024)
        let visionService = QuickVisionService()
        let prompt = """
내가 레이반 메타 안경으로 지금 보고 있는 장면이야.
사진 속 모든 텍스트를 찾아서 한국어로 번역해줘.
번역할 텍스트가 없으면 장면에 보이는 문자나 기호를 읽어줘.
불필요한 설명 없이 번역 결과만 바로 말해줘.
"""

        do {
            let result = try await visionService.analyzeImage(resized, customPrompt: prompt)
            lastAnalysisResult = result
            statusMessage = "음성 출력 중..."
            TTSService.shared.speak(result)
            statusMessage = "완료"
            onDescribeResult?(result)
        } catch {
            let msg = "번역 실패: \(error.localizedDescription)"
            lastAnalysisResult = msg
            statusMessage = msg
            onDescribeResult?(msg)
        }

        isProcessing = false
    }

    // MARK: - Siri Custom Command

    func processGeminiCommand(text: String) async {
        guard !isProcessing else { return }
        isProcessing = true
        statusMessage = "명령 처리 중..."
        lastAnalysisResult = ""

        let t0 = CFAbsoluteTimeGetCurrent()

        // Intent classification — no image needed for navigation
        if let intent = await classifyIntent(text: text),
           intent.type == "navigation",
           let dest = intent.destination {
            await GoogleMapsNavigator.shared.startVoiceNavigation(destination: dest)
            lastAnalysisResult = "\(dest) 네비게이션 시작"
            statusMessage = "네비게이션 시작"
            isProcessing = false
            return
        }

        guard let vm = streamViewModel else {
            fail("StreamViewModel 미초기화", t0: t0)
            return
        }

        if !vm.isStreaming {
            statusMessage = "스트림 시작 중..."
            await vm.handleStartStreaming()
            let deadline = Date().addingTimeInterval(5.0)
            while vm.currentVideoFrame == nil && Date() < deadline {
                try? await Task.sleep(nanoseconds: 200_000_000)
            }
        }

        guard let frame = vm.currentVideoFrame else {
            fail("프레임 수신 실패", t0: t0)
            return
        }

        statusMessage = "AI 분석 중..."
        let resized = Self.resizeForAnalysis(frame, maxDimension: 1024)
        let visionService = QuickVisionService()

        do {
            let result = try await visionService.analyzeImage(resized, customPrompt: text)
            lastAnalysisResult = result
            statusMessage = "음성 출력 중..."
            TTSService.shared.speak(result)
            statusMessage = "완료"
            print("[CustomCmd] 완료: \(result.prefix(80))... (\(elapsed(t0)))")
        } catch {
            let msg = "AI 분석 실패: \(error.localizedDescription)"
            lastAnalysisResult = msg
            statusMessage = msg
        }

        isProcessing = false
    }

    /// 자연어 명령을 Gemini에게 그대로 전달 — navigation 감지 포함
    func processNaturalCommand(text: String) async {
        await processGeminiCommand(text: text)
    }

    /// 설정된 AI 프로바이더로 직접 텍스트 채팅 (OpenClaw 서버 우회)
    func processTextChat(text: String, history: [OpenClawChatMessage]) async -> String {
        let apiKey = VisionAPIConfig.apiKey
        guard !apiKey.isEmpty else {
            return "❌ API 키가 설정되지 않았습니다. 설정 → 프로바이더에서 API 키를 입력해주세요."
        }
        guard let url = URL(string: "\(VisionAPIConfig.baseURL)/chat/completions") else {
            return "❌ API URL 설정 오류"
        }

        isProcessing = true
        statusMessage = "답변 생성 중..."
        defer {
            isProcessing = false
            statusMessage = ""
        }

        var requestMessages: [[String: Any]] = history.suffix(10).map {
            ["role": $0.role, "content": $0.text]
        }
        requestMessages.append(["role": "user", "content": text])

        var request = URLRequest(url: url)
        request.httpMethod = "POST"
        request.timeoutInterval = 30
        for (key, value) in VisionAPIConfig.headers(with: apiKey) {
            request.setValue(value, forHTTPHeaderField: key)
        }
        request.httpBody = try? JSONSerialization.data(withJSONObject: [
            "model": VisionAPIConfig.model,
            "messages": requestMessages
        ])

        guard let (data, _) = try? await URLSession.shared.data(for: request),
              let json = try? JSONSerialization.jsonObject(with: data) as? [String: Any],
              let choices = json["choices"] as? [[String: Any]],
              let message = choices.first?["message"] as? [String: Any],
              let content = message["content"] as? String
        else { return "❌ 응답을 받지 못했습니다. API 키와 모델 설정을 확인해주세요." }

        return content
    }

    // MARK: - Intent Classification

    struct IntentResponse: Decodable {
        let type: String
        let destination: String?
    }

    /// Text-only Gemini call to classify the user's intent before grabbing a frame.
    func classifyIntent(text: String) async -> IntentResponse? {
        let systemPrompt = """
사용자의 명령을 분석해서 JSON으로만 반환해:
{
  "type": "navigation" | "translation" | "telegram" | "analysis" | "chat",
  "destination": "목적지 문자열"
}
사용자 명령: \(text)
"""
        guard let url = URL(string: "\(VisionAPIConfig.baseURL)/chat/completions") else { return nil }

        var urlRequest = URLRequest(url: url)
        urlRequest.httpMethod = "POST"
        urlRequest.timeoutInterval = 15
        for (key, value) in VisionAPIConfig.headers(with: VisionAPIConfig.apiKey) {
            urlRequest.setValue(value, forHTTPHeaderField: key)
        }

        let body: [String: Any] = [
            "model": VisionAPIConfig.model,
            "messages": [["role": "user", "content": systemPrompt]]
        ]
        guard let httpBody = try? JSONSerialization.data(withJSONObject: body) else { return nil }
        urlRequest.httpBody = httpBody

        guard let (data, _) = try? await URLSession.shared.data(for: urlRequest) else { return nil }

        // Extract content string from choices[0].message.content
        guard
            let json = try? JSONSerialization.jsonObject(with: data) as? [String: Any],
            let choices = json["choices"] as? [[String: Any]],
            let message = choices.first?["message"] as? [String: Any],
            let content = message["content"] as? String
        else { return nil }

        // Strip possible markdown code fences before decoding
        let cleaned = content
            .trimmingCharacters(in: .whitespacesAndNewlines)
            .replacingOccurrences(of: "```json", with: "")
            .replacingOccurrences(of: "```", with: "")
            .trimmingCharacters(in: .whitespacesAndNewlines)

        guard let intentData = cleaned.data(using: .utf8) else { return nil }
        return try? JSONDecoder().decode(IntentResponse.self, from: intentData)
    }

    // MARK: - Helpers

    private func fail(_ reason: String, t0: CFAbsoluteTime) {
        print("[VisualAI] FAIL: \(reason) (\(elapsed(t0)))")
        lastAnalysisResult = "❌ \(reason)"
        statusMessage = reason
        isProcessing = false
    }

    private func elapsed(_ start: CFAbsoluteTime) -> String {
        String(format: "T+%.0fms", (CFAbsoluteTimeGetCurrent() - start) * 1000)
    }

    private static func resizeForAnalysis(_ image: UIImage, maxDimension: CGFloat) -> UIImage {
        let currentMax = max(image.size.width, image.size.height)
        guard currentMax > maxDimension else { return image }
        let scale = maxDimension / currentMax
        let newSize = CGSize(width: image.size.width * scale, height: image.size.height * scale)
        let renderer = UIGraphicsImageRenderer(size: newSize)
        return renderer.image { _ in image.draw(in: CGRect(origin: .zero, size: newSize)) }
    }
}
