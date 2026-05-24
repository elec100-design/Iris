//
//  TurboMetaCaptureIntent.swift
//  CameraAccess
//
//  Created by 전기백 on 5/11/26.
//
/*
import AppIntents
import UIKit

struct TurboMetaCaptureIntent: AppIntent {
    static var title: LocalizedStringResource = "안경으로 촬영 및 분석"
    static var description = IntentDescription("레이벤 메타 안경으로 사진을 찍고 AI가 상황을 한국어로 설명합니다.")

    static var openAppWhenRun: Bool = false

    @MainActor
    func perform() async throws -> some IntentResult & ReturnsValue<String> {
        let viewModel = OpenClawChatViewModel.shared

        do {
            try await viewModel.startVisualAISession()
            return .result(value: "분석을 시작합니다.", dialog: "안경으로 사진을 찍어 분석을 시작할게요.")
        } catch {
            return .result(value: "실패", dialog: "안경 연결을 확인해 주세요.")
        }
    }
}

