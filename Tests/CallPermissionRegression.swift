import AppKit
import Foundation

// Real Studio → Playback → router → CaptureRequest → AudioTap → SampleRing.
// SDK and hardware boundaries are local replacements, not real TCC changes.
@main struct CallPermissionRegression {
    static var findings = Set<String>()
    @MainActor static func wait(_ label: String, seconds: Double = 5, _ condition: () -> Bool) async throws {
        let end = ContinuousClock.now.advanced(by: .seconds(seconds))
        while !condition() && ContinuousClock.now < end { try await Task.sleep(for: .milliseconds(10)) }
        interruptionRequire(condition(), label)
    }
    @MainActor static func quiet(_ seconds: Double = 0.25) async throws {
        let count = InterruptionHAL.packets.count
        try await Task.sleep(for: .seconds(seconds))
        interruptionRequire(InterruptionHAL.packets.count == count, "Stale haptics leaked during suppression")
    }
    @MainActor static func stop(_ studio: Studio) async throws {
        studio.stop()
        try await wait("Stop leaked capture, listeners, or actuator") {
            let n = InterruptionHAL.counts
            return n.taps == 0 && n.callbacks == 0 && n.listeners == 0 && n.motors == 0
        }
    }
    @MainActor static func start(_ mode: OutputMode, provider: Provider = .spotify, bypass: Bool = false) async throws -> Studio {
        InterruptionHAL.grant()
        InterruptionHAL.setClients([111: .init(bundle: provider.bundle)])
        let studio = Studio()
        studio.mode = mode
        var tuning = mode.defaults
        tuning.hapticFocus = .both; tuning.vocalQuality = .light
        tuning.automaticTiming = false; tuning.delay = mode == .assist ? 120 : 0
        studio.tuning = tuning
        let count = InterruptionHAL.packets.count
        studio.start(.macAudio, initialBypass: bypass)
        try await wait("Automatic capture did not reach receiving") { studio.captureHealth == .receiving }
        if !bypass { try await wait("Initial haptics missing") { InterruptionHAL.packets.count > count + 3 } }
        return studio
    }
    @MainActor static func calls() async throws {
        var cycles = 0
        for mode in OutputMode.allCases {
            for provider in Provider.allCases {
                let studio = try await start(mode, provider: provider)
                for bundle in ["com.apple.FaceTime", "com.apple.telephony", "com.apple.avconferenced"] {
                    // Inactive window, incoming ringing output, active input,
                    // an in-call output gap, and a clean return to music.
                    InterruptionHAL.setClients([111: .init(bundle: provider.bundle), 112: .init(bundle: bundle, output: 0)])
                    let prior = InterruptionHAL.packets.count
                    try await wait("Idle call window suppressed music") { InterruptionHAL.packets.count > prior + 2 }
                    for call in [InterruptionHAL.Client(bundle: bundle, input: 0, output: 1),
                                 .init(bundle: bundle, input: 1, output: 1),
                                 .init(bundle: bundle, input: 1, output: 0)] {
                        let beforeSpeaker = InterruptionHAL.locked { InterruptionHAL.speakerFrames }
                        InterruptionHAL.setClients([111: .init(bundle: provider.bundle), 112: call])
                        try await wait("Call did not pause and release capture", seconds: 2) {
                            studio.healthSnapshot.pause == .call && InterruptionHAL.counts.taps == 0 && InterruptionHAL.counts.muted == 0
                        }
                        try await quiet()
                        interruptionRequire(studio.active && studio.error == nil, "Call stopped or failed the listening session")
                        interruptionRequire(InterruptionHAL.locked { InterruptionHAL.speakerFrames > beforeSpeaker }, "Fixture music source stopped advancing")
                    }
                    let paused = InterruptionHAL.packets.count
                    InterruptionHAL.locked { InterruptionHAL.delivery = .zeros }
                    InterruptionHAL.setClients([111: .init(bundle: provider.bundle), 112: .init(bundle: bundle, output: 0)])
                    try await wait("Call-ended source did not reconnect") { InterruptionHAL.counts.taps == 1 }
                    try await quiet(0.3)
                    interruptionRequire(InterruptionHAL.packets.count == paused, "Call-ended transition replayed old audio before fresh PCM")
                    InterruptionHAL.locked { InterruptionHAL.delivery = .music }
                    try await wait("Call did not resume without restarting") {
                        InterruptionHAL.packets.count > paused + 3 && studio.healthSnapshot.pause != .call
                    }
                    interruptionRequire(InterruptionHAL.counts.taps == 1 && InterruptionHAL.counts.muted == (mode == .trackpad ? 1 : 0), "Duplicate or wrong post-call route")
                    cycles += 1
                }
                // Haptics off must survive a call, and Stop must defeat a late
                // call-ended transition rather than restarting capture.
                if mode == .assist { studio.toggleAssist() }
                else { studio.start(.macAudio, initialBypass: true) }
                try await wait("Bypass restoration did not keep analysis active") { studio.captureHealth == .receiving && studio.localBypass }
                try await Task.sleep(for: .milliseconds(250))
                try await quiet(0.4)
                InterruptionHAL.setClients([111: .init(bundle: provider.bundle), 112: .init(bundle: "com.apple.FaceTime", input: 1, output: 0)])
                try await wait("Bypassed call retained capture") { InterruptionHAL.counts.taps == 0 }
                let bypassed = InterruptionHAL.packets.count
                InterruptionHAL.setClients([111: .init(bundle: provider.bundle)])
                try await wait("Bypassed session did not reconnect") { InterruptionHAL.counts.taps == 1 }
                try await quiet(0.45)
                interruptionRequire(studio.localBypass && InterruptionHAL.packets.count == bypassed, "Call reset the listener's bypass")
                InterruptionHAL.setClients([111: .init(bundle: provider.bundle), 112: .init(bundle: "com.apple.FaceTime", input: 1, output: 0)])
                try await wait("Call before Stop did not settle") { InterruptionHAL.counts.taps == 0 }
                try await stop(studio)
                InterruptionHAL.setClients([111: .init(bundle: provider.bundle)])
                try await quiet(0.4)
                interruptionRequire(InterruptionHAL.counts.taps == 0 && !studio.active, "Call-ended event undid explicit Stop")
            }
        }
        print("PASS: \(cycles) automatic source/provider/output call cycles, incoming/active/input-only phases, bypass and Stop; real capture/controller code with fake HAL.")
    }
    @MainActor static func callStormAndLateStartup() async throws {
        let studio = try await start(.trackpad)
        // Force a source reconnection into blocked SDK callback registration
        // after music is already playing, then begin a call before it returns.
        let gate = DispatchSemaphore(value: 0)
        let entered = InterruptionHAL.locked { () -> Int in InterruptionHAL.callbackGate = gate; return InterruptionHAL.callbackEntries }
        InterruptionHAL.setClients([113: .init(bundle: "com.spotify.client")])
        try await wait("Reconnection never entered the blocked SDK") { InterruptionHAL.locked { InterruptionHAL.callbackEntries > entered } }
        InterruptionHAL.setClients([113: .init(bundle: "com.spotify.client"), 112: .init(bundle: "com.apple.FaceTime", input: 1, output: 0)])
        try await wait("Call did not suppress while startup was blocked") { studio.healthSnapshot.pause == .call && InterruptionHAL.counts.muted == 0 }
        try await quiet()
        InterruptionHAL.locked { InterruptionHAL.callbackGate = nil }
        gate.signal()
        try await wait("Cancelled late startup leaked an unaccepted tap") { InterruptionHAL.counts.taps == 0 && InterruptionHAL.counts.callbacks == 0 }
        try await quiet()
        InterruptionHAL.setClients([113: .init(bundle: "com.spotify.client")])
        let before = InterruptionHAL.packets.count
        try await wait("Late startup prevented a fresh call-ended connection") { InterruptionHAL.packets.count > before + 3 }
        let load = Task.detached {
            let end = ContinuousClock.now.advanced(by: .seconds(2))
            var number = 0.0
            while ContinuousClock.now < end { for i in 0..<10000 { number += sin(Double(i)) } }
            interruptionRequire(number.isFinite, "Invalid CPU-load result")
        }
        for i in 0..<30 {
            var clients: [UInt32: InterruptionHAL.Client] = [113: .init(bundle: "com.spotify.client")]
            if i % 2 == 0 { clients[112] = .init(bundle: "com.apple.telephony", input: 1, output: 0) }
            InterruptionHAL.setClients(clients)
            try await Task.sleep(for: .milliseconds(40))
        }
        InterruptionHAL.setClients([113: .init(bundle: "com.spotify.client"), 112: .init(bundle: "com.apple.telephony", input: 1, output: 0)])
        try await wait("Steady call after rapid transitions stayed stuck") { studio.healthSnapshot.pause == .call && InterruptionHAL.counts.taps == 0 }
        try await quiet()
        InterruptionHAL.setClients([113: .init(bundle: "com.spotify.client")])
        let paused = InterruptionHAL.packets.count
        try await wait("Rapid call transitions did not recover") { InterruptionHAL.packets.count > paused + 3 }
        await load.value
        try await stop(studio)
        print("PASS: blocked late SDK registration across a call and 30 rapid call-state transitions under CPU load settle and recover; brief transitions shorter than the polling interval are not individually guaranteed.")
    }
    @MainActor static func permissionLoss() async throws {
        for mode in OutputMode.allCases {
            for delivery in [InterruptionHAL.Delivery.stopped, .zeros] {
                let studio = try await start(mode)
                let taps = InterruptionHAL.counts.taps
                InterruptionHAL.revoke(delivery)
                try await wait("Silent loss did not settle or release muting", seconds: 5) {
                    studio.waiting && InterruptionHAL.counts.muted == 0
                }
                try await quiet(0.4)
                print("OBSERVED silent loss:", mode.rawValue, delivery,
                      "capture=\(studio.healthSnapshot.capture.rawValue) pause=\(studio.healthSnapshot.pause.rawValue) error=\(studio.healthSnapshot.error.rawValue)")
                interruptionRequire(studio.active && InterruptionHAL.counts.taps == taps,
                    "Surviving automatic capture did not remain resumable")
                if studio.healthSnapshot.capture != .failed {
                    findings.insert("Silent callback loss/zeroing is shown as waiting, not a permission-specific failure. Actual TCC behavior is unverified.")
                }
                if mode == .assist && delivery == .stopped {
                    try await wait("Long silent loss never offered Listening help", seconds: 9) { studio.captureHelp }
                }
                // A surviving tap resumes if its callbacks return. No Relaunch,
                // Stop/start, permission API or installed app is involved.
                let before = InterruptionHAL.packets.count
                InterruptionHAL.grant()
                try await wait("Restored PCM did not resume on the same session") { InterruptionHAL.packets.count > before + 3 && studio.captureHealth == .receiving }
                try await stop(studio)
            }
            let studio = try await start(mode)
            // Invalidate the old tap, then deny every replacement, not just a
            // single failed attempt. '!hog' is an injected SDK permissions
            // error, not a claim about which code TCC actually returns.
            InterruptionHAL.revoke(.stopped, invalidate: true)
            try await wait("Persistent denial never reached recovery", seconds: 5) { studio.healthSnapshot.capture == .failed }
            interruptionRequire(studio.healthSnapshot.error == .capture && InterruptionHAL.counts.taps == 0, "Denied reconnect retained old capture")
            try await quiet()
            let denied = InterruptionHAL.counts.denied
            try await Task.sleep(for: .seconds(2))
            interruptionRequire(InterruptionHAL.counts.denied <= denied + 1, "Persistent denial caused a rapid retry loop")
            try await wait("Persistent denial was not retried with bounded backoff", seconds: 5) { InterruptionHAL.counts.denied > denied }
            interruptionRequire(InterruptionHAL.counts.denied <= denied + 2 && InterruptionHAL.counts.taps == 0,
                "Permission denial spun unbounded retries or retained capture")
            print("OBSERVED denied reconnect:", mode.rawValue, studio.detection, "capture=\(studio.captureHealth.rawValue)")
            let before = InterruptionHAL.packets.count
            InterruptionHAL.grant()
            try await wait("Automatic reconnect did not recover after grant", seconds: 6) { studio.captureHealth == .receiving && InterruptionHAL.packets.count > before + 3 }
            interruptionRequire(studio.active && studio.error == nil, "Grant restoration stranded automatic capture")
            // Explicit recovery uses the real access helper, then restarts the
            // chosen source inside this same fixture process.
            InterruptionHAL.revoke(.stopped, invalidate: true)
            try await wait("Repeated denial was not observed") { studio.captureHealth == .failed }
            let failure = await studio.prepareAudioAccess()
            interruptionRequire(failure?.contains("System Audio Recording permission") == true && studio.healthSnapshot.capture == .failed,
                "Explicit denied access check lost actionable permission guidance")
            if mode == .assist { studio.toggleAssist() }
            let bypassed = InterruptionHAL.packets.count
            InterruptionHAL.grant()
            await studio.retryCapture()
            try await wait("Listening help Retry did not recover without relaunch") { studio.captureHealth == .receiving }
            if mode == .assist { try await quiet() }
            else { try await wait("Trackpad recovery did not restore haptics") { InterruptionHAL.packets.count > bypassed + 3 } }
            interruptionRequire(studio.localBypass == (mode == .assist) &&
                (mode != .assist || InterruptionHAL.packets.count == bypassed) && studio.audioAccessHealth.status == .checked,
                "Explicit permission recovery reset bypass or retained failed access")
            interruptionRequire(!studio.diagnosticsReport.contains("Private fixture"), "Diagnostics leaked catalog metadata")
            try await stop(studio)
        }
        print("PASS: stopped/zero callbacks, persistent denied reconnect, automatic regrant and explicit recovery exercised without any real TCC access.")
    }
    @MainActor static func explicitRoutes() async throws {
        for provider in Provider.allCases {
            let link = try MusicLink(provider == .spotify ? "spotify:track:0000000000000000000000" : "https://music.apple.com/us/song/fixture/123")
            for mode in OutputMode.allCases {
                InterruptionHAL.grant()
                InterruptionHAL.setClients([111: .init(bundle: provider.bundle)])
                let engine = Playback()
                var update = PlaybackUpdate()
                var tuning = mode.defaults; tuning.vocalQuality = .light; tuning.hapticFocus = .both
                func start() {
                    engine.start(.player(link), tuning: tuning, mode: mode, playerPath: "/Fixture/Player.app", startAt: 0) { update = $0 }
                }
                start()
                try await wait("Explicit player did not receive audio") { update.signal.hasAudio }
                for delivery in [InterruptionHAL.Delivery.stopped, .zeros] {
                    InterruptionHAL.revoke(delivery)
                    try await wait("Explicit silent loss did not settle") { update.waiting }
                    try await quiet(0.4)
                    let retained = InterruptionHAL.counts.muted
                    print("OBSERVED explicit silent loss:", provider.rawValue, mode.rawValue, delivery, "muted taps=\(retained) error=\(update.error != nil)")
                    if retained > 0 {
                        findings.insert("Explicit Trackpad only retains source muting after silent capture loss; Stop or recovered PCM is needed. Reproduced with SDK fault injection, not real TCC revocation.")
                    }
                    let message = update.error?.lowercased() ?? ""
                    interruptionRequire(!message.contains("permission denied") && !message.contains("permission revoked"),
                        "Silence alone must not assert authoritative TCC denial")
                    let before = InterruptionHAL.packets.count
                    InterruptionHAL.grant()
                    try await wait("Existing explicit tap did not resume when PCM returned") { InterruptionHAL.packets.count > before + 3 && !update.waiting }
                }
                InterruptionHAL.revoke(.stopped, invalidate: true)
                try await wait("Explicit permission error did not stop cleanly") {
                    update.captureFailed && update.error != nil && InterruptionHAL.counts.taps == 0 && InterruptionHAL.counts.motors == 0
                }
                interruptionRequire(update.error?.contains("System Audio Recording permission") == true && InterruptionHAL.counts.muted == 0,
                    "Explicit denial lacked permission guidance or retained muting")
                try await quiet()
                InterruptionHAL.grant(); update = PlaybackUpdate()
                let before = InterruptionHAL.packets.count
                start()
                try await wait("Explicit Reconnect needed a process relaunch") { InterruptionHAL.packets.count > before + 3 && update.signal.hasAudio }
                engine.stop()
                try await wait("Explicit Stop leaked capture or listeners") {
                    let n = InterruptionHAL.counts
                    return n.taps == 0 && n.callbacks == 0 && n.listeners == 0 && n.motors == 0
                }
            }
        }
        print("PASS: four explicit Spotify/Music output routes; persistent-denial errors are actionable, clean up I/O and recover on Reconnect within the same process.")
    }
    @MainActor static func main() async throws {
        setbuf(stdout, nil)
        guard let identifier = Bundle.main.bundleIdentifier, identifier.hasPrefix("studio.songwave.interruption-test.") else {
            fatalError("Requires a disposable fixture's actual Info.plist identity")
        }
        UserDefaults.standard.setVolatileDomain(["setupComplete": false, "launchListen": false,
            "audioAccessConfigured": true, "firstSuccessPending": false], forName: UserDefaults.argumentDomain)
        defer { InterruptionHAL.finish(); UserDefaults.standard.removePersistentDomain(forName: identifier) }
        InterruptionHAL.begin()
        try await calls()
        try await callStormAndLateStartup()
        try await permissionLoss()
        try await explicitRoutes()
        interruptionRequire(InterruptionHAL.locked { InterruptionHAL.opened == InterruptionHAL.closed && InterruptionHAL.aggregates.isEmpty }, "Fixture SDK resources leaked")
        for finding in findings.sorted() { print("UNRESOLVED FINDING:", finding) }
        print("Scope: fixture assertions passed; \(findings.count) unresolved findings. Physical call audio and real TCC revoke/regrant are not verified.")
        if ProcessInfo.processInfo.environment["GITHUB_ACTIONS"] == "true" {
            for finding in findings.sorted() { print("::warning title=Capture acceptance gap::" + finding) }
            if let path = ProcessInfo.processInfo.environment["GITHUB_STEP_SUMMARY"] {
                let summary = "### Call/permission fixture assessment\n\nSafety/recovery assertions passed; **\(findings.count) unresolved acceptance findings**. Physical calls and actual TCC revoke/regrant remain unverified.\n\n" +
                    findings.sorted().map { "- " + $0 }.joined(separator: "\n") + "\n\nStrict acceptance: `bash Tests/test-call-permission.sh --require-all` currently exits 2.\n"
                if !FileManager.default.fileExists(atPath: path) { try Data().write(to: URL(fileURLWithPath: path)) }
                let handle = try FileHandle(forWritingTo: URL(fileURLWithPath: path))
                try handle.seekToEnd(); try handle.write(contentsOf: Data(summary.utf8)); try handle.close()
            }
        }
        if CommandLine.arguments.contains("--require-all"), !findings.isEmpty { exit(2) }
    }
}
