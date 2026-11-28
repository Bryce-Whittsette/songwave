import CoreAudio
import Foundation

enum CaptureFault: Error { case routeChanged }

/// Core Audio may wait for the system while opening a device. Keep that work
/// away from the render queue, with bounded admission and cancellable handoff.
final class CaptureRequest {
    enum Failure: LocalizedError {
        case busy, timedOut
        var errorDescription: String? {
            switch self {
            case .busy:
                return "macOS is still opening earlier audio capture requests. Wait, then retry. If it does not recover, quit and reopen SongWave."
            case .timedOut:
                return "macOS has not finished opening audio capture. Play audio and finish any recording permission prompt, then retry in Listening help."
            }
        }
    }
    private final class State {
        let lock = NSLock()
        var cancelled = false
        var result: Result<AudioTap, Error>?
        var isCancelled: Bool {
            lock.lock(); defer { lock.unlock() }
            return cancelled
        }
    }
    private static let workers = DispatchQueue(label: "songwave.capture-start", qos: .userInitiated, attributes: .concurrent)
    private static let admission = NSLock()
    private static var inFlight = 0
    private let state: State

    convenience init?(description: CATapDescription, mute: Bool) {
        self.init(description: { description }, mute: mute)
    }

    init?(description: @escaping () -> CATapDescription, mute: Bool) {
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
            guard !state.isCancelled else { return }
            let prepared = description()
            guard !state.isCancelled else { return }
            let result = Result { try AudioTap(description: prepared, mute: mute) }
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

    /// Explicit access checks share the same admission limit as listening.
    /// The system call may outlive this wait. Access checks open unmuted and
    /// never start physical output, including when their result arrives late.
    func wait(timeout: Duration) async throws -> AudioTap {
        defer { cancel() }
        let deadline = ContinuousClock.now.advanced(by: timeout)
        while true {
            try Task.checkCancellation()
            if state.isCancelled { throw CancellationError() }
            if let result = takeResult() { return try result.get() }
            let remaining = ContinuousClock.now.duration(to: deadline)
            guard remaining > .zero else { throw Failure.timedOut }
            try await Task.sleep(for: min(remaining, .milliseconds(100)))
        }
    }

    func cancel() {
        state.lock.lock(); state.cancelled = true; state.lock.unlock()
    }
    deinit { cancel() }
}
