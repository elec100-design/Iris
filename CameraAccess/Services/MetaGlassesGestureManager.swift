import Foundation
import Combine

// Bluetooth Double Tap 등 Meta Glasses 제스처를 앱 전체에 브로드캐스트합니다.
// Bluetooth delegate에서 제스처 수신 시 handleGesture(.doubleTap)을 호출하세요.
final class MetaGlassesGestureManager: @unchecked Sendable {
    static let shared = MetaGlassesGestureManager()

    private let gestureSubject = PassthroughSubject<GestureType, Never>()

    private init() {}

    var gestureStream: AsyncStream<GestureType> {
        AsyncStream { continuation in
            let cancellable = self.gestureSubject.sink { continuation.yield($0) }
            continuation.onTermination = { _ in cancellable.cancel() }
        }
    }

    // Bluetooth delegate 또는 테스트에서 호출
    func handleGesture(_ gesture: GestureType) {
        gestureSubject.send(gesture)
    }
}

extension Notification.Name {
    static let metaGlassTouchInterrupt = Notification.Name("metaGlassTouchInterrupt")
}
