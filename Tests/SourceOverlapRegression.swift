import AppKit
import CoreAudio
import Foundation
import os

// Native observer wiring with a controlled window. Nothing is ordered onto the
// desktop and no other app is activated by the fixture.
final class FocusWindow: NSWindow {
    var shown = true
    override var isVisible: Bool { shown }
    override var occlusionState: NSWindow.OcclusionState { shown ? .visible : [] }
}
final class CPULoad {
    private let running = OSAllocatedUnfairLock(initialState: true)
    private let group = DispatchGroup()
    init() {
        for _ in 0..<2 {
            group.enter()
            DispatchQueue.global(qos: .utility).async { [self] in
                var value = 0.1
                while running.withLock({ $0 }) {
                    for index in 0..<20_000 { value = sin(value + Double(index) * 0.00001) }
                    withExtendedLifetime(value) {}
                }
                group.leave()
            }
        }
    }
    func stop() { running.withLock { $0 = false }; interruptionRequire(group.wait(timeout: .now() + 5) == .success, "CPU workers did not stop") }
}

@main struct SourceOverlapRegression {
    @MainActor static func wait(_ label: String, seconds: Double = 5, _ condition: () -> Bool) async throws {
        let deadline = ContinuousClock.now.advanced(by: .seconds(seconds))
        while !condition() && ContinuousClock.now < deadline { try await Task.sleep(for: .milliseconds(10)) }
        interruptionRequire(condition(), label)
    }
    @MainActor static func recycledProcess(automatic: Bool, mode: OutputMode) async throws {
        InterruptionHAL.grant()
        InterruptionHAL.setClients([111: .init(bundle: "com.spotify.client", pid: 600001)])
        let engine = Playback()
        var latest = PlaybackUpdate()
        var tuning = mode.defaults
        tuning.vocalQuality = .light; tuning.automaticTiming = false
        let source: PlaybackSource = automatic ? .macAudio : .player(try MusicLink("spotify:track:0000000000000000000000"))
        engine.start(source, tuning: tuning, mode: mode, playerPath: "/Fixture/Player.app", startAt: 0) { latest = $0 }
        engine.confirmPlayer("com.spotify.client")
        let start = InterruptionHAL.packets.count
        try await wait("Initial same-bundle process produced no output") { latest.signal.hasAudio && InterruptionHAL.packets.count > start + 4 }
        let opened = InterruptionHAL.locked { InterruptionHAL.opened }
        InterruptionHAL.locked { InterruptionHAL.lateCallbacks = InterruptionHAL.callbacks.values.map(\.block) }
        InterruptionHAL.setClients([111: .init(bundle: "com.spotify.client", pid: 600002)])
        try await wait("Recycled same-bundle AudioObjectID retained the old PID tap") { InterruptionHAL.locked { InterruptionHAL.opened > opened } }
        let resumed = InterruptionHAL.packets.count
        try await wait("Replacement same-bundle PID did not resume") { latest.signal.hasAudio && InterruptionHAL.packets.count > resumed + 4 }
        interruptionRequire(InterruptionHAL.counts.muted == (mode == .trackpad ? 1 : 0), "Recycled PID retained stale muting")
        engine.stop()
        try await wait("Process reuse retained resources") { InterruptionHAL.counts.taps == 0 && InterruptionHAL.counts.motors == 0 }
        let stopped = InterruptionHAL.packets.count
        try await Task.sleep(for: .milliseconds(200))
        interruptionRequire(InterruptionHAL.packets.count == stopped, "Retired callback actuated after Stop")
        InterruptionHAL.locked { InterruptionHAL.lateCallbacks = [] }
    }
    @MainActor static func pendingReplacement() async throws {
        InterruptionHAL.grant()
        InterruptionHAL.setClients([111: .init(bundle: "com.spotify.client", pid: 610001)])
        let gate = DispatchSemaphore(value: 0)
        let before = InterruptionHAL.locked { InterruptionHAL.callbackGate = gate; return InterruptionHAL.callbackEntries }
        let engine = Playback()
        var tuning = OutputMode.assist.defaults; tuning.vocalQuality = .light; tuning.automaticTiming = false
        engine.start(.macAudio, tuning: tuning, mode: .assist, playerPath: nil, startAt: 0) { _ in }
        engine.confirmPlayer("com.spotify.client")
        try await wait("Registration did not enter the controlled gate") { InterruptionHAL.locked { InterruptionHAL.callbackEntries > before } }
        InterruptionHAL.setClients([111: .init(bundle: "com.spotify.client", pid: 610002)])
        try await wait("Pending request did not follow the replacement PID") { InterruptionHAL.locked { InterruptionHAL.callbackEntries > before + 1 } }
        InterruptionHAL.locked { InterruptionHAL.callbackGate = nil }
        for _ in 0..<8 { gate.signal() }
        let packets = InterruptionHAL.packets.count
        try await wait("Replacement request failed to settle") { InterruptionHAL.counts.taps == 1 && InterruptionHAL.packets.count > packets + 4 }
        interruptionRequire(InterruptionHAL.locked { InterruptionHAL.taps.values.allSatisfy { $0.pids[111] == 610002 } }, "A late request retained the obsolete PID")
        engine.stop()
        try await wait("Pending replacement leaked resources") { InterruptionHAL.counts.taps == 0 && InterruptionHAL.counts.motors == 0 }
    }
    @MainActor static func overlappingSources(_ mode: OutputMode) async throws {
        InterruptionHAL.grant()
        InterruptionHAL.locked { InterruptionHAL.browserMusic = true }
        let bundles = ["com.spotify.client", "com.apple.Music", "com.google.Chrome"]
        var clients = Dictionary(uniqueKeysWithValues: bundles.enumerated().map { (AudioObjectID(111 + $0.offset), InterruptionHAL.Client(bundle: $0.element, gain: $0.offset == 0 ? 1 : 0)) })
        InterruptionHAL.setClients(clients)
        let engine = Playback()
        var latest = PlaybackUpdate()
        var tuning = mode.defaults; tuning.vocalQuality = .light; tuning.automaticTiming = false; tuning.delay = 80
        engine.start(.macAudio, tuning: tuning, mode: mode, playerPath: nil, startAt: 0) { latest = $0 }
        engine.confirmPlayer(bundles[0])
        try await wait("Concurrent source taps did not open") { latest.appBundle == bundles[0] && InterruptionHAL.counts.taps == 3 }
        for cycle in 0..<18 {
            let target = cycle % 3
            // Old and new sources genuinely overlap; the old source goes quiet
            // while its callback/tap is still alive, before the next handoff.
            clients[AudioObjectID(111 + target)]?.gain = 1
            InterruptionHAL.setClients(clients)
            engine.confirmPlayer(target < 2 ? bundles[target] : nil)
            try await Task.sleep(for: .milliseconds(35))
            for index in 0..<3 where index != target { clients[AudioObjectID(111 + index)]?.gain = 0 }
            InterruptionHAL.setClients(clients)
            try await wait("Overlapping source handoff stalled") { latest.appBundle == bundles[target] && latest.signal.hasAudio }
            interruptionRequire(latest.error == nil && InterruptionHAL.counts.taps == 3 && InterruptionHAL.counts.muted <= 1,
                "Handoff failed, leaked taps or retained multiple mute owners")
        }
        InterruptionHAL.locked { InterruptionHAL.lateCallbacks = InterruptionHAL.callbacks.values.map(\.block) }
        InterruptionHAL.setClients([:])
        try await wait("Retired sources did not release their taps") { InterruptionHAL.counts.taps == 0 && InterruptionHAL.counts.muted == 0 }
        try await Task.sleep(for: .milliseconds(300))
        let retired = InterruptionHAL.packets.count
        try await Task.sleep(for: .milliseconds(200))
        interruptionRequire(InterruptionHAL.packets.count == retired, "Late retired callbacks replayed source haptics")
        engine.stop()
        InterruptionHAL.locked { InterruptionHAL.lateCallbacks = []; InterruptionHAL.browserMusic = false }
        try await wait("Multi-source playback did not stop") { InterruptionHAL.counts.motors == 0 }
    }
    @MainActor static func focusUnderUltra() async throws {
        _ = NSApplication.shared
        InterruptionHAL.grant()
        InterruptionHAL.setClients([111: .init(bundle: "com.spotify.client")])
        let studio = Studio()
        studio.mode = .assist; studio.keyboard = false; studio.followVolume = false
        var tuning = OutputMode.assist.defaults
        tuning.vocalQuality = .light; tuning.automaticTiming = false; tuning.gain = 0; tuning.eq.bass.gain = -12
        studio.tuning = tuning
        studio.start(.macAudio)
        try await wait("Focus fixture did not receive PCM") { studio.captureHealth == .receiving }
        let window = FocusWindow(contentRect: .zero, styleMask: [], backing: .buffered, defer: false)
        let view = PlayerWindowVisibility.VisibilityView()
        view.changed = { studio.display.setVisible($0) }
        window.contentView = view
        try await wait("Visibility observer did not attach") { studio.display.isVisible }
        let opened = InterruptionHAL.locked { InterruptionHAL.opened }
        let packets = InterruptionHAL.packets.count
        studio.startParty(lights: false)
        if studio.partyEnd > 0 {
            let load = CPULoad()
            defer { load.stop() }
            var maximumHeartbeatGap = 0.0
            var thermalLimited = false
            var previous = ProcessInfo.processInfo.systemUptime
            for _ in 0..<180 {
                window.shown = false
                NotificationCenter.default.post(name: NSWindow.didChangeOcclusionStateNotification, object: window)
                NotificationCenter.default.post(name: NSApplication.didResignActiveNotification, object: NSApp)
                try await Task.sleep(for: .milliseconds(60))
                interruptionRequire(!studio.display.isVisible, "Hidden focus transition retained visible UI state")
                window.shown = true
                NotificationCenter.default.post(name: NSApplication.didBecomeActiveNotification, object: NSApp)
                NotificationCenter.default.post(name: NSWindow.didBecomeKeyNotification, object: window)
                try await Task.sleep(for: .milliseconds(60))
                if studio.error == "Ultra stopped because your Mac is getting warm." {
                    thermalLimited = true
                    interruptionRequire(studio.partyEnd == 0 && studio.active, "Thermal cancellation stuck Ultra/listening")
                    break
                }
                interruptionRequire(studio.display.isVisible && studio.active && studio.error == nil, "Focus transition stuck the controller/display")
                let now = ProcessInfo.processInfo.systemUptime
                maximumHeartbeatGap = max(maximumHeartbeatGap, now - previous); previous = now
            }
            interruptionRequire((thermalLimited || InterruptionHAL.packets.count > packets + 8) && InterruptionHAL.locked { InterruptionHAL.opened == opened }, "Focus switching stalled output or rebuilt capture")
            try await wait("Ultra countdown did not expire", seconds: 50) { studio.partyEnd == 0 }
            interruptionRequire(studio.tuning.gain == 0 && studio.tuning.eq.bass.gain == -12 && studio.active, "Ultra/focus changed saved settings or stopped listening")
            if thermalLimited { print("SCOPE LIMIT: Thermal protection ended the burst early; full-duration focus load not exercised on this host.") }
            else { print("PASS: 360 native visibility/activation transitions under two CPU workers through a real 45-second Ultra burst; main-actor maximum heartbeat gap \(maximumHeartbeatGap) s. Notifications are injected, not physical app activations.") }
        } else {
            interruptionRequire(studio.error != nil, "Ultra failed without an explanation")
            print("SCOPE LIMIT: Host thermal state blocked Ultra; guard respected, full burst not exercised.")
        }
        view.detach(); studio.stop()
        try await wait("Focus/Ultra fixture retained resources") { InterruptionHAL.counts.taps == 0 && InterruptionHAL.counts.motors == 0 }
    }
    @MainActor static func main() async throws {
        setbuf(stdout, nil)
        InterruptionHAL.begin()
        defer { InterruptionHAL.finish() }
        guard let id = Bundle.main.bundleIdentifier, id.hasPrefix("studio.songwave.interruption-test.") else { fatalError("Disposable bundle required") }
        UserDefaults.standard.removePersistentDomain(forName: id)
        UserDefaults.standard.setVolatileDomain(["setupComplete": false, "launchListen": false,
            "audioAccessConfigured": true, "firstSuccessPending": false], forName: UserDefaults.argumentDomain)
        for mode in OutputMode.allCases {
            for automatic in [true, false] { try await recycledProcess(automatic: automatic, mode: mode) }
            try await overlappingSources(mode)
        }
        try await pendingReplacement()
        try await focusUnderUltra()
        interruptionRequire(InterruptionHAL.locked { DriverBoundary.symbols.count == 8 && DriverBoundary.opened == DriverBoundary.closed && InterruptionHAL.opened == InterruptionHAL.closed && InterruptionHAL.callbacks.isEmpty && InterruptionHAL.listeners.isEmpty }, "Driver/capture ownership or ABI replacement audit failed")
        print("PASS: real capture/ring/router/Playback/Trackpad driver, recycled same-bundle PIDs, late pending completions, 36 overlapping provider/browser handoffs, retired callbacks, bounded waveforms and complete teardown; only OS/private ABI and metadata edges replaced.")
    }
}
