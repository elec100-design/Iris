/*
 * Quick Vision Intent
 * App Intent - Siri 및 단축어를 통해 안경 촬영 및 AI 분석 실행
 */

import AppIntents
import Observation
import UIKit
import SwiftUI

// MARK: - 1. Siri 인텐트 정의 (각 모드별)

@available(iOS 16.0, *)
struct QuickVisionIntent: AppIntent {
    static var title: LocalizedStringResource = "터보 분석"
    static var description = IntentDescription("안경으로 사진을 찍고 내용을 분석합니다.")
    static var openAppWhenRun: Bool = false

    @Parameter(title: "사용자 지정 프롬프트")
    var customPrompt: String?

    @MainActor
    func perform() async throws -> some IntentResult & ProvidesDialog {
        let manager = QuickVisionManager.shared
        await manager.performQuickVisionWithMode(.standard, customPrompt: customPrompt)
        return formatResult(manager)
    }
}

@available(iOS 16.0, *)
struct QuickVisionHealthIntent: AppIntent {
    static var title: LocalizedStringResource = "건강 분석"
    static var description = IntentDescription("음식의 건강도를 분석합니다.")
    static var openAppWhenRun: Bool = false

    @MainActor
    func perform() async throws -> some IntentResult & ProvidesDialog {
        let manager = QuickVisionManager.shared
        await manager.performQuickVisionWithMode(.health)
        return formatResult(manager)
    }
}

@available(iOS 16.0, *)
struct QuickVisionBlindIntent: AppIntent {
    static var title: LocalizedStringResource = "주변 환경 묘사"
    static var description = IntentDescription("눈앞의 환경을 상세히 설명합니다.")
    static var openAppWhenRun: Bool = false

    @MainActor
    func perform() async throws -> some IntentResult & ProvidesDialog {
        let manager = QuickVisionManager.shared
        await manager.performQuickVisionWithMode(.blind)
        return formatResult(manager)
    }
}

@available(iOS 16.0, *)
struct QuickVisionReadingIntent: AppIntent {
    static var title: LocalizedStringResource = "텍스트 읽어주기"
    static var description = IntentDescription("이미지 속 문자를 읽어줍니다.")
    static var openAppWhenRun: Bool = false

    @MainActor
    func perform() async throws -> some IntentResult & ProvidesDialog {
        let manager = QuickVisionManager.shared
        await manager.performQuickVisionWithMode(.reading)
        return formatResult(manager)
    }
}

@available(iOS 16.0, *)
struct QuickVisionTranslateIntent: AppIntent {
    static var title: LocalizedStringResource = "터보 번역"
    static var description = IntentDescription("이미지 속 외국어를 번역합니다.")
    static var openAppWhenRun: Bool = false

    @MainActor
    func perform() async throws -> some IntentResult & ProvidesDialog {
        let manager = QuickVisionManager.shared
        await manager.performQuickVisionWithMode(.translate)
        return formatResult(manager)
    }
}

@available(iOS 16.0, *)
struct QuickVisionEncyclopediaIntent: AppIntent {
    static var title: LocalizedStringResource = "백과사전 검색"
    static var description = IntentDescription("사물을 식별하고 정보를 제공합니다.")
    static var openAppWhenRun: Bool = false

    @MainActor
    func perform() async throws -> some IntentResult & ProvidesDialog {
        let manager = QuickVisionManager.shared
        await manager.performQuickVisionWithMode(.encyclopedia)
        return formatResult(manager)
    }
}

// MARK: - 대화형 맞춤 지시 인텐트 (New)

@available(iOS 16.0, *)
struct QuickVisionCustomIntent: AppIntent {
    static var title: LocalizedStringResource = "터보 맞춤 지시"
    static var description = IntentDescription("사진을 찍고 사용자에게 무엇을 할지 직접 물어봅니다.")
    static var openAppWhenRun: Bool = false

    // 🌟 핵심: 이 변수값이 없으면 Siri가 requestValueDialog의 대사로 사용자에게 질문합니다!
    @Parameter(title: "사용자 명령", requestValueDialog: "무엇을 해드릴까요?")
    var userCommand: String

    @MainActor
    func perform() async throws -> some IntentResult & ProvidesDialog {
        let manager = QuickVisionManager.shared
        // 사용자가 대답한 내용(userCommand)을 Gemini 프롬프트로 그대로 전달합니다.
        await manager.performQuickVisionWithMode(.standard, customPrompt: userCommand)
        return formatResult(manager)
    }
}

// MARK: - 2. 결과 처리 헬퍼

@available(iOS 16.0, *)
@MainActor
private func formatResult(_ manager: QuickVisionManager) -> some IntentResult & ProvidesDialog {
    if let result = manager.lastResult {
        return .result(dialog: "분석 완료: \(result)")
    } else if let error = manager.errorMessage {
        return .result(dialog: "실패: \(error)")
    } else {
        return .result(dialog: "분석을 완료했습니다.")
    }
}

// MARK: - 4. 알림 이름 확장

extension Notification.Name {
    static let quickVisionTriggered = Notification.Name("quickVisionTriggered")
}

// MARK: - 5. 핵심 엔진: QuickVisionManager (이 부분이 없어서 에러가 났었습니다)

@MainActor
@Observable
final class QuickVisionManager {
    static let shared = QuickVisionManager()

