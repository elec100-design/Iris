import Foundation
import AppIntents

// MARK: - 1. 라이브 시작 인텐트 (메인 메뉴의 'Live' 버튼 완전 동기화)
struct LaunchLiveIntent: AppIntent {
    static var title: LocalizedStringResource = "라이브 시작"
    static var openAppWhenRun: Bool = true

    @MainActor
    func perform() async throws -> some IntentResult {
        if let _ = OpenClawChatViewModel.shared {
            // 🌟 [개조 포인트] 쓸데없는 확인창(Dialog)을 원천 차단하고, 제미나이 라이브 스트리밍 오디오 세션을 즉시 강제 트리거합니다.
            NotificationCenter.default.post(name: NSNotification.Name("voiceAgentRequestsListening"), object: nil)
            return .result()
        }
        return .result()
    }
}

// MARK: - 2. 오픈클로 시작 인텐트 (백엔드 스왑 + 중앙 에이전트 자동 클릭)
struct LaunchOpenClawIntent: AppIntent {
    static var title: LocalizedStringResource = "오픈클로 시작"
    static var openAppWhenRun: Bool = true

    @MainActor
    func perform() async throws -> some IntentResult {
        if let viewModel = OpenClawChatViewModel.shared {
            // 1. 백엔드를 오픈클로로 먼저 즉시 전환
            viewModel.selectedBackend = .openClaw
            
            // 🌟 [개조 포인트] 유저가 손대지 않아도 중앙의 '에이전트' 버튼이 클릭된 것처럼 즉시 마이크를 열어 청취를 시작합니다.
            NotificationCenter.default.post(name: NSNotification.Name("agentRequestsListening"), object: nil)
            return .result()
        }
        return .result()
    }
}

// MARK: - 3. 헤르메스 시작 인텐트 (백엔드 스왑 + 중앙 에이전트 자동 클릭)
struct LaunchHermesIntent: AppIntent {
    static var title: LocalizedStringResource = "헤르메스 시작"
    static var openAppWhenRun: Bool = true

    @MainActor
    func perform() async throws -> some IntentResult {
        if let viewModel = OpenClawChatViewModel.shared {
            // 1. 백엔드를 헤르메스로 즉시 전환 및 서버 커넥션 개시
            viewModel.connectHermes()
            
            // 🌟 [개조 포인트] 확인창 없이 앱이 열리자마자 헤르메스 에이전트 마이크를 즉시 활성화하여 대화 대기 상태로 진입합니다.
            NotificationCenter.default.post(name: NSNotification.Name("agentRequestsListening"), object: nil)
            return .result()
        }
        return .result()
    }
}

// MARK: - [핵심] 시스템 단축어 자동 등록기
struct IrisAppShortcuts: AppShortcutsProvider {
    
    @AppShortcutsBuilder
    static var appShortcuts: [AppShortcut] {
        AppShortcut(
            intent: LaunchLiveIntent(),
            phrases: [
                "\(.applicationName)에서 라이브 시작",
                "\(.applicationName) 라이브 시작"
            ],
            shortTitle: "라이브 시작",
            systemImageName: "play.circle.fill"
        )
        
        AppShortcut(
            intent: LaunchOpenClawIntent(),
            phrases: [
                "\(.applicationName)에서 오픈클로 시작",
                "\(.applicationName) 오픈클로 시작"
            ],
            shortTitle: "오픈클로 시작",
            systemImageName: "arrow.triangle.2.circlepath"
        )
        
        AppShortcut(
            intent: LaunchHermesIntent(),
            phrases: [
                "\(.applicationName)에서 헤르메스 시작",
                "\(.applicationName) 헤르메스 시작"
            ],
            shortTitle: "헤르메스 시작",
            systemImageName: "waveform.circle"
        )
    }
}

// MARK: - Notification Name Extension
extension Notification.Name {
    static let hermesBackendActivated = Notification.Name("hermesBackendActivated")
}
