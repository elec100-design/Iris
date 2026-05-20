import Foundation
import CoreLocation
import UIKit

struct NavParsedResult {
    let origin: String?   // nil → Google Maps uses current location
    let destination: String
    let mode: String      // driving | transit | walking | bicycling
}

@MainActor
@Observable
final class GoogleMapsNavigator {
    static let shared = GoogleMapsNavigator()

    // MARK: - Natural Language Entry Point

    /// Parse natural language with Gemini, then open Google Maps. Returns a chat-ready message.
    func openWithNaturalLanguage(text: String) async -> String {
        let parsed = await parseNavigationCommand(text: text)

        let destination = parsed?.destination ?? text
        let origin = parsed?.origin
        let mode = parsed?.mode ?? "transit"

        return openGoogleMaps(origin: origin, destination: destination, mode: mode)
    }

    // MARK: - Core Open

    @discardableResult
    func openGoogleMaps(origin: String?, destination: String, mode: String = "transit") -> String {
        // Universal link — Safari fallback works when Google Maps isn't installed
        var queryItems: [URLQueryItem] = [
            URLQueryItem(name: "api", value: "1"),
            URLQueryItem(name: "destination", value: destination),
            URLQueryItem(name: "travelmode", value: mode)
        ]
        if let origin, !origin.isEmpty {
            queryItems.append(URLQueryItem(name: "origin", value: origin))
        }

        var components = URLComponents(string: "https://www.google.com/maps/dir/")!
        components.queryItems = queryItems

        guard let url = components.url else { return "길찾기 URL 생성 실패" }

        UIApplication.shared.open(url)

        let modeLabel: String
        switch mode {
        case "transit":    modeLabel = "🚇 대중교통"
        case "walking":    modeLabel = "🚶 도보"
        case "bicycling":  modeLabel = "🚴 자전거"
        default:           modeLabel = "🚗 자동차"
        }
        let originLabel = origin ?? "현재 위치"
        return "Google Maps로 경로를 열었습니다.\n\(originLabel) → \(destination) (\(modeLabel))"
    }

    // MARK: - Gemini NL Parsing

    private func parseNavigationCommand(text: String) async -> NavParsedResult? {
        let prompt = """
사용자 명령에서 출발지, 목적지, 이동수단을 추출해서 JSON만 반환해. 다른 설명 없이 JSON만.
출발지가 명시되지 않으면 "origin": null.
이동수단은 driving/transit/walking/bicycling 중 하나. 명시 없으면 transit.

사용자 명령: \(text)

반환 형식: {"origin": "출발지 또는 null", "destination": "목적지", "mode": "transit"}
"""
        guard let url = URL(string: "\(VisionAPIConfig.baseURL)/chat/completions") else { return nil }

        var req = URLRequest(url: url)
        req.httpMethod = "POST"
        req.timeoutInterval = 10
        VisionAPIConfig.headers(with: VisionAPIConfig.apiKey).forEach {
            req.setValue($0.value, forHTTPHeaderField: $0.key)
        }

        let body: [String: Any] = [
            "model": VisionAPIConfig.model,
            "messages": [["role": "user", "content": prompt]]
        ]
        guard let httpBody = try? JSONSerialization.data(withJSONObject: body) else { return nil }
        req.httpBody = httpBody

        guard let (data, _) = try? await URLSession.shared.data(for: req) else { return nil }

        guard
            let json = try? JSONSerialization.jsonObject(with: data) as? [String: Any],
            let choices = json["choices"] as? [[String: Any]],
            let message = choices.first?["message"] as? [String: Any],
            let content = message["content"] as? String
        else { return nil }

        let cleaned = content
            .trimmingCharacters(in: .whitespacesAndNewlines)
            .replacingOccurrences(of: "```json", with: "")
            .replacingOccurrences(of: "```", with: "")
            .trimmingCharacters(in: .whitespacesAndNewlines)

        guard
            let jsonData = cleaned.data(using: .utf8),
            let parsed = try? JSONSerialization.jsonObject(with: jsonData) as? [String: Any],
            let dest = parsed["destination"] as? String, !dest.isEmpty
        else { return nil }

        let rawOrigin = parsed["origin"] as? String
        let resolvedOrigin: String?
        if let o = rawOrigin, o != "null", !o.isEmpty {
            resolvedOrigin = o
        } else {
            resolvedOrigin = nil
        }

        return NavParsedResult(
            origin: resolvedOrigin,
            destination: dest,
            mode: parsed["mode"] as? String ?? "transit"
        )
    }

    // MARK: - Legacy Compatibility

    func navigate(to destination: String, from currentLocation: CLLocation? = nil) {
        openGoogleMaps(origin: nil, destination: destination, mode: "transit")
    }

    func startVoiceNavigation(destination: String) async {
        print("🗺️ 네비게이션 시작: \(destination)")
        navigate(to: destination)
    }
}
