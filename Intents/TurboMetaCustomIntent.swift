/*
 * TurboMeta Custom Intent
 * Siri "무엇을 해드릴까요?" 대화형 인텐트 — 자연어 명령을 Gemini로 전달
 * 장면 관련 키워드 감지 시 카메라 캡처 경로로 라우팅
 */
/*
import AppIntents

struct TurboMetaCustomIntent: AppIntent {
    static var title: LocalizedStringResource = "터보메타에게 시키기"
    static var description = IntentDescription("자연어로 터보메타에게 명령합니다.")
    static var openAppWhenRun: Bool = false

    @Parameter(title: "명령", requestValueDialog: "무엇을 해드릴까요?")
    var userSpokenText: String

    static var parameterSummary: some ParameterSummary {
        Summary("터보메타에게 \(\.$userSpokenText) 하라고 해")
    }

    @MainActor
    func perform() async throws -> some IntentResult & ProvidesDialog {
        await UnifiedVoiceAgent.shared.processVoiceCommand(userSpokenText)
        return .result(dialog: IntentDialog("알겠습니다. 바로 처리할게요."))
    }
}
