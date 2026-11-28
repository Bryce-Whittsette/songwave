import Combine
import Foundation

// This is only the visual subscriber. Capturing, analysis and physical output
// continue independently when the player is hidden or the app is inactive.
@MainActor
final class SignalDisplay: ObservableObject {
    private let primaryOwner = UUID()
    private var visibleOwners: Set<UUID> = []
    private let clock: () -> Double
    private let beatSleep: () async -> Void
    private var beatAt = -Double.infinity
    private var beatStrength = 0.0
    private var latest = SignalFrame.empty
    private var receivedAt: Double
    private var origin = SignalFrame.empty.bands
    private var timestamp: Double
    private var beatReleaseTask: Task<Void, Never>?
    @Published private(set) var recentBeat = false
    private var releaseTask: Task<Void, Never>?
    @Published private(set) var isVisible = false
    @Published private(set) var settling = false
    @Published private(set) var frame = SignalFrame.empty

    init(clock: @escaping () -> Double = { ProcessInfo.processInfo.systemUptime },
         beatSleep: @escaping () async -> Void = { try? await Task.sleep(for: .milliseconds(250)) }) {
        self.clock = clock
        self.beatSleep = beatSleep
        let now = clock()
        timestamp = now
        receivedAt = now
    }

    func setVisible(_ value: Bool, owner: UUID? = nil) {
        let owner = owner ?? primaryOwner
        if value { visibleOwners.insert(owner) } else { visibleOwners.remove(owner) }
        let visible = !visibleOwners.isEmpty
        guard visible != isVisible else { return }
        beatReleaseTask?.cancel(); beatReleaseTask = nil
        if recentBeat { recentBeat = false }
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
            if fresh && resumed.hasAudio && resumed.beatStrength > 0 { retainBeat() }
        }
    }

    func submit(_ next: SignalFrame) {
        latest = next
        let now = clock()
        if !next.hasAudio { beatStrength = 0 }
        else if next.beatStrength.isFinite && next.beatStrength > 0 { beatAt = now; beatStrength = min(1, next.beatStrength) }
        receivedAt = now
        guard isVisible, frame.hasAudio || next.hasAudio else { return }
        if !next.hasAudio { beatReleaseTask?.cancel(); beatReleaseTask = nil; if recentBeat { recentBeat = false } }
        else if next.beatStrength.isFinite && next.beatStrength > 0 { retainBeat() }
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

    private func retainBeat() {
        if !recentBeat { recentBeat = true }
        beatReleaseTask?.cancel()
        let sleep = beatSleep
        beatReleaseTask = Task { [weak self] in
            await sleep()
            guard !Task.isCancelled else { return }
            self?.recentBeat = false; self?.beatReleaseTask = nil
        }
    }

    func beat(at now: Double) -> Double {
        let age = now - beatAt
        guard isVisible, age >= 0, age < 0.22 else { return 0 }
        return beatStrength * max(0, 1 - age / 0.22)
    }

    // The UI marks an existing event consistently, even when its reported
    // strength is low. The separate level meter communicates amplitude.
    // This never changes the event, audio analysis or physical haptic output.
    func beatPulse(at now: Double) -> Double {
        let age = now - beatAt
        guard isVisible, beatStrength > 0, age >= 0, age < 0.22 else { return 0 }
        return max(0, 1 - age / 0.22)
    }

    func bands(at now: Double) -> [Double] {
        let elapsed = max(0, now - timestamp)
        return zip(origin, frame.bands).map { start, target in
            let duration = target > start ? 0.065 : 0.18
            return target + (start - target) * exp(-elapsed / duration)
        }
    }

    deinit { releaseTask?.cancel(); beatReleaseTask?.cancel() }
}
