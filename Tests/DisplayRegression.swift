import Combine
import Foundation

// Hold beat expiries until the test releases them. Runner scheduling delays
// cannot turn a valid renewed beat into a false timing failure.
@MainActor private final class BeatSleeps {
    var pending: [CheckedContinuation<Void, Never>] = []
    var resumed = 0
    func sleep() async {
        guard !Task.isCancelled else { return }
        await withCheckedContinuation { pending.append($0) }
        resumed += 1
    }
    func releaseFirst() { pending.removeFirst().resume() }
}

private func requireDisplay(_ condition: @autoclosure () -> Bool, _ message: String = "",
                            file: StaticString = #filePath, line: UInt = #line) {
    guard condition() else {
        FileHandle.standardError.write(Data("Display assertion failed at \(file):\(line): \(message)\n".utf8))
        exit(1)
    }
}

@main struct DisplayRegression {
    @MainActor static func wait(_ condition: () -> Bool) async throws {
        let deadline = ContinuousClock.now.advanced(by: .seconds(3))
        while !condition() && ContinuousClock.now < deadline { await Task.yield() }
        requireDisplay(condition(), "A controlled display task did not complete")
    }
    @MainActor static func main() async throws {
        var now = 0.0
        let beatSleeps = BeatSleeps()
        let display = SignalDisplay(clock: { now }, beatSleep: { await beatSleeps.sleep() })
        var frames = 0, changes = 0
        let frameObserver = display.$frame.dropFirst().sink { _ in frames += 1 }
        let changeObserver = display.objectWillChange.sink { changes += 1 }
        func signal(_ strength: Double) -> SignalFrame {
            SignalFrame(tones: [], level: strength, bands: Array(repeating: strength, count: 44),
                        inputRMS: 0.01, hasAudio: true)
        }

        for _ in 0..<5_000 { display.submit(signal(0.2)) }
        requireDisplay(frames == 0 && changes == 0, "A hidden player must not publish visual updates")
        display.submit(signal(0.4))
        display.setVisible(true)
        requireDisplay(frames == 1 && display.frame.level == 0.4)
        requireDisplay(display.bands(at: now).allSatisfy { abs($0 - 0.4) < 1e-9 }, "Resume must use the latest signal")

        now = 0.01
        display.submit(signal(0.8))
        let immediate = display.bands(at: now)[0]
        let smoothed = display.bands(at: now + 0.065)[0]
        requireDisplay(abs(immediate - 0.4) < 1e-9 && smoothed > immediate && smoothed < 0.8,
                     "Visible incoming frames must retain smooth interpolation")
        display.submit(.empty)
        requireDisplay(display.settling)
        let silentFrames = frames
        for _ in 0..<500 { display.submit(.empty) }
        requireDisplay(frames == silentFrames, "Repeated silence must not invalidate the monitor")

        display.setVisible(false)
        requireDisplay(!display.settling)
        let pausedFrames = frames, pausedChanges = changes
        for _ in 0..<5_000 { display.submit(signal(0.9)) }
        display.submit(.empty)
        try await Task.sleep(for: .milliseconds(800))
        requireDisplay(frames == pausedFrames && changes == pausedChanges,
                     "Paused signal updates and cancelled release tasks must remain silent")
        now = 5
        display.setVisible(true)
        requireDisplay(!display.frame.hasAudio && !display.settling)
        requireDisplay(display.bands(at: now).allSatisfy { $0 == 0 }, "Stopped hidden audio must not leave a stale waveform")

        display.setVisible(false)
        now = 6
        display.submit(signal(0.1)); display.submit(signal(0.7))
        display.setVisible(true)
        requireDisplay(display.frame.level == 0.7 && display.bands(at: now).allSatisfy { $0 == 0.7 })
        display.submit(.empty)
        requireDisplay(display.settling)
        display.submit(signal(0.5))
        requireDisplay(!display.settling)
        let resumedFrames = frames
        try await Task.sleep(for: .milliseconds(800))
        requireDisplay(frames == resumedFrames && display.frame.level == 0.5 && !display.settling,
                     "A cancelled release must not overwrite resumed music")
        display.setVisible(false)
        now = 7
        display.submit(signal(0.9))
        now = 8
        display.setVisible(true)
        requireDisplay(!display.frame.hasAudio && display.bands(at: now).allSatisfy { $0 == 0 },
                     "Resuming a stalled producer must not animate an expired audio packet")
        withExtendedLifetime((frameObserver, changeObserver)) {}
        now = 9
        display.submit(SignalFrame(tones: [], level: 0.5, bands: [], inputRMS: 0.05, hasAudio: true, beatStrength: 0.8))
        requireDisplay(display.beat(at: 9) > 0)
        requireDisplay(display.recentBeat, "Reduced-motion feedback must retain a detected beat.")
        try await wait { beatSleeps.pending.count == 1 }
        display.submit(SignalFrame(tones: [], level: 0.5, bands: [], inputRMS: 0.05, hasAudio: true, beatStrength: 0.8))
        try await wait { beatSleeps.pending.count == 2 }
        beatSleeps.releaseFirst() // let the cancelled older timer finish
        try await wait { beatSleeps.resumed == 1 }
        requireDisplay(display.recentBeat, "An older expiry must not clear a newer beat.")
        beatSleeps.releaseFirst()
        try await wait { !display.recentBeat }
        requireDisplay(!display.recentBeat, "Text feedback must expire without another audio packet.")
        requireDisplay(display.beat(at: 9.3) == 0, "A visual beat must expire without another audio packet.")
        display.setVisible(false)
        requireDisplay(display.beat(at: 9) == 0 && !display.recentBeat)
        display.setVisible(true)
        display.submit(.empty)
        requireDisplay(display.beat(at: 9) == 0 && !display.recentBeat, "Silence/suppression must clear the visual beat.")
        let supportOwner = UUID()
        display.setVisible(true, owner: supportOwner)
        display.setVisible(false)
        requireDisplay(display.isVisible, "Closing the player must not pause a visible support indicator.")
        display.setVisible(false, owner: supportOwner)
        requireDisplay(!display.isVisible, "Closing the last visual consumer must stop publishing.")
        let visual = SignalDisplay(clock: { 0 })
        visual.setVisible(true)
        func onset(_ strength: Double) -> SignalFrame {
            SignalFrame(tones: [], level: 0.2, bands: [], inputRMS: 0.05, hasAudio: true, beatStrength: strength)
        }
        visual.submit(onset(0.01))
        let quietPulse = visual.beatPulse(at: 0)
        requireDisplay(quietPulse == 1 && visual.beat(at: 0) == 0.01)
        visual.submit(onset(1))
        requireDisplay(visual.beatPulse(at: 0) == quietPulse, "Quiet detected events must remain as visible as strong ones.")
        requireDisplay(abs(visual.beatPulse(at: 0.11) - 0.5) < 1e-9 && visual.beatPulse(at: 0.23) == 0)
        requireDisplay(visual.beatPulse(at: -.infinity) == 0 && visual.beatPulse(at: .nan) == 0)
        visual.submit(.empty)
        requireDisplay(visual.beatPulse(at: 0) == 0, "Silence must clear a visual event immediately.")
        visual.setVisible(false)
        while !beatSleeps.pending.isEmpty { beatSleeps.releaseFirst() }
        print("Display pause/resume, 10,000 hidden packets without publication, latest-frame recovery, silence/stalled input, cancelled release and foreground smoothing passed.")
        print("Quiet/strong detected events retain their original strength while sharing a legible, bounded visual pulse; expiry and silence clear it.")
    }
}
