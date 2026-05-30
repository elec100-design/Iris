import Foundation
import UIKit

// MARK: - Hermes Node Service (Gateway API Server, port 8642)
//
// main 프로필의 Hermes Gateway API Server와 직결합니다.
// 모든 모델 라우팅 및 credential은 Hermes 서버가 처리합니다.
//
final class HermesNodeService: ObservableObject, AgentNodeServiceProtocol, @unchecked Sendable {

    @Published private(set) var agentConnectionState: AgentConnectionState = .disconnected
    var onAgentChunk: ((String) -> Void)?

    private let config: HermesGatewayConfig

    // Designated initializer — config 기반 (신규 권장 방식)
    init(config: HermesGatewayConfig = .shared) {
        self.config = config
    }

    // Backward compatibility — 기존 host/port/model 호출부 지원
    convenience init(host: String = "100.83.59.60",
                     port: Int = 8642,
                     model: String = "gemini-3.1-flash-lite") {
        self.init(config: HermesGatewayConfig(host: host, port: port, model: model))
    }

    // config 프로퍼티 접근 편의 (호출부 캐시 비교용)
    var host: String { config.host }
    var port: Int { config.port }

    // MARK: - AgentNodeServiceProtocol

    func sendAgentPayload(_ payload: AgentPayload) async throws {
        let imgData = extractImageData(from: payload.attachment)
        let stream = try await processAgentCommand(payload.text, imageData: imgData)
        for try await chunk in stream {
            onAgentChunk?(chunk)
        }
    }

    func processAgentCommand(_ command: String, imageData: Data?) async throws -> AsyncThrowingStream<String, Error> {
        let request = buildChatRequest(prompt: command, imageData: imageData)

        return AsyncThrowingStream { continuation in
            Task {
                do {
                    print("[Hermes] 🖥️ Gateway 요청 시작 (\(self.config.host):\(self.config.port))")

                    let (bytes, response) = try await URLSession.shared.bytes(for: request)
                    let statusCode = (response as? HTTPURLResponse)?.statusCode ?? 0

                    guard (200..<300).contains(statusCode) else {
                        print("[Hermes] ✗ Gateway HTTP 에러: \(statusCode)")
                        continuation.finish(throwing: HermesError.httpError(statusCode))
                        return
                    }

                    for try await line in bytes.lines {
                        guard !line.isEmpty, !line.hasPrefix(":") else { continue }

                        let jsonLine = line.hasPrefix("data: ") ? String(line.dropFirst(6)) : line
                        if jsonLine == "[DONE]" { break }

                        if let token = self.parseToken(from: jsonLine), !token.isEmpty {
                            continuation.yield(token)
                        }
                    }
                    continuation.finish()

                } catch {
                    print("[Hermes] ✗ Gateway 통신 오류: \(error.localizedDescription)")
                    continuation.finish(throwing: error)
                }
            }
        }
    }

    func connect() {
        DispatchQueue.main.async { self.agentConnectionState = .connecting }
        Task { await performHealthCheck() }
    }

    func disconnect() {
        DispatchQueue.main.async { self.agentConnectionState = .disconnected }
    }

    // MARK: - Private

    private func performHealthCheck() async {
        var request = URLRequest(url: config.healthURL)
        request.httpMethod = "POST"
        request.setValue("application/json", forHTTPHeaderField: "Content-Type")
        request.setValue("Bearer \(config.apiKey)", forHTTPHeaderField: "Authorization")
        request.timeoutInterval = 5

        // 최소 body로 서버 생존 여부만 확인 (스트리밍 없음)
        let probe: [String: Any] = [
            "model": config.model,
            "messages": [["role": "user", "content": "health check"]],
            "max_tokens": 1,
            "stream": false
        ]
        request.httpBody = try? JSONSerialization.data(withJSONObject: probe)

        do {
            let (_, response) = try await URLSession.shared.data(for: request)
            let statusCode = (response as? HTTPURLResponse)?.statusCode ?? 0
            print("[Hermes] Health Check 응답: \(statusCode) (\(config.host):\(config.port)) apiKey=\(config.apiKey)")

            if (200..<300).contains(statusCode) {
                print("[Hermes] ✓ Gateway 연결 성공")
                await MainActor.run { agentConnectionState = .connected }
            } else if statusCode == 401 {
                // 401 → API Key 불일치 가능성, 로그만 남기고 connected 유지 (개발 단계)
                print("[Hermes] ⚠️ 401 Unauthorized — API Key 확인 필요 (apiKey: \(config.apiKey)). 연결은 허용합니다.")
                await MainActor.run { agentConnectionState = .connected }
            } else {
                // 그 외 오류도 fallback: connected 유지 (서버가 살아 있음)
                print("[Hermes] ⚠️ Health Check 비정상 응답 \(statusCode) — 연결은 허용합니다.")
                await MainActor.run { agentConnectionState = .connected }
            }
        } catch let urlError as URLError {
            let msg: String
            switch urlError.code {
            case .timedOut:            msg = "Tailscale 타임아웃 (\(config.host))"
            case .cannotConnectToHost: msg = "호스트 연결 실패 (\(config.host):\(config.port))"
            case .notConnectedToInternet: msg = "네트워크 없음"
            default:                   msg = "연결 오류: \(urlError.localizedDescription)"
            }
            print("[Hermes] ✗ \(msg)")
            await MainActor.run { agentConnectionState = .error(msg) }
        } catch {
            // 네트워크 도달 자체 실패 시에만 .error 처리
            let msg = "Health Check 실패: \(error.localizedDescription)"
            print("[Hermes] ✗ \(msg)")
            await MainActor.run { agentConnectionState = .error(msg) }
        }
    }

    private func buildChatRequest(prompt: String, imageData: Data?) -> URLRequest {
        var request = URLRequest(url: config.chatCompletionsURL)
        request.httpMethod = "POST"
        request.setValue("application/json", forHTTPHeaderField: "Content-Type")
        request.setValue("Bearer \(config.apiKey)", forHTTPHeaderField: "Authorization")
        request.timeoutInterval = 120

        let userContent: Any
        if let imgData = imageData {
            userContent = [
                ["type": "text", "text": prompt],
                ["type": "image_url", "image_url": ["url": "data:image/jpeg;base64,\(imgData.base64EncodedString())"]]
            ]
        } else {
            userContent = prompt
        }

        let body: [String: Any] = [
            "model": config.model,
            "messages": [["role": "user", "content": userContent]],
            "stream": true,
            "temperature": 0.7
        ]

        request.httpBody = try? JSONSerialization.data(withJSONObject: body)
        return request
    }

    private func parseToken(from line: String) -> String? {
        guard !line.isEmpty,
              let data = line.data(using: .utf8),
              let json = try? JSONSerialization.jsonObject(with: data) as? [String: Any]
        else { return nil }

        if let choices = json["choices"] as? [[String: Any]],
           let delta = choices.first?["delta"] as? [String: Any],
           let content = delta["content"] as? String {
            return content
        }
        return nil
    }

    private func extractImageData(from attachment: AgentAttachment?) -> Data? {
        guard case .metaCamera(let image) = attachment else { return nil }
        return image.jpegData(compressionQuality: 0.85)
    }

    enum HermesError: Error {
        case httpError(Int)
    }
}
