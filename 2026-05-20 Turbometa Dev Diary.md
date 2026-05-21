# 2026-05-20 Turbometa 개발일지

## 1. 프로젝트 현황 요약
- **프로젝트명**: TurboMeta v2.1 (Ray-Ban Meta + OpenClaw + OpenRouter/Google AI 통합)
- **개발 목표**: Hands-free 연속 대화 + 자연스러운 TTS + 안정적인 음성 입력
- **LLM Provider**: OpenRouter (primary) — 텍스트 채팅, 장면 분석 모두 앱 설정 모델 직접 호출
- **TTS**: Google Cloud TTS Neural2 (OpenRouter 사용자) / Alibaba qwen3-tts-flash (Alibaba 사용자)
- **ASR**: Apple SFSpeechRecognizer (API 키 불필요, 실시간 한국어 인식)

---

## 2. 오늘(2026-05-20) 완료된 주요 작업

### 2-1. 연속 대화 모드 (Voice-01)
- `ConversationMemory.swift`: SwiftData 기반 대화 세션 영구 저장
  - `ConversationSession` + `ChatMessage` @Model
  - `appendMessage()`, `getRecentContext()`, `endSession()`, `allSessions` 구현
- `UnifiedVoiceAgent.swift`: Siri → AI 라우팅 파사드
  - ConversationMemory context 주입 → AI 응답 → TTS → 메모리 저장 → UI 알림
  - Notification: `.voiceAgentRequestsListening`, `.voiceAgentDidUpdateMessages`
- `ConversationMemoryTests.swift`: Swift Testing 기반 9개 단위 테스트

### 2-2. MainChatView 실시간 Siri 버블 표시 (UI-01)
- `ChatMessageView.swift` (신규): SwiftData `ChatMessage`용 iMessage 스타일 말풍선
- `ConversationHistoryView.swift` (신규): Siri 경로 대화 기록 뷰 (SwiftData 조회)
- `MainChatView.swift` 업데이트:
  - `.voiceAgentDidUpdateMessages` 수신 → siriMessages 실시간 표시
  - 채팅 하단에 Siri 대화 버블 자동 추가
  - `"chat_bottom"` 앵커로 스크롤 자동 추적

### 2-3. MainChatView 4가지 버그 수정

| # | 버그 | 원인 | 수정 |
|---|------|------|------|
| 1 | 촬영 분석 에러 화면 표시 안 됨 | `fail()`에서 `lastAnalysisResult` 미설정 | `lastAnalysisResult = "❌ \(reason)"` 추가 |
| 2 | 마이크 ASR 텍스트 미입력 | DashScope에 OpenRouter 키 사용 (인증 실패) | AppleASRService로 전환 |
| 3 | 대화창 모델 무시 (gemma4 고정) | 텍스트 채팅이 OpenClaw 서버 경유 | 앱 설정 AI 모델 직접 호출(`processTextChat`) |
| 4 | 대화 기록 세션 비어있음 | 저장은 UserDefaults, 조회는 SwiftData (불일치) | `ChatHistoryView`(OpenClawSessionStorage) 사용 |

### 2-4. Apple SFSpeechRecognizer ASR (`AppleASRService.swift`)
- Alibaba DashScope ASR 완전 교체
- **API 키 불필요** — iOS 시스템 음성 인식 권한만 필요
- 한국어(`ko-KR`) 실시간 스트리밍
- **핵심 설계**: `lastPartial` 추적 → `stop()` 시 직접 `onFinalResult` 전달
  - `cancel()` 호출 시 `isFinal` 콜백이 오지 않는 iOS 동작 우회
- `NSSpeechRecognitionUsageDescription` Info.plist 추가

### 2-5. Google Cloud TTS Neural2 (`TTSService.swift`)
- OpenRouter 사용자 경로: 시스템 TTS → Google Cloud TTS (`ko-KR-Neural2-A`)
- 엔드포인트: `texttospeech.googleapis.com/v1/text:synthesize`
- `APIKeyManager.getGoogleAPIKey()` 재사용 (Live AI와 동일 키)
- 응답: BASE64 PCM16 @ 24kHz → 기존 Alibaba 오디오 엔진 그대로 재사용
- 실패 시 시스템 TTS 자동 폴백

### 2-6. OpenClaw WebSocket 연결 디버깅
- 에러 순서: -1001(timeout) → -1003(DNS) → -1200(TLS) → -1011(bad response)
- 원인 분석:
  - Node.js가 `localhost:18789`만 바인딩 (외부 접근 불가)
  - nginx TLS 종료 후 Node.js 연결, 인증서 CN 불일치
  - iPhone MagicDNS 비활성화 → `.ts.net` 호스트 불인식
