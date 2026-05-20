/*
 * Live AI Mode Manager
 * 实时对话模式管理器 - 管理当前模式、自定义提示词、翻译目标语言
 */

import Foundation
import SwiftUI

class LiveAIModeManager: ObservableObject {
    static let shared = LiveAIModeManager()

    private let userDefaults = UserDefaults.standard
    private let modeKey = "liveAIMode"
    private let customPromptKey = "liveAICustomPrompt"
    private let translateTargetLanguageKey = "liveAITranslateTargetLanguage"

    @Published var currentMode: LiveAIMode {
        didSet {
            userDefaults.set(currentMode.rawValue, forKey: modeKey)
            print("📋 [LiveAIModeManager] 模式已切换: \(currentMode.displayName)")
        }
    }

    @Published var customPrompt: String {
        didSet {
            userDefaults.set(customPrompt, forKey: customPromptKey)
        }
    }

    @Published var translateTargetLanguage: String {
        didSet {
            userDefaults.set(translateTargetLanguage, forKey: translateTargetLanguageKey)
        }
    }

    // 支持的翻译目标语言
    static let supportedLanguages: [(code: String, name: String)] = [
        ("zh-CN", "中文"),
        ("en-US", "English"),
        ("ja-JP", "日本語"),
        ("ko-KR", "한국어"),
        ("fr-FR", "Français"),
        ("de-DE", "Deutsch"),
        ("es-ES", "Español"),
        ("it-IT", "Italiano"),
        ("pt-BR", "Português"),
        ("ru-RU", "Русский")
    ]

    private init() {
        // 加载保存的模式
        if let savedMode = userDefaults.string(forKey: modeKey),
           let mode = LiveAIMode(rawValue: savedMode) {
            self.currentMode = mode
        } else {
            self.currentMode = .standard
        }

        // 加载自定义提示词
        self.customPrompt = userDefaults.string(forKey: customPromptKey) ?? "liveai.custom.default".localized

        // 번역 대상 언어 로드 — 기본값 한국어(ko-KR)
        // savedLanguage.contains("-") 검사: BCP-47 코드(ko-KR 등)만 수락
        // 구버전에서 "Chinese"/"English" 같은 잘못된 값이 저장된 경우 한국어로 리셋
        if let savedLanguage = userDefaults.string(forKey: translateTargetLanguageKey),
           savedLanguage.contains("-") {
            self.translateTargetLanguage = savedLanguage
        } else {
            self.translateTargetLanguage = "ko-KR"
        }
    }

    // MARK: - Get Current System Prompt

    /// 获取当前模式的完整系统提示词
    func getSystemPrompt() -> String {
        switch currentMode {
        case .custom:
            return customPrompt
        case .translate:
            return getTranslatePrompt()
        default:
            return currentMode.systemPrompt
        }
    }

    /// 获取指定模式的系统提示词
    func getSystemPrompt(for mode: LiveAIMode) -> String {
        switch mode {
        case .custom:
            return customPrompt
        case .translate:
            return getTranslatePrompt()
        default:
            return mode.systemPrompt
        }
    }

    /// 获取翻译模式的提示词（包含目标语言）
    private func getTranslatePrompt() -> String {
        let targetLanguageName = Self.supportedLanguages.first { $0.code == translateTargetLanguage }?.name ?? "中文"
        let basePrompt = "prompt.liveai.translate".localized
        return basePrompt.replacingOccurrences(of: "{LANGUAGE}", with: targetLanguageName)
    }

    // MARK: - Mode Management

    func setMode(_ mode: LiveAIMode) {
        currentMode = mode
    }

    func setCustomPrompt(_ prompt: String) {
        customPrompt = prompt
    }

    func setTranslateTargetLanguage(_ languageCode: String) {
        translateTargetLanguage = languageCode
    }

    // MARK: - Static Access (for non-SwiftUI contexts)

    static var staticCurrentMode: LiveAIMode {
        return shared.currentMode
    }

    static var staticSystemPrompt: String {
        return shared.getSystemPrompt()
    }

    /// 是否在语音触发时自动发送图片
    static var staticAutoSendImageOnSpeech: Bool {
        return shared.currentMode.autoSendImageOnSpeech
    }
}
