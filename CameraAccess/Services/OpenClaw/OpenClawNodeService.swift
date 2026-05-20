/*
 * OpenClaw Node Service
 * 将 Ray-Ban Meta 眼镜作为 OpenClaw 设备节点
 * 通过 WebSocket 连接到本地 Gateway，暴露摄像头和音频能力
 */

import Foundation
import UIKit

// MARK: - Connection State

enum OpenClawConnectionState: Equatable {
    case disconnected
    case connecting
    case waitingForPairing
    case connected
    case error(String)

    static func == (lhs: OpenClawConnectionState, rhs: OpenClawConnectionState) -> Bool {
        switch (lhs, rhs) {
        case (.disconnected, .disconnected),
             (.connecting, .connecting),
             (.waitingForPairing, .waitingForPairing),
             (.connected, .connected):
            return true
        case (.error(let a), .error(let b)):
            return a == b
        default:
            return false
        }
    }
}

// MARK: - OpenClaw Node Service

class OpenClawNodeService: NSObject, ObservableObject {
    static let shared = OpenClawNodeService()

    // MARK: - Published State (Must be updated on MainThread)

    @Published var connectionState: OpenClawConnectionState = .disconnected
    @Published var isEnabled = UserDefaults.standard.bool(forKey: "openclaw_enabled")
    @Published var gatewayHost = UserDefaults.standard.string(forKey: "openclaw_host") ?? "127.0.0.1"
    @Published var gatewayPort = UserDefaults.standard.integer(forKey: "openclaw_port").nonZeroOrDefault(18789)

    // MARK: - Private Properties

    private var webSocket: URLSessionWebSocketTask?
    private var urlSession: URLSession?
    private var commandRouter: OpenClawCommandRouter?
    private var reconnectTask: Task<Void, Never>?
    private var tickTask: Task<Void, Never>?
    private var nodeId: String
    private var pendingNonce: String?
    private var shouldReconnect = false
    private var reconnectAttempts = 0
    private lazy var deviceIdentity = OpenClawDeviceIdentityStore.loadOrCreate()

    // Gateway token stored in Keychain
    private let keychainService = "com.smartview.glassai.openclaw"
    private let keychainAccount = "gateway_token"

    // Protocol
    private static let protocolVersion = 3
    private static let tickInterval: TimeInterval = 15
    private static let maxReconnectAttempts = 5

    // Supported commands
    private static let commands = [
        "camera.snap",
        "camera.list",
        "device.status",
        "device.info"
    ]

    private static let caps = [
        "camera"
    ]

    // MARK: - Init

    private override init() {
        // Generate stable device ID from device identifier
        let deviceId = UIDevice.current.identifierForVendor?.uuidString ?? UUID().uuidString
        self.nodeId = "rayban-\(deviceId.prefix(8))".lowercased()
        super.init()
    }

    // MARK: - Public Methods

    func setCommandRouter(_ router: OpenClawCommandRouter) {
        self.commandRouter = router
    }

    func connect() {
        guard connectionState != .connected && connectionState != .connecting else { return }

        shouldReconnect = true
        saveSettings()
        startConnection()
    }

    /// Send chat message to OpenClaw AI (with optional image)
    func sendChatMessage(_ text: String, image: UIImage? = nil) {
        guard connectionState == .connected else { return }

        var attachments: [[String: Any]] = []
        if let img = image, let jpegData = img.jpegData(compressionQuality: 0.7) {
            attachments.append([
                "type": "image",
                "mimeType": "image/jpeg",
                "content": jpegData.base64EncodedString()
            ])
        }

        var params: [String: Any] = [
            "sessionKey": chatSessionKey,
            "message": text,
            "idempotencyKey": UUID().uuidString
        ]
        if !attachments.isEmpty {
            params["attachments"] = attachments
        }

        let frame: [String: Any] = [
            "type": "req",
            "id": UUID().uuidString,
            "method": "chat.send",
            "params": params
        ]
        sendJSON(frame)
        print("[OpenClaw] Sent chat: \(text.prefix(50))")
    }

    /// Chat session key (reuse for context)
    private var chatSessionKey = "turbometa-chat"

    /// Chat event callback
    var onChatEvent: ((String) -> Void)?

    // MARK: - App-Initiated Capture (앱 주도 촬영)

