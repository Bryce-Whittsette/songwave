import Foundation
import Darwin

// The real Playback/Session and bundled model run with capture and motor edges
// replaced. This never requests recording access or actuates physical hardware.
@main struct ModeSwitchStress {
    static func run(_ seconds: Double) { RunLoop.current.run(until: Date(timeIntervalSinceNow: seconds)) }
    static func wait(_ message: String, _ condition: () -> Bool) {
        let end = Date(timeIntervalSinceNow: 8)
        while !condition() && Date() < end { run(0.01) }
        require(condition(), message)
    }
    static func main() {
        setbuf(stdout, nil)
        LifecycleHardware.clear()
        LifecycleHardware.set([111: LifecycleClient(bundle: "com.spotify.client")])
        let engine = Playback()
        var errors: [String] = []
        engine.start(.macAudio, tuning: OutputMode.assist.defaults, mode: .assist, playerPath: nil, startAt: 0) {
            if let error = $0.error { errors.append(error) }
        }
        engine.confirmPlayer("com.spotify.client")
        wait("Live Light playback never started") { LifecycleHardware.writes.count > 6 }
        var isolated = OutputMode.trackpad.defaults
        isolated.hapticFocus = .voice; isolated.vocalQuality = .isolated
        engine.set(tuning: isolated); engine.setMacMode(.trackpad)
        let before = LifecycleHardware.writes.count
        wait("The existing isolated pipeline did not produce output") { LifecycleHardware.writes.count > before + 6 || !errors.isEmpty }
        require(errors.isEmpty, errors.joined(separator: "; "))
        let load = DispatchGroup()
        load.enter()
        DispatchQueue.global(qos: .userInitiated).async {
            let end = Date(timeIntervalSinceNow: 2)
            var value = 0.0
            while Date() < end { for index in 0..<10000 { value += sin(Double(index)) } }
            require(value.isFinite)
            load.leave()
        }
        for index in 0..<120 {
            let mode = OutputMode.allCases[index % OutputMode.allCases.count]
            let focus = HapticFocus.allCases[(index / 2) % HapticFocus.allCases.count]
            var tuning = mode.defaults; tuning.hapticFocus = focus
            tuning.vocalQuality = index % 3 == 0 ? .isolated : .light
            engine.set(tuning: tuning); engine.setMacMode(mode)
            if index % 13 == 0 { engine.setHaptics(false) }
            else { engine.setHaptics(true) }
            run(0.012)
            require(errors.isEmpty, errors.joined(separator: "; "))
            require(LifecycleHardware.liveTaps <= 1 && LifecycleHardware.liveMotors <= 1,
                    "Mode changes retained duplicate live I/O")
        }
        engine.setHaptics(true); engine.set(tuning: OutputMode.assist.defaults); engine.setMacMode(.assist)
        let resumed = LifecycleHardware.writes.count
        wait("Light playback did not recover after rapid mode changes") { LifecycleHardware.writes.count > resumed + 10 }
        if CommandLine.arguments.count > 1, let idleSeconds = Double(CommandLine.arguments[1]), idleSeconds > 0 {
            require(idleSeconds.isFinite && idleSeconds <= 43200, "Keep the optional soak bounded to 12 hours")
            LifecycleHardware.set([:])
            wait("Idle did not release capture") { LifecycleHardware.liveTaps == 0 && LifecycleHardware.mutedTaps == 0 }
            run(0.5)
            let idleWrites = LifecycleHardware.writes.count
            let started = Date()
            var nextReport = Date()
            while Date().timeIntervalSince(started) < idleSeconds {
                run(0.5)
                require(LifecycleHardware.writes.count == idleWrites, "Idle emitted stale haptics")
                require(LifecycleHardware.liveTaps == 0 && LifecycleHardware.mutedTaps == 0)
                if Date() >= nextReport {
                    print("Wall-clock idle soak seconds:", Int(Date().timeIntervalSince(started)), "capture=0 muted=0 stale-output=0")
                    nextReport = Date(timeIntervalSinceNow: 60)
                }
            }
            LifecycleHardware.set([111: LifecycleClient(bundle: "com.spotify.client")])
            engine.confirmPlayer("com.spotify.client")
            wait("Playback did not resume after the wall-clock idle soak") { LifecycleHardware.writes.count > idleWrites + 8 }
            print("Wall-clock idle/resume passed:", Int(Date().timeIntervalSince(started)), "seconds. Capture/motor edges are simulated; this is not a physical sleep test.")
        }
        engine.stop()
        wait("Stop retained capture, muted speakers or an actuator") {
            LifecycleHardware.liveTaps == 0 && LifecycleHardware.mutedTaps == 0 && LifecycleHardware.liveMotors == 0
        }
        let stopped = LifecycleHardware.writes.count
        run(0.4)
        require(LifecycleHardware.writes.count == stopped, "Cancelled work emitted stale haptics")
        load.wait()
        run(1)
        var usage = rusage(); getrusage(RUSAGE_SELF, &usage)
        print("120 rapid Beat/Voice/Both, Light/Isolated and output switches under CPU load passed using the unchanged bundled model; Stop released all mocked I/O and emitted no late output.")
        print("Peak RSS bytes:", usage.ru_maxrss, "(test process, not a whole-app energy measurement)")
    }
}
