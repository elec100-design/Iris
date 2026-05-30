import Foundation

// MARK: - Hermes Gateway Config
//
// main 프로필 전용 Gateway API Server (8642) 설정.
// healthURL: /v1/chat/completions (POST) — /v1/models는 401 발생으로 사용 금지.
//
struct HermesGatewayConfig {
    static let shared = HermesGatewayConfig()

    let host: String
    let port: Int
    let model: String
    let apiKey: String

    init(host: String = "100.83.59.60",
         port: Int = 8642,
         model: String = "gemini-3.1-flash-lite",
         apiKey: String = "Dbeka0119") {
        self.host = host
        self.port = port
        self.model = model
        self.apiKey = apiKey
    }

    var baseURL: URL { URL(string: "http://\(host):\(port)")! }
    var chatCompletionsURL: URL { baseURL.appendingPathComponent("v1/chat/completions") }
    var healthURL: URL { chatCompletionsURL } // POST health probe용 (401 회피)
}
