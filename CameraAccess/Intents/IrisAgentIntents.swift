/*
 * IrisAgentIntents.swift
 * Siri App Intents — Iris Live & Agent 듀얼 모드 호출
 */

import AppIntents

// MARK: - Start Iris Live Intent

struct StartIrisLiveIntent: AppIntent {
    static var title: LocalizedStringResource = "아이리스 라이브 시작"
    static var description = IntentDescription("아이리스 라이브 AI와 실시간 대화를 시작합니다.")
    static var openAppWhenRun: Bool = true

    @MainActor
    func perform() async throws -> some IntentResult & ProvidesDialog {
        NotificationCenter.default.post(name: .liveAITriggered, object: nil)
        Task { await LiveAIManager.shared.startLiveAISession() }
        return .result(dialog: "아이리스 라이브를 연결합니다.")
    }
}

// MARK: - Call Agent Intent

struct CallAgentIntent: AppIntent {
    static var title: LocalizedStringResource = "에이전트 호출"
    static var description = IntentDescription("OpenClaw 에이전트 모드를 실행합니다.")
    static var openAppWhenRun: Bool = true

    @MainActor
    func perform() async throws -> some IntentResult & ProvidesDialog {
        NotificationCenter.default.post(name: .agentCallTriggered, object: nil)
        return .result(dialog: "에이전트를 호출했습니다. 지시를 내려주세요.")
    }
}

// MARK: - Notification Names

extension Notification.Name {
    static let agentCallTriggered = Notification.Name("agentCallTriggered")
}
