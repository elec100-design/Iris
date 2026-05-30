import AVFoundation
import UIKit

// TTS 중단, Haptic, 준비 메시지 + Meta Glasses Bluetooth 라우팅을 책임지는 매니저
@MainActor
final class SpeechManager {
    let synthesizer = AVSpeechSynthesizer()
    private let impactGenerator = UIImpactFeedbackGenerator(style: .medium)

    init() {
        configureAudioSession()
    }

    // Meta Glasses (A2DP) 우선 라우팅 — defaultToSpeaker 제거로 iPhone 스피커 고정 해제
    private func configureAudioSession() {
        let session = AVAudioSession.sharedInstance()
        do {
            try session.setCategory(.playback, mode: .default, options: [.allowBluetooth, .allowBluetoothA2DP])
            try session.setActive(true)
        } catch {
            print("[SpeechManager] AudioSession configure failed: \(error)")
        }
    }

    func stopSpeakingImmediately() {
        synthesizer.stopSpeaking(at: .immediate)
    }

    func triggerHaptic() {
        impactGenerator.prepare()
        impactGenerator.impactOccurred()
    }

    // Hermes 응답 TTS 직전에 호출 → Meta Glasses 라우팅 보장
    func prepareForSpeaking() {
        configureAudioSession()
    }

    func speakReadyMessage() async {
        // AudioSession을 speak 직전에 재설정하여 Meta Glasses 라우팅 확보
        configureAudioSession()
        try? await Task.sleep(nanoseconds: 180_000_000) // 180ms: 이전 TTS가 완전히 멈출 여유

        let utterance = AVSpeechUtterance(string: "네~ 말씀해 주세요")
        utterance.voice = AVSpeechSynthesisVoice(language: "ko-KR")
        utterance.rate = 0.48
        utterance.volume = 0.9
        synthesizer.speak(utterance)

        // TTS가 완전히 끝날 때까지 대기 (최대 3초) — 마이크 활성화 전 충돌 방지
        let deadline = Date().addingTimeInterval(3.0)
        while synthesizer.isSpeaking && Date() < deadline {
            try? await Task.sleep(nanoseconds: 50_000_000)
        }
    }
}
