import CoreAudio
import Foundation

// Keep assertion locations visible even in optimized CI executables.
private func require(_ condition: @autoclosure () -> Bool, _ message: String = "",
                     file: StaticString = #filePath, line: UInt = #line) {
    guard condition() else {
        FileHandle.standardError.write(Data("Lifecycle assertion failed at \(file):\(line): \(message)\n".utf8))
        exit(1)
    }
}

// Boundary replacements only: the production Playback/Session, call policy,
// spectrum, automatic renderer and output gain run unchanged. No recording
// permission, speaker, keyboard, actuator or neural model is used in this suite.
struct GlassError: LocalizedError { let errorDescription: String?; init(_ text: String) { errorDescription = text } }
struct LifecycleClient { var bundle: String; var input: UInt32 = 0; var output: UInt32 = 1 }
enum LifecycleHardware {
    static let lock = NSLock()
    private static var clients: [UInt32: LifecycleClient] = [:]
    private static var packets: [(time: Double, level: Double)] = []
    private static var taps = 0
    private static var muted = 0
    private static var motors = 0
    private static var failCapture = false
    static func locked<T>(_ operation: () -> T) -> T { lock.lock(); defer { lock.unlock() }; return operation() }
    static func set(_ next: [UInt32: LifecycleClient]) { locked { clients = next } }
    static func snapshot() -> [UInt32: LifecycleClient] { locked { clients } }
    static func packet(_ level: Double) { locked { packets.append((ProcessInfo.processInfo.systemUptime, level)) } }
    static var writes: [(time: Double, level: Double)] { locked { packets } }
    static var liveTaps: Int { locked { taps } }
    static var mutedTaps: Int { locked { muted } }
    static var liveMotors: Int { locked { motors } }
    static func tap(_ delta: Int) { locked { taps += delta } }
    static func mute(_ delta: Int) { locked { muted += delta } }
    static func motor(_ delta: Int) { locked { motors += delta } }
    static func failNextCapture() { locked { failCapture = true } }
    static func captureFails() -> Bool { locked { let value = failCapture; failCapture = false; return value } }
    static func clear() { locked { require(taps == 0 && motors == 0 && muted == 0); packets.removeAll(); clients.removeAll(); failCapture = false } }
}
enum AudioHardware {
    static func processList() -> [AudioObjectID] { Array(LifecycleHardware.snapshot().keys) }
    static func processIDs(for bundle: String, appPath: String) -> [AudioObjectID] {
        LifecycleHardware.snapshot().filter { $0.value.bundle == bundle && $0.value.output != 0 }.map(\.key)
    }
    static func read<T>(_ id: AudioObjectID, _ property: UInt32, into value: inout T) -> OSStatus {
        guard let client = LifecycleHardware.snapshot()[id] else { return -1 }
        switch property {
        case kAudioProcessPropertyIsRunningInput: value = client.input as! T
        case kAudioProcessPropertyIsRunningOutput: value = client.output as! T
        case kAudioProcessPropertyPID: value = Int32(500000 + id) as! T
        case kAudioProcessPropertyBundleID: value = Optional(Unmanaged.passRetained(client.bundle as CFString)) as! T
        default: return -1
        }
        return 0
    }
}
final class LifecycleRing {
    private var position = 0
    func takeNewest(maximum: Int, into samples: inout [Float]) {
        samples = (0..<192).map { offset in
            let time = Double(position + offset) / 24000
            let voice = (1...8).reduce(0.0) { $0 + 0.045 / Double($1) * sin(2 * .pi * 224 * Double($1) * time) }
            return Float(0.18 * sin(2 * .pi * 65 * time) + voice)
        }
        position += samples.count
    }
}
final class AudioTap {
    let rate = 24000.0
    let ring = LifecycleRing()
    private var opened = false
    private var muted = false
    init(description: CATapDescription, mute: Bool) throws {
        if LifecycleHardware.captureFails() { throw GlassError("Injected capture failure") }
        LifecycleHardware.tap(1)
        opened = true
        try setMuted(mute)
    }
    func setMuted(_ next: Bool) throws {
        if muted != next { muted = next; LifecycleHardware.mute(next ? 1 : -1) }
    }
    deinit {
        if opened { LifecycleHardware.tap(-1) }
        if muted { LifecycleHardware.mute(-1) }
    }
}
func fold(_ left: Float, _ right: Float) -> Float { (left + right) * 0.5 }
final class Trackpad {
    let name = "Mock trackpad"
    init() throws { LifecycleHardware.motor(1) }
    func play(_ tones: [Tone], for milliseconds: Double, level: Double) throws {
        require(milliseconds > 0 && milliseconds <= 16)
        require(level.isFinite && (0...1).contains(level))
        require(!tones.isEmpty && tones.allSatisfy { $0.hertz.isFinite && $0.weight.isFinite })
        LifecycleHardware.packet(level)
    }
    deinit { LifecycleHardware.motor(-1) }
}
struct YouTubeState {
    var browser: String; var category: String; var videoID: String?
    static func playing() -> [Self] { [] }
    static func family(for bundle: String) -> String? { nil }
}
struct PartyBurst {
    static let length = 45.0
    static func allowed(thermal: ProcessInfo.ThermalState) -> Bool { true }
    static func accent(elapsed: Double) -> Bool { false }
}
enum OutputVolume { static func read() -> Double { 1 } }
enum OutputTiming {
    static func reportedDelay() -> Double { 0 }
    static func additionalDelay(reported: Double, analysisRate: Double, offsetMS: Double) -> Double { max(0, offsetMS / 1000) }
}
final class KeyboardLight { init?() { return nil }; func update(beatStrength: Double, now: Double) {} }
final class IsolatedVocals {
    init() { preconditionFailure("The Light playback lifecycle suite must not load a neural model") }
    var failure: String? { nil }; var isReady: Bool { false }; var hasPendingAudio: Bool { false }
    var isDrained: Bool { true }; var status: String { "Mock isolation" }; var latency: Double { 0 }
    func reset() {}; func cancel() {}; func finish() {}
    func push(_ samples: [Float], rate: Double, at now: Double) {}
    func read(maximum: Int, at now: Double) -> [Float] { [] }
}

