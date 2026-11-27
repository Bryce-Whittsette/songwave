import Combine
import Foundation

@main struct DisplayRegression {
    @MainActor static func main() async throws {
        var now = 0.0
        let display = SignalDisplay(clock: { now })
        var frames = 0, changes = 0
        let frameObserver = display.$frame.dropFirst().sink { _ in frames += 1 }
        let changeObserver = display.objectWillChange.sink { changes += 1 }
        func signal(_ strength: Double) -> SignalFrame {
            SignalFrame(tones: [], level: strength, bands: Array(repeating: strength, count: 44),
                        inputRMS: 0.01, hasAudio: true)
        }

        for _ in 0..<5_000 { display.submit(signal(0.2)) }
        precondition(frames == 0 && changes == 0, "A hidden player must not publish visual updates")
        display.submit(signal(0.4))
        display.setVisible(true)
        precondition(frames == 1 && display.frame.level == 0.4)
        precondition(display.bands(at: now).allSatisfy { abs($0 - 0.4) < 1e-9 }, "Resume must use the latest signal")

        now = 0.01
        display.submit(signal(0.8))
        let immediate = display.bands(at: now)[0]
        let smoothed = display.bands(at: now + 0.065)[0]
        precondition(abs(immediate - 0.4) < 1e-9 && smoothed > immediate && smoothed < 0.8,
                     "Visible incoming frames must retain smooth interpolation")
        display.submit(.empty)
        precondition(display.settling)
        let silentFrames = frames
        for _ in 0..<500 { display.submit(.empty) }
        precondition(frames == silentFrames, "Repeated silence must not invalidate the monitor")

        display.setVisible(false)
        precondition(!display.settling)
        let pausedFrames = frames, pausedChanges = changes
        for _ in 0..<5_000 { display.submit(signal(0.9)) }
        display.submit(.empty)
        try await Task.sleep(for: .milliseconds(800))
        precondition(frames == pausedFrames && changes == pausedChanges,
                     "Paused signal updates and cancelled release tasks must remain silent")
        now = 5
        display.setVisible(true)
        precondition(!display.frame.hasAudio && !display.settling)
        precondition(display.bands(at: now).allSatisfy { $0 == 0 }, "Stopped hidden audio must not leave a stale waveform")

        display.setVisible(false)
        now = 6
        display.submit(signal(0.1)); display.submit(signal(0.7))
        display.setVisible(true)
        precondition(display.frame.level == 0.7 && display.bands(at: now).allSatisfy { $0 == 0.7 })
        display.submit(.empty)
        precondition(display.settling)
        display.submit(signal(0.5))
        precondition(!display.settling)
        let resumedFrames = frames
        try await Task.sleep(for: .milliseconds(800))
        precondition(frames == resumedFrames && display.frame.level == 0.5 && !display.settling,
                     "A cancelled release must not overwrite resumed music")
        display.setVisible(false)
        now = 7
        display.submit(signal(0.9))
        now = 8
        display.setVisible(true)
        precondition(!display.frame.hasAudio && display.bands(at: now).allSatisfy { $0 == 0 },
                     "Resuming a stalled producer must not animate an expired audio packet")
        withExtendedLifetime((frameObserver, changeObserver)) {}
        now = 9
        display.submit(SignalFrame(tones: [], level: 0.5, bands: [], inputRMS: 0.05, hasAudio: true, beatStrength: 0.8))
        precondition(display.beat(at: 9) > 0)
        precondition(display.beat(at: 9.3) == 0, "A visual beat must expire without another audio packet.")
        display.setVisible(false)
        precondition(display.beat(at: 9) == 0)
        display.setVisible(true)
        display.submit(.empty)
        precondition(display.beat(at: 9) == 0, "Silence/suppression must clear the visual beat.")
        let supportOwner = UUID()
        display.setVisible(true, owner: supportOwner)
        display.setVisible(false)
        precondition(display.isVisible, "Closing the player must not pause a visible support indicator.")
        display.setVisible(false, owner: supportOwner)
        precondition(!display.isVisible, "Closing the last visual consumer must stop publishing.")
        print("Display pause/resume, 10,000 hidden packets without publication, latest-frame recovery, silence/stalled input, cancelled release and foreground smoothing passed.")
    }
}
