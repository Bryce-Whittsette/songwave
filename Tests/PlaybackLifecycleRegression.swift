import CoreAudio
import AVFoundation
import Foundation

@main struct PlaybackLifecycleRegression {
    static func wait(_ description: String, timeout: Double = 3, until condition: () -> Bool) {
        let end = Date(timeIntervalSinceNow: timeout)
        while !condition() && Date() < end { RunLoop.current.run(until: Date(timeIntervalSinceNow: 0.002)) }
        require(condition(), description)
    }
    static func run(for duration: Double) { RunLoop.current.run(until: Date(timeIntervalSinceNow: duration)) }
    static func gain() {
        for cadence in [0.008, 0.016, 0.064, 0.09] {
            var gain = UserHapticsGain()
            require(gain.level(enabled: true, at: 0) == 1)
            require(gain.level(enabled: false, at: 0.016) == 1)
            var prior = 1.0
            for step in 1...20 {
                let next = gain.level(enabled: false, at: 0.016 + Double(step) * cadence)
                require((0...prior).contains(next)); prior = next
            }
            require(prior == 0)
            require(gain.level(enabled: true, at: 1) == 1)
            require(gain.level(enabled: false, at: .nan) == 0)
            require(gain.level(enabled: false, at: 2) == 0)
        }
        var gain = UserHapticsGain()
        _ = gain.level(enabled: true, at: 1)
        _ = gain.level(enabled: false, at: 1.008)
        let falling = gain.level(enabled: false, at: 1.072)
        require(falling > 0 && falling < 1)
        require(gain.level(enabled: true, at: 1.072) == falling)
        require(gain.level(enabled: true, at: 1.136) > falling)
    }
    static func setupCheck() throws {
        LifecycleHardware.clear()
        LifecycleHardware.set([111: LifecycleClient(bundle: "com.spotify.client")])
        let link = try MusicLink("spotify:track:0000000000000000000000")
        let engine = Playback()
        var updates = 0
        engine.start(.player(link), tuning: OutputMode.assist.defaults, mode: .assist,
            playerPath: "/Mock/Player.app", startAt: 0, hapticsEnabled: false) { update in
            if update.signal.hasAudio { updates += 1 }
        }
        wait("Verification must still detect audio") { updates >= 3 }
        require(LifecycleHardware.writes.isEmpty && LifecycleHardware.mutedTaps == 0,
            "Setup detection must not actuate or mute speakers")
        engine.stop()
        wait("Verification capture did not stop") { LifecycleHardware.liveTaps == 0 && LifecycleHardware.liveMotors == 0 }
        var completed = false
        engine.testTrackpad { _ in completed = true }
        wait("Explicit test did not complete", timeout: 2) { completed }
        require((1...3).contains(LifecycleHardware.writes.count))
        require(LifecycleHardware.writes.allSatisfy { $0.level <= 0.35 })
        wait("Test resources were not released") { LifecycleHardware.liveMotors == 0 && LifecycleHardware.liveTaps == 0 }
        LifecycleHardware.clear()
        engine.testTrackpad { _ in }
        engine.stop()
        run(for: 0.12)
        let stopped = LifecycleHardware.writes.count
        run(for: 0.8)
        require(LifecycleHardware.writes.count == stopped && LifecycleHardware.liveMotors == 0,
            "Cancellation retained scheduled test output")
        LifecycleHardware.clear()
        LifecycleHardware.set([112: LifecycleClient(bundle: "com.apple.FaceTime", input: 1, output: 0)])
        var blocked = false
        engine.testTrackpad { blocked = $0 != nil }
        wait("A call must block the explicit test") { blocked }
        require(LifecycleHardware.writes.isEmpty && LifecycleHardware.liveMotors == 0)
        LifecycleHardware.clear()
        print("Setup capture stays unmuted and non-actuating; explicit taps are bounded, cancelled on Stop, and blocked during calls.")
    }
    static func blockedCaptureCancellation() throws {
        for explicit in [false, true] {
            LifecycleHardware.clear()
            LifecycleHardware.set([111: LifecycleClient(bundle: "com.spotify.client")])
            LifecycleHardware.blockCapture()
            let engine = Playback()
            let link = try MusicLink("spotify:track:0000000000000000000000")
            engine.start(explicit ? .player(link) : .macAudio, tuning: OutputMode.assist.defaults,
                         mode: .assist, playerPath: explicit ? "/Mock/Player.app" : nil, startAt: 0) { _ in }
            wait("Capture startup was not exercised") { LifecycleHardware.captureAttempts > 0 }
            engine.stop()
            wait("Stop was blocked behind a stalled Core Audio startup", timeout: 1) { LifecycleHardware.liveMotors == 0 }
            LifecycleHardware.releaseCapture()
            run(for: 0.05)
            wait("A cancelled capture startup retained resources") { LifecycleHardware.liveTaps == 0 && LifecycleHardware.mutedTaps == 0 }
            require(LifecycleHardware.writes.isEmpty, "Cancelled capture startup emitted haptics")
            engine.start(.player(link), tuning: OutputMode.assist.defaults, mode: .assist,
                         playerPath: "/Mock/Player.app", startAt: 0) { _ in }
            wait("A fresh session could not start after cancellation") { LifecycleHardware.writes.count > 5 }
            engine.stop()
            wait("The replacement session retained resources") { LifecycleHardware.liveTaps == 0 && LifecycleHardware.liveMotors == 0 }
        }
        print("Stop remains responsive during blocked automatic/explicit capture startup; cancelled late completions cannot retain muting or emit haptics.")
    }
    static func boundedCaptureAdmission() {
        LifecycleHardware.clear(); LifecycleHardware.blockCapture()
        var requests: [CaptureRequest] = []
        for _ in 0..<80 {
            if let request = CaptureRequest(description: CATapDescription(stereoMixdownOfProcesses: [111]), mute: false) { requests.append(request) }
        }
        require(!requests.isEmpty && requests.count <= 4, "Capture startup admission was not bounded")
        wait("Capture workers did not start") { LifecycleHardware.captureAttempts == requests.count }
        requests.forEach { $0.cancel() }; requests.removeAll()
        LifecycleHardware.releaseCapture()
        run(for: 0.1)
        wait("Cancelled workers retained I/O") { LifecycleHardware.liveTaps == 0 && LifecycleHardware.mutedTaps == 0 }
        print("80 capture-start requests admitted at most four Core Audio workers, with cancellation cleanup and no speaker muting.")
    }
    static func routeReconnection() throws {
        for automatic in [false, true] {
            for mode in OutputMode.allCases {
                LifecycleHardware.clear(); LifecycleHardware.changeRoute(rate: 24000)
                LifecycleHardware.set([111: LifecycleClient(bundle: "com.spotify.client")])
                let engine = Playback()
                let link = try MusicLink("spotify:track:0000000000000000000000")
                var tuning = mode.defaults; tuning.hapticFocus = .beat
                engine.start(automatic ? .macAudio : .player(link), tuning: tuning, mode: mode,
                             playerPath: automatic ? nil : "/Mock/Player.app", startAt: 0) { _ in }
                engine.confirmPlayer("com.spotify.client")
                wait("Initial route never played") { LifecycleHardware.writes.count > 6 }
                for rate in [48000.0, 44100.0, 16000.0, 96000.0, 48000.0] {
                    let attempts = LifecycleHardware.captureAttempts
                    LifecycleHardware.changeRoute(rate: rate)
                    wait("An output change did not rebuild capture") { LifecycleHardware.captureAttempts > attempts }
                    let prior = LifecycleHardware.writes.count
                    wait("Output did not resume at the new sample rate") { LifecycleHardware.writes.count > prior + 6 }
                    require(LifecycleHardware.liveTaps == 1 && LifecycleHardware.liveMotors == 1)
                    require(LifecycleHardware.mutedTaps == (mode == .trackpad ? 1 : 0))
                }
                engine.stop()
                wait("Route stress retained I/O") { LifecycleHardware.liveTaps == 0 && LifecycleHardware.liveMotors == 0 }
            }
        }
        print("20 route/rate rebuilds across automatic/explicit sources and both outputs resumed with one active connection and correct muting.")
    }
    static func extremeRates() throws {
        let link = try MusicLink("spotify:track:0000000000000000000000")
        for rate in [8000.0, 11025, 16000, 22050, 24000, 32000, 44100, 48000, 88200, 96000, 176400, 192000, 352800, 384000, 705600, 768000] {
            LifecycleHardware.clear(); LifecycleHardware.changeRoute(rate: rate)
            LifecycleHardware.set([111: LifecycleClient(bundle: "com.spotify.client")])
            let engine = Playback()
            var failure: String?
            var tuning = OutputMode.assist.defaults; tuning.hapticFocus = .beat
            engine.start(.player(link), tuning: tuning, mode: .assist, playerPath: "/Mock/Player.app", startAt: 0) { if let error = $0.error { failure = error } }
            wait("A supported extreme rate produced no output: \(rate)") { LifecycleHardware.writes.count > 6 || failure != nil }
            require(failure == nil, failure ?? "")
            engine.stop()
            wait("Extreme-rate playback retained resources") { LifecycleHardware.liveTaps == 0 && LifecycleHardware.liveMotors == 0 }
        }
        for rate in [0.0, -1, 7999, 768001, Double.infinity, Double.nan] {
            LifecycleHardware.clear(); LifecycleHardware.changeRoute(rate: rate)
            LifecycleHardware.set([111: LifecycleClient(bundle: "com.spotify.client")])
            let engine = Playback(); var failure: String?
            engine.start(.player(link), tuning: OutputMode.assist.defaults, mode: .assist,
                         playerPath: "/Mock/Player.app", startAt: 0) { if let error = $0.error { failure = error } }
            wait("An invalid rate did not report a failure") { failure != nil }
            wait("Invalid-rate startup retained I/O") { LifecycleHardware.liveTaps == 0 && LifecycleHardware.liveMotors == 0 }
            require(LifecycleHardware.writes.isEmpty)
            engine.stop()
        }
        LifecycleHardware.clear(); LifecycleHardware.changeRoute(rate: 384000)
        LifecycleHardware.set([111: LifecycleClient(bundle: "com.spotify.client")])
        let engine = Playback(); var failure: String?
        var tuning = OutputMode.trackpad.defaults; tuning.hapticFocus = .voice; tuning.vocalQuality = .isolated
        engine.start(.player(link), tuning: tuning, mode: .trackpad, playerPath: "/Mock/Player.app", startAt: 0) { if let error = $0.error { failure = error } }
        wait("Unsupported isolated input silently stalled") { failure != nil }
        require(failure!.contains("192 kHz") && failure!.contains("Light"))
        wait("Unsupported isolation rate retained resources") { LifecycleHardware.liveTaps == 0 && LifecycleHardware.liveMotors == 0 }
        require(LifecycleHardware.writes.isEmpty)
        engine.stop(); LifecycleHardware.changeRoute(rate: 24000)
        print("Playback exercised 16 rates from 8–768 kHz; invalid rates fail cleanly; unsupported isolated rates explain Light without switching the engine or loading a model.")
    }
    static func staleStartupRoute() throws {
        for automatic in [false, true] {
            LifecycleHardware.clear(); LifecycleHardware.changeRoute(rate: 48000)
            LifecycleHardware.set([111: LifecycleClient(bundle: "com.spotify.client")])
            LifecycleHardware.blockCapture()
            let engine = Playback()
            let link = try MusicLink("spotify:track:0000000000000000000000")
            var tuning = OutputMode.trackpad.defaults; tuning.hapticFocus = .beat
            engine.start(automatic ? .macAudio : .player(link), tuning: tuning, mode: .trackpad,
                         playerPath: automatic ? nil : "/Mock/Player.app", startAt: 0) { _ in }
            engine.confirmPlayer("com.spotify.client")
            wait("Startup did not enter the blocked route") { LifecycleHardware.captureAttempts > 0 }
            LifecycleHardware.changeRoute(rate: 44100)
            LifecycleHardware.releaseCapture()
            wait("A stale startup did not recover onto the current route") {
                LifecycleHardware.captureAttempts >= 2 && LifecycleHardware.writes.count > 6
            }
            require(LifecycleHardware.liveTaps == 1 && LifecycleHardware.mutedTaps == 1)
            engine.stop()
            wait("Stale startup recovery retained resources") { LifecycleHardware.liveTaps == 0 && LifecycleHardware.liveMotors == 0 }
        }
        print("Automatic and explicit capture discard stale startup completions before muting and recover at the new sample rate.")
    }
    static func malformedFiles() throws {
        let directory = FileManager.default.temporaryDirectory.appendingPathComponent(UUID().uuidString)
        try FileManager.default.createDirectory(at: directory, withIntermediateDirectories: true)
        defer { try? FileManager.default.removeItem(at: directory) }
        let empty = directory.appendingPathComponent("empty.wav")
        do {
            let format = AVAudioFormat(standardFormatWithSampleRate: 48000, channels: 1)!
            _ = try AVAudioFile(forWriting: empty, settings: format.settings)
        }
        let corrupt = directory.appendingPathComponent("corrupt.wav")
        try Data("RIFF\u{00}\u{00}\u{00}\u{00}WAVEfmt ".utf8).write(to: corrupt)
        let zero = directory.appendingPathComponent("zero.wav")
        try Data().write(to: zero)
        for url in [empty, corrupt, zero] {
            LifecycleHardware.clear()
            let engine = Playback(); var failed = false
            engine.start(.file(url), tuning: OutputMode.trackpad.defaults, mode: .trackpad,
                         playerPath: nil, startAt: 0) { failed = $0.error != nil }
            wait("Empty/corrupt audio did not report a failure") { failed }
            require(LifecycleHardware.liveTaps == 0 && LifecycleHardware.liveMotors == 0 && LifecycleHardware.writes.isEmpty,
                    "Invalid file startup touched physical-output boundaries")
            engine.stop()
        }
        print("Zero-byte, empty valid WAV and truncated WAV files fail before capture or motor setup.")
    }
    static func routeChangesBeforeMuting() throws {
        for automatic in [false, true] {
            LifecycleHardware.clear(); LifecycleHardware.changeRoute(rate: 48000)
            LifecycleHardware.set([111: LifecycleClient(bundle: "com.spotify.client")])
            LifecycleHardware.changeRouteOnNextMute()
            let engine = Playback(); var failure: String?
            let link = try MusicLink("spotify:track:0000000000000000000000")
            var tuning = OutputMode.trackpad.defaults; tuning.hapticFocus = .beat
            engine.start(automatic ? .macAudio : .player(link), tuning: tuning, mode: .trackpad,
                         playerPath: automatic ? nil : "/Mock/Player.app", startAt: 0) { if let error = $0.error { failure = error } }
            engine.confirmPlayer("com.spotify.client")
            wait("A route change immediately before muting did not recover") {
                LifecycleHardware.captureAttempts >= 2 && LifecycleHardware.writes.count > 6 || failure != nil
            }
            require(failure == nil && LifecycleHardware.mutedTaps == 1 && LifecycleHardware.liveTaps == 1)
            engine.stop()
            wait("Muting-race recovery retained resources") { LifecycleHardware.liveTaps == 0 && LifecycleHardware.liveMotors == 0 }
        }
        print("Route changes between startup acceptance and speaker muting reconnect without failing the session or muting a stale tap.")
    }
    static func main() throws {
        setbuf(stdout, nil)
        try malformedFiles()
        try routeChangesBeforeMuting()
        try extremeRates()
        try staleStartupRoute()
        try routeReconnection()
        boundedCaptureAdmission()
        try blockedCaptureCancellation()
        gain()
        try setupCheck()
        var cases = 0
        for provider in Provider.allCases {
            for mode in OutputMode.allCases {
              for focus in HapticFocus.allCases {
                LifecycleHardware.clear()
                let client = LifecycleClient(bundle: provider.bundle)
                let idleCall = LifecycleClient(bundle: "com.apple.FaceTime", output: 0)
                LifecycleHardware.set([111: client, 112: idleCall])
                require(!CallAudioPolicy.active(in: AudioHardware.processList().compactMap(AudioClient.init)), "An idle FaceTime app is not a call")
                let link = try MusicLink(provider == .spotify ? "spotify:track:0000000000000000000000" : "https://music.apple.com/us/song/test/123")
                let engine = Playback()
                LifecycleHardware.outputVolume = mode == .trackpad ? 0 : 1
                engine.setEffects(followVolume: true, keyboard: false)
                var tuning = mode.defaults
                tuning.hapticFocus = focus
                tuning.automaticTiming = false
                tuning.delay = focus == .both ? 24 : 0
                engine.start(.player(link), tuning: tuning, mode: mode, playerPath: "/Mock/Player.app", startAt: 0) { _ in }
                wait("The explicit player route failed to produce output with inactive FaceTime open") { LifecycleHardware.writes.count > 12 }
                require(LifecycleHardware.mutedTaps == (mode == .trackpad ? 1 : 0))
                if mode == .assist {
                    var quiet = tuning
                    quiet.gain = 0; quiet.eq.enabled = false; quiet.eq.bass.gain = -12
                    engine.set(tuning: quiet)
                    run(for: 0.2)
                    let quietCount = LifecycleHardware.writes.count
                    run(for: 0.06)
                    require(LifecycleHardware.writes.count == quietCount, "Zero normal intensity produced output")
                    engine.party(until: ProcessInfo.processInfo.systemUptime + 3)
                    wait("Ultra did not override zero saved intensity") { LifecycleHardware.writes.count > quietCount + 8 }
                    engine.party(until: 0)
                    run(for: 0.1)
                    let restored = LifecycleHardware.writes.count
                    run(for: 0.06)
                    require(LifecycleHardware.writes.count == restored, "Ultra did not restore saved intensity")
                    engine.set(tuning: tuning)
                    wait("Normal settings did not resume") { LifecycleHardware.writes.count > restored + 8 }
                }
                engine.setHaptics(false)
                run(for: 0.09)
                // Hosted runners can miss timer ticks within a 90 ms window.
                // The deterministic gain tests above verify the fade itself;
                // integration verifies bypass keeps the route alive and settles.
                require(LifecycleHardware.liveTaps == 1, "Manual bypass disconnected capture")
                require(LifecycleHardware.mutedTaps == (mode == .trackpad ? 1 : 0), "Manual bypass changed the audio route")
                run(for: 0.15)
                let faded = LifecycleHardware.writes.count
                run(for: 0.05)
                require(LifecycleHardware.writes.count == faded, "Bypass did not finish")
                engine.setHaptics(true)
                wait("Enabling haptics did not resume") { LifecycleHardware.writes.count > faded + 8 }
                LifecycleHardware.set([111: client, 112: LifecycleClient(bundle: "com.apple.FaceTime", input: 1, output: 0)])
                wait("The explicit player did not release capture during a call", timeout: 1) { LifecycleHardware.liveTaps == 0 }
                require(LifecycleHardware.mutedTaps == 0, "A call retained trackpad-only speaker muting")
                let suppressed = LifecycleHardware.writes.count
                run(for: 0.08)
                require(LifecycleHardware.writes.count == suppressed, "A call received fading or stale haptics")
                LifecycleHardware.set([111: client, 112: idleCall])
                wait("Music did not reconnect after the call", timeout: 1.5) { LifecycleHardware.writes.count > suppressed + 8 }
                require(LifecycleHardware.mutedTaps == (mode == .trackpad ? 1 : 0))
                LifecycleHardware.failNextCapture()
                LifecycleHardware.set([113: client, 112: idleCall])
                wait("Capture failure did not release the session", timeout: 2) { LifecycleHardware.liveMotors == 0 }
                require(LifecycleHardware.liveTaps == 0 && LifecycleHardware.mutedTaps == 0)
                let stopped = LifecycleHardware.writes.count
                run(for: 0.05)
                require(LifecycleHardware.writes.count == stopped, "Capture failure retained motor output")
                engine.stop()
                cases += 1
              }
            }
        }
        print("\(cases) explicit Spotify/Music routes passed: idle FaceTime, gradual bypass, resume, immediate recognized-call suppression, reconnect, and capture-failure cleanup; gain cadence/reversal checks passed.")
    }
}
