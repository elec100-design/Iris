# 아이리스 (Iris) - RayBan Meta 스마트 안경 AI 어시스턴트

<div align="center">

<img src="./rayban.png" width="120" alt="Iris Logo"/>

**🌏 세계 최초의 한국어 지원 레이밴 메타 멀티모달 AI 어시스턴트**

[![iOS](https://img.shields.io/badge/iOS-17.0%2B-blue.svg)](https://www.apple.com/ios/)
[![Swift](https://img.shields.io/badge/Swift-5.0-orange.svg)](https://swift.org)
[![License](https://img.shields.io/badge/License-MIT-green.svg)](LICENSE)

[English](./README_EN.md) | [简体中文](./README.md) | [한국어](./README_KR.md)

</div>

---

> **면책 조항 (Disclaimer)**: 본 프로젝트는 개발자의 학습 및 연구를 위한 소스 코드만을 제공하는 오픈소스 프로젝트입니다. Apple의 표준 개발 워크플로우를 준수하여 빌드하십시오.

---

## 🌟 아이리스 (Iris) 주요 기능 이원화

아이리스는 사용자의 목적에 따라 두 가지 강력한 모드를 제공합니다:

### ⚡ Live (Gemini 실시간 모드)
*   **Gemini API 직접 연동:** Gemini API Key를 사용하여 고성능 실시간 멀티모달 라이브 대화를 경험하세요.
*   **고속 엔진:** 지연 없는 응답 속도와 정확한 정보 해석 능력을 제공합니다.

### 🤖 에이전트 (OpenClaw 로컬 모드)
*   **맥미니(OpenClaw) 연동:** 사용자의 데스크톱 환경(OpenClaw)과 로컬 LLM을 연동하여 최고의 보안성과 확장성을 보장합니다.
*   **개방형 플랫폼:** 나만의 로컬 LLM을 안경에서 직접 활용 가능합니다.

---

## 🎉 주요 업데이트 v2.2.0 (아이리스 리브랜딩)

### 🆕 새 기능
- **브랜드 리네이밍:** TurboMeta에서 **'아이리스 (Iris)'**로 새롭게 태어났습니다.
- **기능 이원화:** `Live`(Gemini 기반)와 `에이전트`(OpenClaw 로컬 환경 기반)로 운영 체계를 개편했습니다.
- **연속 대화 메모리:** SwiftData 기반으로 대화 세션을 영구적으로 보존합니다.

---

## 📥 설치 및 설정

### 🍎 iOS — 소스에서 빌드하기
1. Xcode로 `CameraAccess.xcodeproj` 열기
2. `CameraAccess/Info.plist`에서 `MetaAppID` 및 `ClientToken` 설정
3. 설정에서 `Gemini API Key` 또는 `OpenClaw` 연동 정보 입력

---

## 🗺️ 로드맵 (Roadmap)
* [x] 아이리스 리브랜딩 및 기능 이원화
* [x] Gemini API 직접 연동 (Live 모드)
* [x] 맥미니 OpenClaw 및 로컬 LLM 연동 (에이전트 모드)
* [ ] 연속 듣기 모드 강화
* [ ] 실시간 통번역 고도화

---

**스마트 안경을 더 똑똑하게 🕶️**
Made with ❤️ for RayBan Meta Users