    /// WSS를 통해 Gateway에 수동 촬영 명령을 전송
    func sendManualCaptureCommand() {
        guard connectionState == .connected else {
            print("[OpenClaw] sendManualCaptureCommand: not connected, skipping")
            return
        }
        let frame: [String: Any] = [
            "type": "command",
            "command": "camera.snap",
            "payload": [String: Any]()
        ]
        sendJSON(frame)
        print("[OpenClaw] Sent manual capture command via WSS")
    }

    func disconnect() {
        shouldReconnect = false
        reconnectTask?.cancel()
        reconnectTask = nil
        tickTask?.cancel()
        tickTask = nil
        webSocket?.cancel(with: .goingAway, reason: nil)
        webSocket = nil
        urlSession?.invalidateAndCancel()
        urlSession = nil
        
        DispatchQueue.main.async {
            self.connectionState = .disconnected
        }
        print("[OpenClaw] Disconnected")
    }

    func saveGatewayToken(_ token: String) {
        let data = token.data(using: .utf8) ?? Data()
        SecItemDelete([
            kSecClass: kSecClassGenericPassword,
            kSecAttrService: keychainService,
            kSecAttrAccount: keychainAccount
        ] as CFDictionary)

        guard !token.isEmpty else { return }
        SecItemAdd([
            kSecClass: kSecClassGenericPassword,
            kSecAttrService: keychainService,
            kSecAttrAccount: keychainAccount,
            kSecValueData: data
        ] as CFDictionary, nil)
    }

    func loadGatewayToken() -> String? {
        var result: AnyObject?
        let status = SecItemCopyMatching([
            kSecClass: kSecClassGenericPassword,
            kSecAttrService: keychainService,
            kSecAttrAccount: keychainAccount,
            kSecReturnData: true
        ] as CFDictionary, &result)
        guard status == errSecSuccess, let data = result as? Data else { return nil }
        return String(data: data, encoding: .utf8)
    }

    // MARK: - Connection Logic

