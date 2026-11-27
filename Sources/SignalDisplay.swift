import Combine
import Foundation

// This is only the visual subscriber. Capturing, analysis and physical output
// continue independently when the player is hidden or the app is inactive.
@MainActor
final class SignalDisplay: ObservableObject {
    private let clock: () -> Double
    private var latest = SignalFrame.empty
    private var receivedAt: Double
    private var origin = SignalFrame.empty.bands
    private var timestamp: Double
    private var releaseTask: Task<Void, Never>?
    @Published private(set) var isVisible = false
    @Published private(set) var settling = false
    @Published private(set) var frame = SignalFrame.empty

    init(clock: @escaping () -> Double = { ProcessInfo.processInfo.systemUptime }) {
        self.clock = clock
        let now = clock()
        timestamp = now
        receivedAt = now
    }

    func setVisible(_ visible: Bool) {
        guard visible != isVisible else { return }
        releaseTask?.cancel()
        releaseTask = nil
        if settling { settling = false }
        isVisible = visible
        if visible {
            // Resume from the newest packet, not the waveform from before hiding.
            // A stopped source therefore cannot leave a stale animated trace.
            let now = clock()
            let fresh = now >= receivedAt && now - receivedAt <= 0.25
            let resumed = latest.hasAudio && !fresh ? SignalFrame.empty : latest
            origin = resumed.bands
            timestamp = now
            frame = resumed
        }
    }

    func submit(_ next: SignalFrame) {
        latest = next
        let now = clock()
        receivedAt = now
        guard isVisible, frame.hasAudio || next.hasAudio else { return }
        origin = bands(at: now)
        timestamp = now
        let releasing = frame.hasAudio && !next.hasAudio
        frame = next
        if releasing {
            settling = true
            releaseTask?.cancel()
            releaseTask = Task { [weak self] in
                try? await Task.sleep(for: .milliseconds(750))
                guard !Task.isCancelled else { return }
                self?.settling = false
                self?.releaseTask = nil
            }
        } else if next.hasAudio && settling {
            releaseTask?.cancel()
            releaseTask = nil
            settling = false
        }
    }

    func bands(at now: Double) -> [Double] {
        let elapsed = max(0, now - timestamp)
        return zip(origin, frame.bands).map { start, target in
            let duration = target > start ? 0.065 : 0.18
            return target + (start - target) * exp(-elapsed / duration)
        }
    }

    deinit { releaseTask?.cancel() }
}
