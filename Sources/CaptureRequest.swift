import CoreAudio
import Foundation

enum CaptureFault: Error { case routeChanged }

/// Core Audio may wait for the system while opening a device. Keep that work
/// away from the render queue, with bounded admission and cancellable handoff.
final class CaptureRequest {
    private final class State {
        let lock = NSLock()
        var cancelled = false
        var result: Result<AudioTap, Error>?
    }
    private static let workers = DispatchQueue(label: "songwave.capture-start", qos: .userInitiated, attributes: .concurrent)
    private static let admission = NSLock()
    private static var inFlight = 0
    private let state: State

    init?(description: CATapDescription, mute: Bool) {
        Self.admission.lock()
        guard Self.inFlight < 4 else { Self.admission.unlock(); return nil }
        Self.inFlight += 1
        Self.admission.unlock()
        let state = State()
        self.state = state
        Self.workers.async {
            defer {
                Self.admission.lock(); Self.inFlight -= 1; Self.admission.unlock()
            }
            state.lock.lock()
            let cancelled = state.cancelled
            state.lock.unlock()
            guard !cancelled else { return }
            let result = Result { try AudioTap(description: description, mute: mute) }
            state.lock.lock()
            if !state.cancelled { state.result = result }
            state.lock.unlock()
            // A late cancelled result is released here, never installed into a
            // replacement session and never sent to a motor.
        }
    }

    /// Deterministic I/O edge for offline router tests; production uses the
    /// bounded worker initializer above.
    init(result: Result<AudioTap, Error>?) { state = State(); state.result = result }

    func takeResult() -> Result<AudioTap, Error>? {
        state.lock.lock(); defer { state.lock.unlock() }
        guard !state.cancelled else { return nil }
        let result = state.result
        state.result = nil
        return result
    }

    func cancel() {
        state.lock.lock(); state.cancelled = true; state.lock.unlock()
    }
    deinit { cancel() }
}