    private func startConnection() {
        DispatchQueue.main.async {
            self.connectionState = .connecting
        }

        // wss: Tailscale MagicDNS hostname(.ts.net) + 443일 때만 사용.
        // 원시 IP 직접 연결 시 인증서 CN 불일치 → TLS 실패하므로 ws로 강제.
        // Tailscale 자체가 E2E 암호화하므로 내부망에서 ws는 안전.
        let isRawIP = gatewayHost.range(of: #"^\d{1,3}(\.\d{1,3}){3}$"#, options: .regularExpression) != nil
        let scheme = (!isRawIP && (gatewayHost.contains("ts.net") || gatewayPort == 443)) ? "wss" : "ws"
            
        var urlString = "\(scheme)://\(gatewayHost):\(gatewayPort)/"
            
        // Append token as query parameter if available
        if let token = loadGatewayToken(), !token.isEmpty {
            urlString += "?token=\(token)"
        }
        guard let url = URL(string: urlString) else {
            DispatchQueue.main.async {
                self.connectionState = .error("Invalid gateway URL")
            }
            return
        }

        print("[OpenClaw] Connecting to \(urlString)")

        let config = URLSessionConfiguration.default
        config.timeoutIntervalForRequest = 10
        // 绕过系统代理，直连局域网 Gateway
        config.connectionProxyDictionary = [:]
        let delegateQueue = OperationQueue()
        delegateQueue.name = "openclaw-ws"
        urlSession = URLSession(configuration: config, delegate: self, delegateQueue: delegateQueue)

        webSocket = urlSession?.webSocketTask(with: url)
        webSocket?.maximumMessageSize = 16 * 1024 * 1024
        webSocket?.resume()
            // receiveMessage() is called in didOpen delegate
    }
    
    private func saveSettings() {
        UserDefaults.standard.set(isEnabled, forKey: "openclaw_enabled")
        UserDefaults.standard.set(gatewayHost, forKey: "openclaw_host")
        UserDefaults.standard.set(gatewayPort, forKey: "openclaw_port")
    }

    // MARK: - WebSocket Messaging

    private func receiveMessage() {
        webSocket?.receive { [weak self] result in
            switch result {
            case .success(let message):
                self?.handleMessage(message)
                self?.receiveMessage()
            case .failure(let error):
                print("[OpenClaw] Receive error: \(error.localizedDescription)")
                self?.handleDisconnect()
            }
        }
    }

    private func sendJSON(_ dict: [String: Any]) {
        guard let data = try? JSONSerialization.data(withJSONObject: dict),
              let text = String(data: data, encoding: .utf8) else { return }

        webSocket?.send(.string(text)) { error in
            if let error {
                print("[OpenClaw] Send error: \(error.localizedDescription)")
            }
        }
    }

    // MARK: - Message Handling

    private func handleMessage(_ message: URLSessionWebSocketTask.Message) {
        let text: String
        switch message {
        case .string(let s):
            text = s
            print("[OpenClaw] RAW MSG: \(s.prefix(500))")
        case .data(let d):
            text = String(data: d, encoding: .utf8) ?? ""
            print("[OpenClaw] RAW DATA: \(d.count) bytes")
        @unknown default: return
        }

        guard let data = text.data(using: .utf8),
              let json = try? JSONSerialization.jsonObject(with: data) as? [String: Any] else { return }

        let type = json["type"] as? String
        let method = json["method"] as? String
        let event = json["event"] as? String

        // OpenClaw protocol: type="event", event="connect.challenge"
        if type == "event" && event == "connect.challenge" {
            if let payload = json["payload"] as? [String: Any],
               let nonce = payload["nonce"] as? String {
                handleChallenge(nonce: nonce)
            }
            return
        }

        // Response frame
        if type == "res" {
            let ok = json["ok"] as? Bool ?? false
            if ok {
                handleHelloOk(json: json)
            } else {
                handleResponse(json: json)
            }
            return
        }

        switch type {
        case "evt", "event":
            handleEvent(method: event ?? method, json: json)
        case "req", "request":
            handleRequest(json: json)
        case "res", "response":
            handleResponse(json: json)
        default:
            print("[OpenClaw] Unknown message type: \(type ?? "nil")")
        }
    }

    // MARK: - Handshake

    private func handleChallenge(nonce: String) {
        print("[OpenClaw] Received challenge, nonce: \(nonce.prefix(8))...")
        pendingNonce = nonce

        let token = loadGatewayToken() ?? ""
        let role = "operator"
        let scopes = ["operator.read", "operator.write", "operator.admin"]
        let clientId = "openclaw-ios"
        let clientMode = "node"
        let platform = "ios"
        let signedAtMs = Int64(Date().timeIntervalSince1970 * 1000)

        // Build device signature (v3)
        let signature = deviceIdentity.sign(
            clientId: clientId,
            clientMode: clientMode,
            role: role,
            scopes: scopes,
            signedAtMs: signedAtMs,
            token: token.isEmpty ? nil : token,
            nonce: nonce,
            platform: platform,
            deviceFamily: nil
        )

        var auth: [String: Any] = [:]
        if !token.isEmpty {
            auth["token"] = token
        }

        let connectParams: [String: Any] = [
            "minProtocol": Self.protocolVersion,
            "maxProtocol": Self.protocolVersion,
            "client": [
                "id": clientId,
                "displayName": "Ray-Ban Meta Glasses",
                "version": "2.0.0",
                "mode": clientMode,
                "platform": platform,
                "modelIdentifier": UIDevice.current.model
            ] as [String: Any],
            "role": role,
            "scopes": scopes,
            "caps": Self.caps,
            "commands": Self.commands,
            "auth": auth,
            "device": [
                "id": deviceIdentity.deviceId,
                "publicKey": deviceIdentity.publicKeyBase64Url,
                "signature": signature,
                "signedAt": signedAtMs,
                "nonce": nonce
            ] as [String: Any]
        ] as [String: Any]

        let frame: [String: Any] = [
            "type": "req",
            "id": UUID().uuidString,
            "method": "connect",
            "params": connectParams
        ]

        print("[OpenClaw] Sending connect request (node + device identity)...")
        sendJSON(frame)
    }

    private func handleHelloOk(json: [String: Any]) {
        print("[OpenClaw] Connected to gateway!")

        DispatchQueue.main.async {
            self.connectionState = .connected
            self.reconnectAttempts = 0
        }
        self.startTickWatchdog()
    }

    // MARK: - Event Handling

    private func handleEvent(method: String?, json: [String: Any]) {
        guard let method else { return }

        // 모든 이벤트 로깅 (물리 버튼, 상태 변경 등 Gateway 이벤트 추적용)
        let payloadSnippet: String
        if let payload = json["payload"] as? [String: Any] {
            let keys = payload.keys.sorted().joined(separator: ",")
            payloadSnippet = "keys=[\(keys)]"
        } else {
            payloadSnippet = "no payload"
        }
        print("[OpenClaw] EVT \(method) | \(payloadSnippet)")

        switch method {
        case "node.invoke.request", "node.invoke":
            print("[OpenClaw] >>> INVOKE RECEIVED: \(method)")
            handleInvokeRequest(json: json)
        case "chat":
            if let payload = json["payload"] as? [String: Any],
               let state = payload["state"] as? String,
               let message = payload["message"] as? [String: Any],
               let content = message["content"] as? [[String: Any]] {
                // Extract text from content array
                let text = content.compactMap { $0["text"] as? String }.joined()
                if !text.isEmpty {
                    DispatchQueue.main.async {
                        self.onChatEvent?(state == "final" ? "[[FINAL]]\(text)" : text)
                    }
                }
            }
        case "tick", "health":
            break
        default:
            break
        }
    }

    private func handleRequest(json: [String: Any]) {
        let method = json["method"] as? String ?? ""
        let id = json["id"] as? String ?? ""

        switch method {
        case "node.invoke":
            if let params = json["params"] as? [String: Any] {
                handleInvokeFromRequest(id: id, params: params)
            }
        default:
            print("[OpenClaw] Request: \(method)")
            sendJSON([
                "type": "res",
                "id": id,
                "ok": false,
                "error": ["code": "UNSUPPORTED", "message": "Unknown method: \(method)"]
            ])
        }
    }

    private func handleResponse(json: [String: Any]) {
        let id = json["id"] as? String ?? ""
        let ok = json["ok"] as? Bool ?? false

        if !ok {
            let error = json["error"] as? [String: Any]
            let code = error?["code"] as? String ?? ""
            let message = error?["message"] as? String ?? ""
            print("[OpenClaw] Response error for \(id): \(code) - \(message)")

            if code == "NOT_PAIRED" {
                DispatchQueue.main.async {
                    self.connectionState = .waitingForPairing
                }
            }
        }
    }

    // MARK: - Invoke Handling

    private func handleInvokeRequest(json: [String: Any]) {
        guard let params = json["params"] as? [String: Any] else { return }
        let invokeId = params["id"] as? String ?? ""
        handleInvokeFromRequest(id: invokeId, params: params)
    }

    private func handleInvokeFromRequest(id: String, params: [String: Any]) {
        let command = params["command"] as? String ?? ""
        let cmdParams = params["params"] as? [String: Any]
            ?? (params["paramsjson"] as? String).flatMap { str in
                try? JSONSerialization.jsonObject(with: Data(str.utf8)) as? [String: Any]
            }

        print("[OpenClaw] Invoke: \(command) (id: \(id.prefix(8)))")

        let request = OpenClawNodeInvokeRequest(
            id: id,
            command: command,
            params: cmdParams,
            timeoutMs: params["timeoutms"] as? Int ?? params["timeoutMs"] as? Int
        )

        Task { @MainActor in
            let result = await self.commandRouter?.handleCommand(request)
                ?? self.makeErrorResult(id: id, code: "NO_ROUTER", message: "Command router not configured")
            self.sendInvokeResult(result)
        }
    }

    private func sendInvokeResult(_ result: OpenClawNodeInvokeResult) {
        var payload: [String: Any] = [
            "id": result.id,
            "nodeId": nodeId,
            "ok": result.ok
        ]

        if let p = result.payload {
            // For large payloads (images), use payloadjson
            if let data = try? JSONEncoder().encode(p),
               let jsonStr = String(data: data, encoding: .utf8) {
                payload["payloadjson"] = jsonStr
            }
        }

        if let error = result.error {
            var errDict: [String: Any] = [:]
            if let code = error.code { errDict["code"] = code }
            if let message = error.message { errDict["message"] = message }
            payload["error"] = errDict
        }

        sendJSON([
            "type": "req",
            "id": UUID().uuidString,
            "method": "node.invoke.result",
            "params": payload
        ])
    }

    private func makeErrorResult(id: String, code: String, message: String) -> OpenClawNodeInvokeResult {
        return OpenClawNodeInvokeResult(
            id: id,
            nodeId: nodeId,
            ok: false,
            payload: nil,
            error: OpenClawError(code: code, message: message)
        )
    }

    // MARK: - Keepalive

    private func startTickWatchdog() {
            // 기존 작업이 있다면 취소합니다.
            tickTask?.cancel()
            
            // 서버 버전 호환성 문제로 'tick' 메소드 전송을 중단합니다.
            tickTask = Task {
                print("[OpenClaw] Tick watchdog disabled to prevent 'unknown method' errors.")
                
                while !Task.isCancelled {
                    // 단순히 루프만 돌며 태스크를 유지합니다.
                    try? await Task.sleep(nanoseconds: 30 * 1_000_000_000) // 30초 대기
                    if Task.isCancelled { break }
                    
                    // 실제 전송 로직이 없으므로 self를 참조할 필요가 없습니다.
                }
            }
        }

    // MARK: - Reconnection

    private func handleDisconnect() {
        // Need to read/write state carefully
        let isCurrentlyDisconnected = DispatchQueue.main.sync {
            self.connectionState == .disconnected
        }
        guard !isCurrentlyDisconnected else { return }

        webSocket = nil
        urlSession?.invalidateAndCancel()
        urlSession = nil
        tickTask?.cancel()

        guard shouldReconnect else {
            DispatchQueue.main.async {
                self.connectionState = .disconnected
            }
            return
        }

        reconnectAttempts += 1
        if reconnectAttempts > Self.maxReconnectAttempts {
            print("[OpenClaw] Max reconnect attempts reached, giving up")
            DispatchQueue.main.async {
                self.connectionState = .error("연결 실패, \(Self.maxReconnectAttempts)회 재시도함")
                self.shouldReconnect = false
            }
            return
        }

        let delay = min(Double(1 << reconnectAttempts), 30.0) // 2, 4, 8, 16, 30s
        print("[OpenClaw] Reconnect attempt \(reconnectAttempts)/\(Self.maxReconnectAttempts) in \(delay)s")
        DispatchQueue.main.async {
            self.connectionState = .disconnected
        }
        scheduleReconnect(delay: delay)
    }

    private func scheduleReconnect(delay: TimeInterval) {
        reconnectTask?.cancel()
        reconnectTask = Task { [weak self] in
            try? await Task.sleep(nanoseconds: UInt64(delay * 1_000_000_000))
            guard !Task.isCancelled else { return }

            Task { @MainActor in
                guard let self, self.shouldReconnect else { return }
                self.startConnection()
            }
        }
    }
}

// MARK: - URLSessionWebSocketDelegate

extension OpenClawNodeService: URLSessionWebSocketDelegate {
    func urlSession(_ session: URLSession, webSocketTask: URLSessionWebSocketTask, didOpenWithProtocol protocol: String?) {
        print("[OpenClaw] WebSocket opened, starting receive loop")
        // Start receiving immediately
        webSocketTask.receive { [weak self] result in
            switch result {
            case .success(let message):
                self?.handleMessage(message)
                self?.receiveMessage()
            case .failure(let error):
                print("[OpenClaw] First receive FAILED: \(error) | \(error.localizedDescription)")
            }
        }
    }

    func urlSession(_ session: URLSession, webSocketTask: URLSessionWebSocketTask, didCloseWith closeCode: URLSessionWebSocketTask.CloseCode, reason: Data?) {
        print("[OpenClaw] WebSocket closed: \(closeCode.rawValue)")
        handleDisconnect()
    }

    func urlSession(_ session: URLSession, task: URLSessionTask, didCompleteWithError error: (any Error)?) {
        if let error {
            print("[OpenClaw] Connection error: \(error.localizedDescription)")
            DispatchQueue.main.async {
                self.connectionState = .error(error.localizedDescription)
            }
            handleDisconnect()
        }
    }
}

// MARK: - Helpers

private extension Int {
    func nonZeroOrDefault(_ defaultValue: Int) -> Int {
        return self != 0 ? self : defaultValue
    }
}
