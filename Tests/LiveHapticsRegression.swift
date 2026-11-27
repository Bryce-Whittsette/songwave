import CoreAudio
import Foundation

// These replace capture I/O only. The production app router, spectrum analysis,
// vocal focus, automatic renderer and motor envelope run unchanged. No OS
// permissions, speakers, keyboard lights or physical actuators are used.
struct GlassError: LocalizedError { let errorDescription: String?; init(_ text: String) { errorDescription = text } }
struct MockClient { var bundle: String; var input: UInt32 = 0; var output: UInt32 = 1 }
enum AudioHardware {
    static var clients: [UInt32: MockClient] = [:]
    static func processList() -> [AudioObjectID] { Array(clients.keys) }
    static func read<T>(_ id: AudioObjectID, _ property: UInt32, into value: inout T) -> OSStatus {
        guard let client = clients[id] else { return -1 }
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
final class MockRing {
    static var position = 0
    static var silent = false
    func takeNewest(maximum: Int, into samples: inout [Float]) {
        samples = (0..<192).map { offset in
            let t = Double(Self.position + offset) / 24000
            let age = (t - 0.25).truncatingRemainder(dividingBy: 0.5)
            let kick = age >= 0 ? 0.20 * exp(-age * 24) * sin(2 * .pi * 70 * age) : 0
            let voice = (1...8).reduce(0.0) { $0 + 0.04 / Double($1) * sin(2 * .pi * 224 * Double($1) * t) }
            return Self.silent ? 0 : Float(kick + voice)
        }
        Self.position += samples.count
    }
}
final class AudioTap {
    static var muted: Set<UInt32> = []
    static var live = 0
    let rate = 24000.0
    let ring = MockRing()
    let id: UInt32
    init(description: CATapDescription, mute: Bool) throws {
        id = description.processes[0]
        Self.live += 1
    }
    func setMuted(_ muted: Bool) throws {
        if muted { Self.muted.insert(id) } else { Self.muted.remove(id) }
    }
    deinit { Self.muted.remove(id); Self.live -= 1 }
}
struct YouTubeState {
    static var states: [Self] = []
    var browser: String
    var category: String
    var videoID: String?
    static func playing() -> [Self] { states }
    static func family(for bundle: String) -> String? { bundle.contains("Chrome") ? "chrome" : nil }
}

@main struct LiveHapticsRegression {
    static func main() throws {
        var cases = 0
        for bundle in ["com.spotify.client", "com.apple.Music", "com.google.Chrome"] {
            for mode in OutputMode.allCases {
                try autoreleasepool {
                    MockRing.position = 0; MockRing.silent = false
                    AudioHardware.clients = [111: MockClient(bundle: bundle)]
                    YouTubeState.states = bundle.contains("Chrome") ? [YouTubeState(browser: "chrome", category: "music", videoID: "song")] : []
                    let router = MacMusicInput()
                    router.confirmedPlayer = bundle.contains("Chrome") ? nil : bundle
                    var spectrum = try Spectrum(sampleRate: 24000)
                    var renderer = AutomaticHaptics()
                    var motor = MotorEnvelope()
                    var now = ProcessInfo.processInfo.systemUptime
                    var packets = 0, attacks = 0
                    for _ in 0..<350 {
                        var frame = SignalFrame.empty
                        try router.read(now: now, mute: mode == .trackpad) { samples, _, changed in
                            if changed { spectrum = try Spectrum(sampleRate: 24000); renderer = AutomaticHaptics() }
                            for sample in samples { spectrum.append(sample) }
                            frame = spectrum.frame(tuning: mode.defaults, mode: mode)
                        }
                        let output = renderer.frame(frame, mode: mode, blocked: router.suppressOutput, at: now)
                        let level = motor.level(target: output.level, transient: output.beatStrength > 0, at: now)
                        if level > 0.02 && !output.tones.isEmpty { packets += 1 }
                        if output.beatStrength > 0 { attacks += 1 }
                        now += 0.008
                    }
                    precondition(packets > 10 && router.activeBundle == bundle, "An app needed a file or pattern to generate live haptics.")
                    if mode == .assist { precondition(attacks >= 4 && AudioTap.muted.isEmpty) }
                    else { precondition(AudioTap.muted == [111]) }
                    AudioHardware.clients[113] = MockClient(bundle: "com.apple.CoreSpeech", input: 1, output: 0)
                    now += 0.4
                    try router.read(now: now, mute: mode == .trackpad) { _, _, _ in }
                    precondition(router.dictationActive && !router.suppressOutput && router.activeBundle == bundle,
                        "Keyboard Dictation must not replace or pause verified music.")
                    precondition(AudioTap.live == 1, "Dictation's microphone must never become a capture feed.")
                    AudioHardware.clients[113] = MockClient(bundle: "com.apple.CoreSpeech", input: 1, output: 1)
                    now += 0.4
                    try router.read(now: now, mute: mode == .trackpad) { _, _, _ in }
                    precondition(AudioTap.live == 1 && !router.suppressOutput)
                    AudioHardware.clients[112] = MockClient(bundle: "com.apple.FaceTime", input: 1)
                    now += 0.4
                    try router.read(now: now, mute: mode == .trackpad) { _, _, _ in preconditionFailure("Call audio was admitted") }
                    precondition(router.suppressOutput)
                    precondition(renderer.frame(.empty, mode: mode, blocked: router.suppressOutput, at: now).level == 0)
                    precondition(AudioTap.muted.isEmpty)
                    AudioHardware.clients.removeValue(forKey: 112)
                    AudioHardware.clients.removeValue(forKey: 113)
                    now += 2.5
                    try router.read(now: now, mute: mode == .trackpad) { _, _, _ in }
                    precondition(!router.dictationActive && !router.suppressOutput,
                        "Dictation continuity must expire and calls must release normally.")
                    cases += 1
                }
                precondition(AudioTap.live == 0, "A capture tap leaked")
            }
        }
        // Host-time amplitude ramps give the same result at different tick rates.
        func settled(_ tick: Double) -> Double {
            var motor = MotorEnvelope()
            _ = motor.level(target: 0, transient: false, at: 0)
            var level = 0.0
            for i in 1...Int((0.048 / tick).rounded()) { level = motor.level(target: 0.7, transient: false, at: Double(i) * tick) }
            return level
        }
        precondition(abs(settled(0.008) - settled(0.016)) < 1e-9)
        var renderer = AutomaticHaptics()
        let hit = SignalFrame(tones: [], level: 1, bands: [], inputRMS: 0.1, hasAudio: true, beatStrength: 1)
        _ = renderer.frame(hit, mode: .assist, blocked: false, at: 1)
        _ = renderer.frame(.empty, mode: .trackpad, blocked: false, at: 1.01)
        precondition(renderer.frame(.empty, mode: .assist, blocked: false, at: 1.02).level == 0, "A mode switch replayed an old beat.")
        precondition(renderer.frame(.empty, mode: .assist, blocked: false, at: 1.5).level == 0)
        print("\(cases) simulated Spotify/Music/browser live streams generated automatic haptics in both modes; call suppression, tap cleanup, mode resets and cadence-independent fades passed.")
    }
}