    var isProcessing = false
    var lastResult: String?
    var errorMessage: String?
    var lastImage: UIImage?
    var lastMode: QuickVisionMode = .standard

    private(set) var streamViewModel: StreamSessionViewModel?
    private let tts = TTSService.shared

    private init() {
        NotificationCenter.default.addObserver(
            self,
            selector: #selector(handleQuickVisionTrigger(_:)),
            name: .quickVisionTriggered,
            object: nil
        )
    }

    func setStreamViewModel(_ viewModel: StreamSessionViewModel) {
        self.streamViewModel = viewModel
    }

    @objc private func handleQuickVisionTrigger(_ notification: Notification) {
        let customPrompt = notification.userInfo?["customPrompt"] as? String
        let modeString = notification.userInfo?["mode"] as? String
        let mode = modeString.flatMap { QuickVisionMode(rawValue: $0) } ?? .standard

        Task { @MainActor in
            await performQuickVisionWithMode(mode, customPrompt: customPrompt)
        }
    }

    func performQuickVisionWithMode(_ mode: QuickVisionMode, customPrompt: String? = nil) async {
        guard !isProcessing else { return }
        guard let streamViewModel = streamViewModel else {
            tts.speak("앱을 먼저 실행해 주세요.")
            return
        }

        isProcessing = true
        errorMessage = nil
        lastResult = nil
        
        guard let apiKey = APIKeyManager.shared.getAPIKey(), !apiKey.isEmpty else {
            tts.speak("API 키를 설정해 주세요.")
            isProcessing = false
            return
        }

        tts.speak("분석을 시작합니다.", apiKey: apiKey)
        let prompt = customPrompt ?? QuickVisionModeManager.shared.getPrompt(for: mode)

        do {
            if !streamViewModel.hasActiveDevice { throw QuickVisionError.noDevice }

            if streamViewModel.streamingStatus != .streaming {
                await streamViewModel.handleStartStreaming()
                var wait = 0
                while streamViewModel.streamingStatus != .streaming && wait < 50 {
                    try await Task.sleep(nanoseconds: 100_000_000)
                    wait += 1
                }
            }

            try await Task.sleep(nanoseconds: 500_000_000)
            streamViewModel.capturePhoto()

            var photoWait = 0
            while streamViewModel.capturedPhoto == nil && photoWait < 30 {
                try await Task.sleep(nanoseconds: 100_000_000)
                photoWait += 1
            }

            let photo = streamViewModel.capturedPhoto ?? streamViewModel.currentVideoFrame
            guard let finalPhoto = photo else { throw QuickVisionError.frameTimeout }

            lastImage = finalPhoto
            await streamViewModel.stopSession()

            let service = QuickVisionService(apiKey: apiKey)
            let result = try await service.analyzeImage(finalPhoto, customPrompt: prompt)

            lastResult = result
            tts.speak(result, apiKey: apiKey)

        } catch {
            errorMessage = error.localizedDescription
            tts.speak("실패했습니다.", apiKey: apiKey)
            await streamViewModel.stopSession()
        }

        isProcessing = false
    }

    func stopStream() async {
        guard let streamViewModel = streamViewModel else { return }
        await streamViewModel.stopSession()
    }

    func performQuickVision() async {
        await performQuickVisionWithMode(.standard)
    }

    func triggerQuickVision() {
        Task { @MainActor in
            await performQuickVision()
        }
    }

    func sendCustomCommand(text: String) async {
        print("🔥 [TurboMeta] 자연어 명령 수신: \(text)")

        if let chatVM = OpenClawChatViewModel.shared {
            await chatVM.processNaturalCommand(text: text)
            lastResult = chatVM.lastAnalysisResult
        } else {
            await performQuickVisionWithMode(.standard, customPrompt: text)
        }
    }
}

// MARK: - 기능 확장

extension QuickVisionManager {
    /// 터보 번역 전용: 촬영 → 번역 프롬프트로 AI 호출
    func captureAndTranslate() async -> (translatedText: String?, error: String?) {
        await performQuickVisionWithMode(.translate)
        return (lastResult, errorMessage)
    }

    func checkGlassesConnection() -> Bool {
        let isConnected = streamViewModel?.hasActiveDevice == true
        if !isConnected {
            print("❌ [TurboMeta] 안경이 연결되어 있지 않습니다. Meta View 앱에서 먼저 연결해주세요.")
        }
        return isConnected
    }

    /// 3가지 모드로 현재 시야를 분석: describe(설명) / translate(번역) / navigation(길안내)
    func sendCurrentViewToOpenClaw(mode: String = "describe") async {
        switch mode {
        case "translate":
            QuickVisionModeManager.shared.setMode(.translate)
            await performQuickVisionWithMode(.translate)

        case "navigation":
            tts.speak("목적지를 말씀해 주세요.")

        default: // describe
            let prompt = "내가 지금 레이반 메타 안경으로 보고 있는 장면이야. 사진 속 텍스트(메뉴판, 간판, 표지판 등)가 있으면 우선적으로 읽고 한국어로 번역해줘. 텍스트가 없으면 장면 전체를 한국어로 자세하고 자연스럽게 설명해줘."
            await performQuickVisionWithMode(.standard, customPrompt: prompt)
        }
    }
}
