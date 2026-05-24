//
//  TurboMetaShortcuts.swift
//  CameraAccess
//
//  Created by 전기백 on 5/11/26.
//

import AppIntents
import Foundation
import SwiftUI

// MARK: - 1. 아이리스 라이브 인텐트 정의
struct StartIrisLiveIntent: AppIntent {
    static var title: LocalizedStringResource = "아이리스 라이브"
    static var description = IntentDescription("아이리스 라이브 세션을 즉시 시작합니다.")
    static var openAppWhenRun: Bool = true

    @MainActor
    func perform() async throws -> some IntentResult & ProvidesDialog {
        NotificationCenter.default.post(name: NSNotification.Name("voiceAgentRequestsListening"), object: nil)
        return .result(dialog: "아이리스 라이브를 연결합니다.")
    }
}

// MARK: - 2. 아이리스 에이전트 인텐트 정의
struct CallAgentIntent: AppIntent {
    static var title: LocalizedStringResource = "아이리스 에이전트"
    static var description = IntentDescription("아이리스 에이전트를 호출하여 지시를 내립니다.")
    static var openAppWhenRun: Bool = true

    @MainActor
    func perform() async throws -> some IntentResult & ProvidesDialog {
        NotificationCenter.default.post(name: NSNotification.Name("agentRequestsListening"), object: nil)
        return .result(dialog: "아이리스 에이전트를 호출합니다.")
    }
}

// MARK: - 3. 단축어 프로바이더 (Siri 명령어 고정 매핑)
struct TurboMetaShortcuts: AppShortcutsProvider {
    static var appShortcuts: [AppShortcut] {
        [
            // [모드 1] 아이리스 라이브 - 시리가 음악 앱으로 새는 것을 방지하기 위해 문구를 명확히 고정
            AppShortcut(
                intent: StartIrisLiveIntent(),
                phrases: [
                    "아이리스 라이브 실행해줘",
                    "아이리스 라이브 실행시켜",
                    "아이리스 라이브 시작해줘",
                    "아이리스 라이브 켜줘",
                    "아이리스 라이브 열어줘"
                ],
                shortTitle: "아이리스 라이브",
                systemImageName: "waveform.circle.fill"
            ),
            
            // [모드 2] 아이리스 에이전트 - 도움말 창으로 새는 것을 방지하기 위해 문구 보강
            AppShortcut(
                intent: CallAgentIntent(),
                phrases: [
                    "아이리스 에이전트 실행해줘",
                    "아이리스 에이전트 실행시켜",
                    "아이리스 에이전트 호출해줘",
                    "아이리스 에이전트 켜줘",
                    "아이리스 에이전트 열어줘"
                ],
                shortTitle: "아이리스 에이전트",
                systemImageName: "sparkles"
            )
        ]
    }
}
