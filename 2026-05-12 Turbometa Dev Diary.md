# 2026-05-12 Turbometa 개발일지

## 1. 프로젝트 현황 요약
- **프로젝트명**: TurboMeta v2 (Ray-Ban Meta + OpenClaw + OpenRouter 통합 AI 어시스턴트)
- **개발 목표**: Siri “터보메타에게 시키기” 하나로 Ray-Ban Meta 착용 상태에서 **화면 없이 완전 hands-free** 음성 통합 AI 구현
- **현재 상태**: Chat-centric UI + Unified Agent Router + OpenRouter LLM 강제 routing 완료
- **LLM Provider**: **OpenRouter** (primary) + Google AI Studio bypass (사용량 0 유지)

## 2. 오늘(2026-05-12) 완료된 주요 작업

### UI / UX 개선
- 메인 화면 → **Chat-Centric MainChatView**로 전환 (카드 메뉴 제거)
- 하단 Tab Bar → 최소화, 설정 버튼을 Navigation Toolbar 오른쪽 gear로 이동
- Simulator Mock Mode 구현 → Ray-Ban 연결 없이도 Home/Chat 화면 즉시 진입
- **마이크 버튼 UX 대폭 개선**
  - “듣는 중...” + 실시간 interim transcription → 하단 텍스트 입력창 자동 입력
  - 사용자가 내용 확인/수정 후 Send(↑) 버튼으로 전송 가능
- Quick Vision에서 “지금 보이는 거 설명해” hard-coded 제거 → **동적 prompt** 지원

### Siri / Intent 통합
- `TurboMetaCustomIntent` + `UnifiedAgentRouter` 설계 완료
- “터보메타에게 시키기” 명령 하나로 **Quick Vision, 번역, Google Maps 네비게이션, LeanEat, Chat** 등 모든 기능 통합 라우팅
- Gemini classification 강화 (“지금 보이는 장면”, “번역해”, “길 찾아줘” 키워드 정확 인식)
- Siri 인덱싱 문제 해결 + background capture 지원

### Navigation
- 길찾기 버튼 → **Apple Maps → Google Maps** deep link 변경
- Gemini 자연어 파싱 → origin/destination/mode 자동 추출 후 `comgooglemaps://` 또는 web URL 열기

### TTS / Voice Experience
- `TTSManager` 신규 생성 (AVSpeechSynthesizer + 한국어 Siri voice)
- rate(0.48), pitch(1.05), volume 최적화 + OpenClaw WebSocket으로 Ray-Ban Meta 스피커 직접 출력
- Settings에 TTS Voice & Speed 조절 UI 추가

### LLM Routing 명확화
- `APIProviderManager`에서 **OpenRouter 강제** (모든 Quick Vision, Mic, Chat, Agent 호출)
- Google AI Studio Key는 Settings에 유지하되 실제 호출 bypass (사용량 변동 없음)
- OpenClaw = **하드웨어 브릿지** (camera/mic/speaker) 역할만 담당, LLM은 전부 OpenRouter

### Settings & 기타 안정화
- 출력 언어 기본값 **한국어(ko)** 강제 (중국어 fallback 완전 제거)
- Simulator API Key 입력 UX 개선 (OpenRouter, Qwen 등)
- LiveTranslate noApiKey 에러 → OpenClaw fallback으로 graceful handling

## 3. 현재 아키텍처 요약
- **Root View**: `MainChatView` (NavigationStack + Chat + 하단 액션 바)
- **Unified Agent**: `TurboMetaCustomIntent` → `UnifiedAgentRouter` → 각 Manager (QuickVisionManager, NavigationManager, TTSManager …)
- **Hardware Layer**: OpenClaw WebSocket (Ray-Ban Meta camera/mic/speaker)
- **LLM Layer**: OpenRouter (vision + text 모델 공통)
- **TTS Layer**: Apple AVSpeechSynthesizer + OpenClaw speaker

## 4. 다음 세션 계획 (새 창에서 계속)
- Ray-Ban Meta **음성 통합 AI 기능 버전** 본격 개발
- Continuous Conversation Mode (컨텍스트 유지)
- LeanEat Manager, Telegram Manager, iCloud 자동 저장 등 Unified Router 확장
- DAT SDK gesture (tap/long-press) 활용 가능성 검토
- OpenRouter 최적 모델 (Gemini 2.0 Flash / Claude 3.5 Sonnet) 고정

**작업자**: Gemini (Architect) + Claude Code (Implementation) + User  
**작업 일시**: 2026-05-13  
**다음 세션 시작 시**: “이전 개발일지 요약”이라고 말씀하시면 바로 이어가겠습니다.

---
**End of Log**