- 코드 수정: Raw IP 주소 → `ws://`, ts.net 호스트 → `wss://` 자동 선택
- 연결 성공 후 `waitingForPairing` 상태 도달 확인

---

## 3. 현재 아키텍처 요약

```
[사용자 음성]
    │
    ▼
AppleASRService (SFSpeechRecognizer, ko-KR)
    │ onFinalResult
    ▼
MainChatView.sendText()
    │
    ├─[텍스트 채팅]─▶ OpenClawChatViewModel.processTextChat()
    │                 └─▶ OpenRouter / Alibaba API 직접 호출
    │                     (VisionAPIConfig.model, baseURL)
    │
    └─[촬영 분석]──▶ OpenClawChatViewModel.captureAndDescribe()
                     └─▶ StreamViewModel(프레임) → QuickVisionService → TTS

[Siri "터보메타에게 시키기"]
    └─▶ TurboMetaCustomIntent → UnifiedVoiceAgent
        ├─▶ ConversationMemory (context 주입)
        ├─▶ AI 라우팅 (vision/chat)
        ├─▶ TTSService (Google Cloud Neural2 / Alibaba / System)
        └─▶ Notification → MainChatView Siri 버블 표시

[TTS 경로]
    OpenRouter 사용자: Google Cloud TTS Neural2 → 실패 시 AVSpeechSynthesizer
    Alibaba 사용자:    qwen3-tts-flash → 실패 시 AVSpeechSynthesizer
```

---

## 4. 파일 변경 목록

| 파일 | 변경 |
|------|------|
| `ConversationMemory.swift` | 신규: SwiftData 연속 대화 메모리 |
| `UnifiedVoiceAgent.swift` | 신규: Siri → AI 라우팅 파사드 |
| `Services/OpenClaw/AppleASRService.swift` | 신규: SFSpeechRecognizer 기반 ASR |
| `Views/ChatMessageView.swift` | 신규: SwiftData ChatMessage 말풍선 |
| `Views/ConversationHistoryView.swift` | 신규: Siri 대화 기록 뷰 |
| `Views/MainChatView.swift` | 수정: Siri 버블, ASR 교체, 직접 AI 채팅, 히스토리 수정 |
| `ViewModels/OpenClawChatViewModel.swift` | 수정: `processTextChat()` 추가, `fail()` lastAnalysisResult 설정 |
| `Services/TTSService.swift` | 수정: Google Cloud TTS Neural2 추가 |
| `Services/OpenClaw/OpenClawNodeService.swift` | 수정: IP/hostname 기반 ws/wss 자동 선택 |
| `Info.plist` | 수정: `NSSpeechRecognitionUsageDescription` 추가 |
| `CameraAccessTests/ConversationMemoryTests.swift` | 신규: 9개 단위 테스트 |

---

## 5. 설정 가이드 (OpenRouter 사용자 기준)

| 기능 | 설정 위치 | 필요 키 |
|------|----------|---------|
| 텍스트 채팅 | 설정 → 프로바이더 → OpenRouter + 모델 선택 | OpenRouter API 키 |
| 촬영 분석 | 동일 | OpenRouter API 키 |
| 음성 입력 (ASR) | 별도 설정 없음 (iOS 권한만 허용) | 불필요 |
| TTS 음성 출력 | 설정 → Live AI → Google API 키 입력 | Google API 키 (Cloud TTS API 활성화 필요) |
| Siri 명령 | 설정 앱 → Siri → TurboMeta 확인 | — |

---

## 6. 알려진 이슈 / 다음 세션 계획

- [ ] **Siri 인식율 50%**: "터보메타에게 시키기" phrase 미등록 → `TurboMetaShortcuts.swift`에 구문 추가 필요
- [ ] **촬영 분석 모델 오류**: OpenRouter에서 `google/gemini-2.0-flash-exp` 삭제됨 → 설정에서 `google/gemini-flash-1.5`로 변경 필요
- [ ] **연속 듣기 모드**: 답변 후 자동 마이크 재활성화 (UnifiedVoiceAgent → MainChatView 연동)
- [ ] OpenClaw 서버 LLM 설정 명확화 (서버 `.env` 편집 가이드)
- [ ] Siri 단축어 구문 목록 확장 및 오인식 패턴 제거

**작업자**: Claude Code (Sonnet 4.6) + User  
**작업 일시**: 2026-05-20  
**다음 세션 시작 시**: "이전 개발일지 요약"이라고 말씀하시면 바로 이어가겠습니다.

---
**End of Log**
