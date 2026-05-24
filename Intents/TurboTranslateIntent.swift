//
//  TurboTranslateIntent.swift
//  CameraAccess
//
//  Created by 전기백 on 5/11/26.
//
/* ㅏ*/
import AppIntents

struct TurboTranslateIntent: AppIntent {
    static var title: LocalizedStringResource = "레이반 번역"
    static var description = IntentDescription("안경으로 사진을 찍어 텍스트를 한국어로 번역합니다.")
    
    func perform() async throws -> some IntentResult & ProvidesDialog {
        // 1. 번역 모드 강제 설정
        QuickVisionModeManager.shared.setMode(.translate)

        // 2. 안경 연결 체크
        guard await QuickVisionManager.shared.checkGlassesConnection() else {
            return .result(dialog: IntentDialog("안경이 연결되어 있지 않습니다.\nMeta View 앱에서 먼저 연결해주세요."))
        }

        // 3. 즉시 촬영 + 번역
        let result = await QuickVisionManager.shared.captureAndTranslate()

        if let translated = result.translatedText {
            return .result(dialog: IntentDialog(translated))
        } else {
            return .result(dialog: IntentDialog("번역에 실패했습니다. 다시 시도해주세요."))
        }
    }
}
