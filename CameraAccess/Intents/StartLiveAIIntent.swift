import AppIntents

struct StartLiveAIIntent: AppIntent {
    static var title: LocalizedStringResource = "Live AI 시작"
    static var description = IntentDescription("레이반 메타와 아이리스 Live 세션을 즉시 시작합니다.")
    static var openAppWhenRun: Bool = false

    @MainActor
    func perform() async throws -> some IntentResult & ProvidesDialog {
        Task {
            await LiveAIManager.shared.startLiveAISession()
        }
        return .result(dialog: "아이리스를 연결합니다. 말씀하세요.")
    }
}
