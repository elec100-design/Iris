/*
 * ConnectionManager
 * 연결 관리 프로토콜 + Mock 구현 (Simulator/Preview용)
 */

import Foundation
import SwiftUI

// MARK: - Protocol

@MainActor
protocol ConnectionManagerProtocol: AnyObject {
    var isConnected: Bool { get }
    func connect() async throws
    func disconnect() async
}

// MARK: - Mock (Simulator / SwiftUI Preview)

@MainActor
final class MockConnectionManager: ConnectionManagerProtocol, ObservableObject {
    @Published var isConnected = true

    func connect() async throws {}
    func disconnect() async {}
}

// MARK: - Environment Key

private struct ConnectionManagerKey: EnvironmentKey {
    static let defaultValue: (any ConnectionManagerProtocol)? = nil
}

extension EnvironmentValues {
    var connectionManager: (any ConnectionManagerProtocol)? {
        get { self[ConnectionManagerKey.self] }
        set { self[ConnectionManagerKey.self] = newValue }
    }
}