@main struct PlaybackLifecycleRegression {
    static func wait(_ description: String, timeout: Double = 3, until condition: () -> Bool) {
        let end = Date(timeIntervalSinceNow: timeout)
        while !condition() && Date() < end { RunLoop.current.run(until: Date(timeIntervalSinceNow: 0.002)) }
        require(condition(), description)
    }
    static func run(for duration: Double) { RunLoop.current.run(until: Date(timeIntervalSinceNow: duration)) }
    static func gain() {
        for cadence in [0.008, 0.016] {
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
    static func main() throws {
        gain()
        var cases = 0
        for provider in Provider.allCases {
            for mode in OutputMode.allCases {
                LifecycleHardware.clear()
                let client = LifecycleClient(bundle: provider.bundle)
                let idleCall = LifecycleClient(bundle: "com.apple.FaceTime", output: 0)
                LifecycleHardware.set([111: client, 112: idleCall])
                require(!CallAudioPolicy.active(in: AudioHardware.processList().compactMap(AudioClient.init)), "An idle FaceTime app is not a call")
                let link = try MusicLink(provider == .spotify ? "spotify:track:0000000000000000000000" : "https://music.apple.com/us/song/test/123")
                let engine = Playback()
                var tuning = mode.defaults
                tuning.automaticTiming = false
                engine.start(.player(link), tuning: tuning, mode: mode, playerPath: "/Mock/Player.app", startAt: 0) { _ in }
                wait("The explicit player route failed to produce output with inactive FaceTime open") { LifecycleHardware.writes.count > 12 }
                require(LifecycleHardware.mutedTaps == (mode == .trackpad ? 1 : 0))
                let beforeBypass = LifecycleHardware.writes.count
                engine.setHaptics(false)
                run(for: 0.09)
                require(LifecycleHardware.writes.count > beforeBypass + 2, "Manual bypass hard-cut instead of rendering a fade")
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
        print("\(cases) explicit Spotify/Music routes passed: idle FaceTime, gradual bypass, resume, immediate recognized-call suppression, reconnect, and capture-failure cleanup; gain cadence/reversal checks passed.")
    }
}
