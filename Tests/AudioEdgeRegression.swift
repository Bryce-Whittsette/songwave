import AVFoundation
import Foundation

// Playback's speaker edge is compile-time replaced too. Real AVAudioFile reads
// disposable PCM; this clock never opens an output device or plays a sound.
final class AVAudioPlayer {
    private var position = 0.0
    private var started: Double?
    var isPlaying: Bool { started != nil }
    var currentTime: Double {
        get { position + (started.map { ProcessInfo.processInfo.systemUptime - $0 } ?? 0) }
        set { position = newValue; if started != nil { started = ProcessInfo.processInfo.systemUptime } }
    }
    init(contentsOf: URL) throws {}
    func prepareToPlay() -> Bool { true }
    func play() -> Bool { started = ProcessInfo.processInfo.systemUptime; return true }
    func stop() { position = currentTime; started = nil }
}

@main struct AudioEdgeRegression {
    @MainActor static func wait(_ label: String, seconds: Double = 5, _ condition: () -> Bool) async throws {
        let end = ContinuousClock.now.advanced(by: .seconds(seconds))
        while !condition() && ContinuousClock.now < end { try await Task.sleep(for: .milliseconds(10)) }
        interruptionRequire(condition(), label)
    }
    @MainActor static func stop(_ engine: Playback) async throws {
        engine.stop()
        try await wait("Edge fixture leaked capture or output resources") {
            let n = InterruptionHAL.counts
            return n.taps == 0 && n.callbacks == 0 && n.listeners == 0 && n.motors == 0 && n.muted == 0
        }
    }
    static func frameIsSafe(_ frame: SignalFrame) {
        interruptionRequire(frame.level.isFinite && (0...1).contains(frame.level) && frame.inputRMS.isFinite &&
            frame.beatStrength.isFinite && (0...1).contains(frame.beatStrength) &&
            frame.tones.allSatisfy { $0.hertz.isFinite && $0.weight.isFinite && $0.weight >= 0 }, "Corrupt input escaped into a signal/output frame")
    }
    static func maximumPackets() {
        let ring = SampleRing()
        let samples = (0..<262_144).map { Float($0 % 1000) / 1000 }
        var output: [Float] = []
        samples.withUnsafeBufferPointer { source in
            var list = AudioBufferList(mNumberBuffers: 1, mBuffers: AudioBuffer(mNumberChannels: 1,
                mDataByteSize: 1_048_576, mData: UnsafeMutableRawPointer(mutating: source.baseAddress)))
            for _ in 0..<50 { withUnsafePointer(to: &list) { ring.push($0) } }
            ring.takeNewest(maximum: .max, into: &output)
            interruptionRequire(output == Array(samples.suffix(32_768)), "Maximum valid packets exceeded capacity or lost their newest samples")
            list.mBuffers.mDataByteSize = 1_048_580
            withUnsafePointer(to: &list) { ring.push($0) }
            ring.takeNewest(maximum: .max, into: &output)
            interruptionRequire(output.isEmpty, "A declared oversize packet crossed the storage boundary")
        }
        print("PASS: 50 maximum-valid 1 MiB PCM packets (13,107,200 offered samples) retain exactly the newest 32,768 samples; an oversized declaration is rejected before access.")
    }
    @MainActor static func captureEdges() async throws {
        var cases = 0
        for rate in [8000.0, 192000.0] {
            for automatic in [false, true] {
                for mode in OutputMode.allCases {
                    InterruptionHAL.grant()
                    InterruptionHAL.locked { InterruptionHAL.sampleRate = rate; InterruptionHAL.frames = 0 }
                    InterruptionHAL.setClients([111: .init(bundle: "com.spotify.client")])
                    let engine = Playback()
                    var latest = PlaybackUpdate()
                    var tuning = mode.defaults
                    tuning.hapticFocus = .both; tuning.vocalQuality = .light; tuning.automaticTiming = false; tuning.delay = 0
                    let source: PlaybackSource = automatic ? .macAudio : .player(try MusicLink("spotify:track:0000000000000000000000"))
                    engine.start(source, tuning: tuning, mode: mode, playerPath: "/Fixture/Player.app", startAt: 0) { update in
                        frameIsSafe(update.signal); latest = update
                    }
                    if automatic { engine.confirmPlayer("com.spotify.client") }
                    let before = InterruptionHAL.packets.count
                    try await wait("Real callback/ring produced no output at \(rate) Hz") { InterruptionHAL.packets.count > before + 4 && latest.signal.hasAudio }
                    interruptionRequire(InterruptionHAL.counts.muted == (mode == .trackpad ? 1 : 0), "Extreme-rate routing was wrong")
                    // All backing storage is valid. Only the declared layout or
                    // scalar contents is malformed; never pass dangling memory.
                    for packet in InterruptionHAL.Delivery.allCases where packet != .music {
                        InterruptionHAL.locked { InterruptionHAL.delivery = packet }
                        try await Task.sleep(for: .milliseconds(35))
                        interruptionRequire(latest.error == nil, "A malformed callback crashed/failed playback")
                    }
                    InterruptionHAL.locked { InterruptionHAL.delivery = .empty }
                    try await wait("Empty callbacks retained audio or mute ownership") {
                        latest.captureInterrupted && latest.waiting && InterruptionHAL.counts.muted == 0
                    }
                    try await Task.sleep(for: .milliseconds(200))
                    let quiet = InterruptionHAL.packets.count
                    try await Task.sleep(for: .milliseconds(150))
                    interruptionRequire(InterruptionHAL.packets.count == quiet && latest.error == nil,
                        "Malformed/stale PCM replayed haptics after settling")
                    InterruptionHAL.locked { InterruptionHAL.delivery = .music }
                    try await wait("Fresh PCM did not recover after malformed callbacks") {
                        InterruptionHAL.packets.count > quiet + 4 && !latest.captureInterrupted &&
                            InterruptionHAL.counts.muted == (mode == .trackpad ? 1 : 0)
                    }
                    try await stop(engine)
                    cases += 1
                }
            }
        }
        print("PASS: \(cases) real callback/ring/playback routes at 8/192 kHz, both outputs and automatic/explicit sources; empty, half-frame, missing, misaligned, oversized, malformed-plane and nonfinite PCM; silence/mute release and fresh recovery.")
    }
    static func longPattern(curves: Int = 0) throws -> (HapticPattern, Data) {
        let count = 4096 - curves
        var entries: [[String: Any]] = (0..<count).map { index in
            let last = index == count - 1
            var event: [String: Any] = ["Time": 3600 * Double(index) / Double(count - 1),
                "EventType": last ? "HapticContinuous" : "HapticTransient",
                "EventParameters": [["ParameterID": "HapticIntensity", "ParameterValue": 0.4]]]
            if last { event["EventDuration"] = 30 }
            return ["Event": event]
        }
        for index in 0..<curves {
            entries.append(["ParameterCurve": ["Time": Double(index) * 3600 / Double(curves),
                "ParameterID": index.isMultiple(of: 2) ? "HapticIntensityControl" : "HapticSharpnessControl",
                "ParameterCurveControlPoints": (0..<16).map { ["Time": Double($0) * 2, "ParameterValue": 0.5] }]])
        }
        let data = try JSONSerialization.data(withJSONObject: ["Version": 1, "Pattern": entries])
        return (try HapticPattern(data: data), data)
    }
    static func patternScheduling() throws -> HapticPattern {
        let (pattern, bytes) = try longPattern()
        interruptionRequire(pattern.events.count == 4096, "Maximum-event fixture was not accepted")
        var padded = bytes
        padded.append(Data(repeating: 32, count: 1_048_576 - bytes.count))
        _ = try HapticPattern(data: padded)
        padded.append(32)
        do { _ = try HapticPattern(data: padded); interruptionRequire(false, "Over-byte-limit pattern was accepted") } catch {}
        var player = HapticPattern.Player(pattern)
        let start = ContinuousClock.now
        var attacks = 0
        for tick in 0...453_750 {
            let frame = player.frame(at: Double(tick) * 0.008)
            frameIsSafe(frame)
            if frame.beatStrength > 0 { attacks += 1 }
        }
        interruptionRequire(attacks == 4095 && !player.frame(at: 3630).hasAudio,
            "An hour-long pattern dropped/doubled a scheduled transient or retained its final sustain")
        for seek in [1800.0, 0, 3599, 30, 3600, 0] {
            let frame = player.frame(at: seek)
            frameIsSafe(frame)
            let expected = pattern.events.filter { $0.transient && $0.time <= seek && $0.time + $0.duration > seek }.map(\.intensity).max() ?? 0
            interruptionRequire(abs(frame.beatStrength - expected) < 0.000001, "Seek replayed expired events or lost a current attack")
            interruptionRequire(player.frame(at: seek).beatStrength == 0, "Repeated audio-clock position doubled a beat")
        }
        interruptionRequire(!player.frame(at: .nan).hasAudio && !player.frame(at: -.infinity).hasAudio,
            "Invalid transport time generated output")
        interruptionRequire(!player.frame(at: 100_000).hasAudio, "Late transport callback replayed a backlog")
        let (automated, _) = try longPattern(curves: 256)
        var curved = HapticPattern.Player(automated)
        for index in 0..<12_000 {
            let time = index.isMultiple(of: 31) ? Double(index % 3600) : Double(index) * 0.31
            frameIsSafe(curved.frame(at: time))
        }
        print("PASS: 4,096-entry / 1 MiB boundary, 453,751 simulated 8 ms ticks through 60m30s, exact transient count, long sustain expiry, late/repeated/invalid clocks, backwards seeks and 256 curves. Simulation took \(start.duration(to: .now)); not a physical hour-long run.")
        return pattern
    }
    static func sparseWAV(_ url: URL) throws {
        let bytes = UInt32(3631 * 8000 * 4)
        var header = Data("RIFF".utf8)
        func u32(_ value: UInt32) { var v = value.littleEndian; withUnsafeBytes(of: &v) { header.append(contentsOf: $0) } }
        func u16(_ value: UInt16) { var v = value.littleEndian; withUnsafeBytes(of: &v) { header.append(contentsOf: $0) } }
        u32(bytes + 36); header.append(Data("WAVEfmt ".utf8)); u32(16); u16(3); u16(1)
        u32(8000); u32(32000); u16(4); u16(32); header.append(Data("data".utf8)); u32(bytes)
        try header.write(to: url)
        let file = try FileHandle(forWritingTo: url)
        defer { try? file.close() }
        try file.truncate(atOffset: UInt64(bytes) + 44)
    }
    @MainActor static func authoredPlayback(_ pattern: HapticPattern) async throws {
        let directory = FileManager.default.temporaryDirectory.appendingPathComponent("songwave-ahap-edge-" + UUID().uuidString)
        try FileManager.default.createDirectory(at: directory, withIntermediateDirectories: true)
        defer { try? FileManager.default.removeItem(at: directory) }
        let url = directory.appendingPathComponent("sparse.wav")
        try sparseWAV(url)
        let engine = Playback()
        engine.setPattern(pattern)
        var tuning = OutputMode.assist.defaults
        tuning.vocalQuality = .light; tuning.automaticTiming = false; tuning.delay = 0
        var failure: String?
        let before = InterruptionHAL.packets.count
        engine.start(.file(url), tuning: tuning, mode: .assist, playerPath: nil, startAt: 3599.9) { failure = $0.error ?? failure }
        try await wait("Late-song authored playback did not reach its final sustained event") { InterruptionHAL.packets.count > before + 4 || failure != nil }
        interruptionRequire(failure == nil, "Sparse WAV playback failed: \(failure ?? "")")
        for _ in 0..<100 { engine.setPattern(pattern); engine.setPattern(nil) }
        engine.setPattern(pattern)
        try await Task.sleep(for: .milliseconds(150))
        engine.setHaptics(false)
        try await Task.sleep(for: .milliseconds(250))
        let quiet = InterruptionHAL.packets.count
        try await Task.sleep(for: .milliseconds(100))
        interruptionRequire(InterruptionHAL.packets.count == quiet, "Long AHAP bypass retained output")
        engine.setHaptics(true)
        try await wait("Long AHAP did not resume after bypass/replacement") { InterruptionHAL.packets.count > quiet + 4 }
        try await stop(engine)
        let stopped = InterruptionHAL.packets.count
        try await Task.sleep(for: .milliseconds(100))
        interruptionRequire(InterruptionHAL.packets.count == stopped, "Stop retained scheduled AHAP output")
        print("PASS: real Playback scheduling near 60 minutes, 200 pattern replace/remove operations, bypass/resume and Stop; mocked speaker/actuator, disposable sparse WAV.")
    }
    @MainActor static func main() async throws {
        setbuf(stdout, nil)
        maximumPackets()
        let pattern = try patternScheduling()
        InterruptionHAL.begin()
        defer { InterruptionHAL.finish() }
        try await captureEdges()
        try await authoredPlayback(pattern)
        interruptionRequire(InterruptionHAL.locked { InterruptionHAL.opened == InterruptionHAL.closed && InterruptionHAL.aggregates.isEmpty }, "Edge fixture leaked SDK ownership")
    }
}
