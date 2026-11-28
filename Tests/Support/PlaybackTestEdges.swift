import CoreAudio
import Foundation

// Keep assertion locations visible even in optimized CI executables.
func require(_ condition: @autoclosure () -> Bool, _ message: String = "",
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
    private static var captureBarrier: DispatchSemaphore?
    private static var enteredCapture = 0
    private static var failCapture = false
    private static var volume = 1.0
    private static var sampleRate = 24000.0
    private static var routeGeneration = 0
    static func locked<T>(_ operation: () -> T) -> T { lock.lock(); defer { lock.unlock() }; return operation() }
    static func set(_ next: [UInt32: LifecycleClient]) { locked { clients = next } }
    static func snapshot() -> [UInt32: LifecycleClient] { locked { clients } }
    static func packet(_ level: Double) { locked { packets.append((ProcessInfo.processInfo.systemUptime, level)) } }
    static var outputVolume: Double { get { locked { volume } } set { locked { volume = newValue } } }
    static var writes: [(time: Double, level: Double)] { locked { packets } }
    static var liveTaps: Int { locked { taps } }
    static var mutedTaps: Int { locked { muted } }
    static var liveMotors: Int { locked { motors } }
    static func tap(_ delta: Int) { locked { taps += delta } }
    static func mute(_ delta: Int) { locked { muted += delta } }
    static func motor(_ delta: Int) { locked { motors += delta } }
    static func blockCapture() { locked { captureBarrier = DispatchSemaphore(value: 0); enteredCapture = 0 } }
    static var captureAttempts: Int { locked { enteredCapture } }
    static func waitForCaptureIfBlocked() {
        let barrier = locked { enteredCapture += 1; return captureBarrier }
        barrier?.wait()
    }
    static func releaseCapture() {
        let barrier = locked { let prior = captureBarrier; captureBarrier = nil; return prior }
        for _ in 0..<8 { barrier?.signal() }
    }
    static var route: (rate: Double, generation: Int) { locked { (sampleRate, routeGeneration) } }
    static func changeRoute(rate: Double) { locked { sampleRate = rate; routeGeneration += 1 } }
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
    private let rate: Double
    init(rate: Double) { self.rate = rate }
    func takeNewest(maximum: Int, into samples: inout [Float]) {
        samples = (0..<Int(rate * 0.008)).map { offset in
            let time = Double(position + offset) / rate
            let voice = (1...8).reduce(0.0) { $0 + 0.045 / Double($1) * sin(2 * .pi * 224 * Double($1) * time) }
            return Float(0.18 * sin(2 * .pi * 65 * time) + voice)
        }
        position += samples.count
    }
}
final class AudioTap {
    let rate: Double
    let ring: LifecycleRing
    private let generation: Int
    var needsReconnect: Bool { generation != LifecycleHardware.route.generation }
    private var opened = false
    private var muted = false
    init(description: CATapDescription, mute: Bool) throws {
        let route = LifecycleHardware.route
        rate = route.rate; generation = route.generation; ring = LifecycleRing(rate: route.rate)
        LifecycleHardware.waitForCaptureIfBlocked()
        if LifecycleHardware.captureFails() { throw GlassError("Injected capture failure") }
        LifecycleHardware.tap(1)
        opened = true
        try setMuted(mute)
    }
    func setMuted(_ next: Bool) throws {
        require(!next || !needsReconnect, "A stale startup result applied speaker muting")
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
        // Match the production driver's no-op contract for silence/unvoiced PCM.
        guard !tones.isEmpty, level > 0.005 else { return }
        require(milliseconds > 0 && milliseconds <= 16)
        require(level.isFinite && (0...1).contains(level))
        require(tones.allSatisfy { $0.hertz.isFinite && $0.weight.isFinite }, "Nonfinite motor tones")
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
    static func accent(elapsed: Double) -> Bool {
        elapsed >= 0 && elapsed < length && elapsed.truncatingRemainder(dividingBy: 0.36) < 0.12
    }
}
enum OutputVolume { static func read() -> Double { LifecycleHardware.outputVolume } }
enum OutputTiming {
    static func reportedDelay() -> Double { 0 }
    static func additionalDelay(reported: Double, analysisRate: Double, offsetMS: Double, focus: HapticFocus = .beat) -> Double { max(0, offsetMS / 1000) }
}
final class KeyboardLight { init?() { return nil }; func update(beatStrength: Double, now: Double) {} }
#if !SONGWAVE_REAL_ISOLATION_TEST
final class IsolatedVocals {
    init() { preconditionFailure("The Light playback lifecycle suite must not load a neural model") }
    var failure: String? { nil }; var isReady: Bool { false }; var hasPendingAudio: Bool { false }
    var isDrained: Bool { true }; var status: String { "Mock isolation" }; var latency: Double { 0 }
    func reset() {}; func cancel() {}; func finish() {}
    func push(_ samples: [Float], rate: Double, at now: Double) {}
    func read(maximum: Int, at now: Double) -> [Float] { [] }
}

#endif
