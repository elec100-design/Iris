/*
 * AppleASRService
 * Apple SFSpeechRecognizer 기반 실시간 한국어 음성 인식
 * API 키 불필요 — 시스템 권한만 필요
 *
 * 핵심 설계:
 * - lastPartial: 최신 부분 인식 결과를 항상 추적
 * - stop() 호출 시 lastPartial을 onFinalResult로 전달 (cancel이 콜백을 막으므로)
 */

import Foundation
import Speech
import AVFoundation

class AppleASRService {
    private var recognitionRequest: SFSpeechAudioBufferRecognitionRequest?
    private var recognitionTask: SFSpeechRecognitionTask?
    private let audioEngine = AVAudioEngine()
    private let speechRecognizer: SFSpeechRecognizer?
    private var lastPartial = ""
    private var delivered = false

    var onPartialResult: ((String) -> Void)?
    var onFinalResult: ((String) -> Void)?
    var onError: ((String) -> Void)?

    init(locale: Locale = Locale(identifier: "ko-KR")) {
        speechRecognizer = SFSpeechRecognizer(locale: locale)
    }

    // MARK: - Public API

    func start() {
        SFSpeechRecognizer.requestAuthorization { [weak self] status in
            guard let self else { return }
            DispatchQueue.main.async {
                if status == .authorized {
                    do { try self.startRecognition() }
                    catch { self.onError?(error.localizedDescription) }
                } else {
                    self.onError?("음성 인식 권한이 필요합니다. 설정 → 개인 정보 보호 → 음성 인식에서 허용해주세요.")
                }
            }
        }
    }

    func stop() {
        // cancel()은 isFinal 콜백을 막으므로, lastPartial을 직접 전달
        let text = lastPartial
        teardown()
        if !text.isEmpty && !delivered {
            delivered = true
            onFinalResult?(text)
        }
    }

    // MARK: - Internal

    private func teardown() {
        if audioEngine.isRunning {
            audioEngine.inputNode.removeTap(onBus: 0)
            audioEngine.stop()
        }
        recognitionRequest?.endAudio()
        recognitionTask?.cancel()
        recognitionTask = nil
        recognitionRequest = nil
        print("[AppleASR] Torn down")
    }

    private func startRecognition() throws {
        teardown()
        lastPartial = ""
        delivered = false

        guard let recognizer = speechRecognizer, recognizer.isAvailable else {
            onError?("음성 인식을 사용할 수 없습니다. 네트워크 연결을 확인해주세요.")
            return
        }

        let session = AVAudioSession.sharedInstance()
        try session.setCategory(.record, mode: .measurement, options: .duckOthers)
        try session.setActive(true, options: .notifyOthersOnDeactivation)

        recognitionRequest = SFSpeechAudioBufferRecognitionRequest()
        guard let request = recognitionRequest else { return }
        request.shouldReportPartialResults = true

        recognitionTask = recognizer.recognitionTask(with: request) { [weak self] result, error in
            guard let self, !self.delivered else { return }
            if let result = result {
                let text = result.bestTranscription.formattedString
                if !text.isEmpty {
                    self.lastPartial = text
                    if result.isFinal {
                        self.delivered = true
                        DispatchQueue.main.async { self.onFinalResult?(text) }
                    } else {
                        DispatchQueue.main.async { self.onPartialResult?(text) }
                    }
                }
            }
            if let error {
                let code = (error as NSError).code
                // 1110 = no speech, 203 = retry — 조용히 무시
                if code != 1110 && code != 203 {
                    DispatchQueue.main.async { self.onError?(error.localizedDescription) }
                }
            }
        }

        let inputNode = audioEngine.inputNode
        let fmt = inputNode.outputFormat(forBus: 0)
        inputNode.installTap(onBus: 0, bufferSize: 1024, format: fmt) { [weak self] buffer, _ in
            self?.recognitionRequest?.append(buffer)
        }

        audioEngine.prepare()
        try audioEngine.start()
        print("[AppleASR] Started (ko-KR)")
    }
}
