# TurboMeta - RayBan Meta 스마트 안경 AI 어시스턴트

<div align="center">

<img src="./rayban.png" width="120" alt="TurboMeta Logo"/>

**🌏 세계 최초의 한국어 지원 레이밴 메타 멀티모달 AI 어시스턴트**

[![iOS](https://img.shields.io/badge/iOS-17.0%2B-blue.svg)](https://www.apple.com/ios/)
[![Android](https://img.shields.io/badge/Android-8.0%2B-green.svg)](https://www.android.com/)
[![Swift](https://img.shields.io/badge/Swift-5.0-orange.svg)](https://swift.org)
[![Kotlin](https://img.shields.io/badge/Kotlin-1.9-purple.svg)](https://kotlinlang.org)
[![License](https://img.shields.io/badge/License-MIT-green.svg)](LICENSE)
[![Buy Me a Coffee](https://img.shields.io/badge/Buy%20Me%20a%20Coffee-☕-FFDD00?style=for-the-badge&logo=buy-me-a-coffee&logoColor=black)](https://buymeacoffee.com/turbo1123)

[English](./README_EN.md) | [简体中文](./README.md) | [한국어](./README_KR.md)

</div>

---

> **면책 조항 (Disclaimer)**: 본 프로젝트는 개발자의 학습 및 연구를 위한 소스 코드만을 제공하는 오픈소스 프로젝트입니다. 사전 빌드된 바이너리(IPA)를 제공하지 않으며, 공식 앱 스토어 배포 방식을 우회하는 행위를 지원하지 않습니다. iOS 사용자는 Apple의 표준 개발 워크플로우에 따라 Xcode를 사용하여 직접 빌드해야 합니다. 본 프로젝트는 [Apple Developer Program 사용권 계약](https://developer.apple.com/support/terms/)의 모든 약관을 엄격히 준수합니다.

---

## 🎉 주요 업데이트 v2.1.0

<div align="center">

### 🎙️ 연속 대화 + 자연스러운 TTS + 안정적인 음성 입력

**API 키 없이 한국어 음성 입력 · Google Cloud Neural2 TTS · Siri 연동 연속 대화**

✅ **iOS v2.1.0**

☕ **이 프로젝트가 도움이 되셨나요?** [**커피 한 잔 후원하기**](https://buymeacoffee.com/turbo1123)

</div>

### 🆕 v2.1 새로운 기능

- 🎤 **Apple 음성 인식 (ASR)**: API 키 불필요 — iOS 내장 `SFSpeechRecognizer`로 한국어 실시간 음성 입력 (Alibaba DashScope 대체)
- 🔊 **Google Cloud TTS Neural2**: OpenRouter 사용자에게 `ko-KR-Neural2-A` 고품질 음성 합성 제공 (시스템 TTS 자동 폴백)
- 💬 **직접 AI 채팅**: 텍스트 대화가 OpenClaw 서버를 경유하지 않고 설정한 AI 모델(OpenRouter/Gemini)을 직접 호출
- 🧠 **연속 대화 메모리**: SwiftData 기반 `ConversationMemory` + `UnifiedVoiceAgent`로 Siri 경로 대화 세션 영구 저장
- 💬 **Siri 버블 표시**: Siri "터보메타에게 시키기" 명령 결과가 메인 채팅 화면에 실시간 말풍선으로 표시
- 🐛 **4가지 버그 수정**: 촬영 분석 에러 표시, 마이크 ASR 입력, 대화 모델 설정 반영, 대화 기록 표시

---

## 🎉 주요 업데이트 v2.0.0

<div align="center">

### 🔗 OpenClaw 통합 + Meta Ray-Ban Display 지원

**음성 채팅, 사진 인식, OpenClaw AI 어시스턴트 — 당신의 안경이 모든 것과 연결됩니다!**

✅ **iOS v2.0.0** | 📱 **Android v1.5.0**

</div>

### 🆕 v2.0 새로운 기능

- 🔗 **OpenClaw 통합**: 안경을 [OpenClaw](https://openclaw.ai) AI 어시스턴트에 연결하여 사진 촬영 및 음성 채팅 가능 👉 [설정 가이드](#-openclaw-통합)
- 🕶️ **Meta Ray-Ban Display 지원**: 최신 Meta Ray-Ban Display 안경 지원 추가 (DAT SDK v0.5.0)
- 🎙️ **실시간 음성 인식**: OpenClaw 채팅 시 Alibaba Fun-ASR 기반의 음성-텍스트 변환 지원
- 🛡️ **안정성 개선**: 메모리 누수 해결 및 스레드 안전성(Thread Safety) 강화

### 🎯 핵심 기능

- 🔗 **OpenClaw AI 어시스턴트**: OpenClaw 게이트웨이에 연결하여 안경으로 촬영한 사진으로 AI와 대화
- 🎬 **RTMP 라이브 스트리밍**: YouTube, Twitch, Bilibili, TikTok 등 모든 RTMP 플랫폼으로 스트리밍
- 👁️ **퀵 비전 (Quick Vision)**: Siri 음성 명령을 통해 폰을 꺼내지 않고도 눈앞의 사물 식별
- 🤖 **라이브 AI (Live AI)**: 안경 카메라와 마이크를 이용한 실시간 멀티모달 AI 대화
- 🍽️ **린잇 (LeanEat)**: 음식 사진을 찍어 영양 분석 및 건강 점수 확인

---

## 📱 퀵 비전 (Quick Vision)

<div align="center">

### 🚀 백그라운드 깨우기 + Siri 음성 트리거!

**휴대폰 잠금을 해제할 필요 없이, 말 한마디로 눈앞의 모든 것을 AI가 분석합니다.**

</div>

Meta DAT SDK의 제한으로 인해 앱이 백그라운드에서 안경 카메라에 직접 접근할 수 없습니다. 이를 극복하기 위해 **Siri 단축어(Shortcuts) + App Intent + Alibaba Cloud TTS**를 결합하여 구현했습니다.

- 📱 **Siri 음성 호출**: "Siri야, 터보메타 퀵 비전 실행해줘"
- ⌚ **동작 버튼(Action Button) 지원** (iPhone 15 Pro 이상): 원터치로 퀵 비전 실행
- 🔊 **음성 결과 안내**: qwen3-tts-flash 기반의 고품질 음성 출력
- 🎯 **완전 자동화**: 스트림 시작 → 캡처 → 스트림 정지 → AI 인식 → 음성 안내

👉 [상세 튜토리얼 보기](#퀵-비전-튜토리얼)

---

## 🎨 인터페이스 미리보기

<table>
  <tr>
    <td align="center"><b>홈 화면</b><br/>Home</td>
    <td align="center"><b>대화 기록</b><br/>Live AI</td>
    <td align="center"><b>촬영 페이지</b><br/>Camera</td>
    <td align="center"><b>설정 페이지</b><br/>Settings</td>
  </tr>
  <tr>
    <td><img src="./screenshots/首页.jpg" width="180"/></td>
    <td><img src="./screenshots/对话记录.jpg" width="180"/></td>
    <td><img src="./screenshots/camera.jpg" width="180"/></td>
    <td><img src="./screenshots/设置页面.jpg" width="180"/></td>
  </tr>
</table>

## 📥 소스 코드 다운로드 및 빌드

### ⚠️ 중요: Meta DAT SDK 프리뷰 모드 활성화 필수!

TurboMeta를 사용하기 전, Meta View 앱에서 반드시 DAT SDK 프리뷰 모드를 활성화해야 합니다 (iOS 개발자 모드와 별개).

1. **안경 펌웨어를 버전 20 이상으로 업데이트**
2. **Meta View 앱을 최신 버전으로 업데이트**
3. 휴대폰에서 **Meta View 앱** 실행
4. **설정(Settings)** → **앱 정보(App Info)** 이동
5. **버전 번호(Version Number)** 확인
6. **버전 번호를 빠르게 5번 탭하세요**
7. 확인 메시지가 나타나면 성공

---

### 🍎 iOS — 소스에서 빌드하기

> ✅ 한국어/영어 UI, OpenRouter, Gemini, RTMP 스트리밍, OpenClaw 지원
> ⚠️ **빌드 시 Xcode 15.0 이상이 필요합니다.**

#### Step 1: Meta Wearables 등록
1. [Meta Wearables 개발자 센터](https://wearables.developer.meta.com/) 가입
2. **Projects** → **Create Project** 생성
3. **App configuration** 페이지의 **iOS integration** 항목에서 `MetaAppID`와 `ClientToken` 복사
4. `CameraAccess/Info.plist` 파일을 열고 아래 항목을 수정:

```xml
<key>MWDAT</key>
<dict>
    <key>AppLinkURLScheme</key>
    <string>turbometa://</string>
    <key>MetaAppID</key>
    <string>YOUR_META_APP_ID</string>
    <key>ClientToken</key>
    <string>YOUR_CLIENT_TOKEN</string>
    <key>TeamID</key>
    <string>$(DEVELOPMENT_TEAM)</string>
</dict>

```

#### Step 2: 빌드 및 실행

1. Xcode로 `CameraAccess.xcodeproj` 열기
2. **Signing & Capabilities**에서 본인의 Apple ID와 Team 선택
3. iPhone 연결 후 실행(Run)
4. 앱 설정에서 Alibaba Cloud API Key 입력 👉 [설정 가이드](https://www.google.com/search?q=%23api-%ED%82%A4-%EC%84%A4%EC%A0%95)

---

## 🛠️ 기술 스택 (Tech Stack)

### iOS

* **플랫폼**: iOS 17.0+
* **언어**: Swift 5.0 + SwiftUI
* **SDK**: Meta Wearables DAT SDK v0.5.0
* **아키텍처**: MVVM + Combine / Observation
* **오디오**: AVAudioEngine + AVAudioPlayerNode

### AI 모델 / 서비스

* **OpenRouter**: 텍스트 채팅 및 이미지 분석 (Gemini, Claude, GPT 등 모든 모델 지원)
* **Google Gemini API**: 직접 연결 옵션
* **Google Cloud TTS Neural2**: 고품질 한국어 음성 합성 (`ko-KR-Neural2-A`)
* **Apple SFSpeechRecognizer**: API 키 불필요, iOS 내장 한국어 음성 인식
* **Qwen Omni-Realtime**: 실시간 멀티모달 대화용 (Live AI)
* **Qwen VL-Plus**: 이미지 인식 및 영양 분석용
* **Qwen TTS-Flash**: 고품질 한국어/중국어 음성 합성 (Alibaba 경로)

---

## ⚙️ 설정 옵션 (Configuration)

### v2.1 API 키 설정 (OpenRouter 사용자 기준)

| 기능 | 설정 위치 | 필요 키 |
|------|----------|---------|
| 텍스트 채팅 / 촬영 분석 | 설정 → 프로바이더 → OpenRouter + 모델 선택 | OpenRouter API 키 |
| 음성 입력 (ASR) | 별도 설정 없음 (iOS 권한만 허용) | 불필요 |
| TTS 음성 출력 | 설정 → Live AI → Google API 키 입력 | Google API 키 (Cloud TTS API 활성화 필요) |
| Siri 명령 | 설정 앱 → Siri → TurboMeta 확인 | — |

### API 키 설정 (기존 Alibaba 사용자)

Alibaba Cloud Model Studio에서 API 키를 발급받아야 합니다.

1. [Alibaba Cloud Model Studio](https://bailian.console.alibabacloud.com/) 접속 및 로그인
2. **API-KEY 관리**에서 키 생성
3. 앱 내 **설정** → **API Key 관리**에 붙여넣기

---

## 🔒 개인정보 및 보안

* ✅ 모든 오디오/비디오 데이터는 AI 처리를 위해서만 사용됩니다.
* ✅ 사용자 개인 데이터를 별도로 저장하거나 업로드하지 않습니다.
* ✅ 모든 통신은 HTTPS 암호화 프로토콜을 사용합니다.

## 🗺️ 로드맵 (Roadmap)

* [x] 실시간 AI 대화 및 영양 분석
* [x] 퀵 비전 (Siri 단축어 통합)
* [x] Android 버전 출시
* [x] OpenClaw 통합 (v2.0)
* [x] Apple SFSpeechRecognizer ASR — API 키 불필요 (v2.1)
* [x] Google Cloud TTS Neural2 자연스러운 음성 (v2.1)
* [x] 직접 AI 채팅 (설정 모델 반영) (v2.1)
* [x] SwiftData 연속 대화 메모리 + Siri 버블 (v2.1)
* [ ] 연속 듣기 모드 (답변 후 자동 마이크 재활성화)
* [ ] 실시간 통번역 기능 추가
* [ ] 워드런(WordLearn) 단어 학습 모드
* [ ] Apple Watch 컴패니언 앱 지원

## 🤝 기여하기 (Contributing)

버그 리포트, 기능 제안, PR(Pull Request)은 언제나 환영합니다!

---

**스마트 안경을 더 똑똑하게 🕶️**

Made with ❤️ for RayBan Meta Users
