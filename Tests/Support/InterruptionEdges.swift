import AppKit
import Foundation

func interruptionRequire(_ condition: @autoclosure () -> Bool, _ message: String,
                         file: StaticString = #filePath, line: UInt = #line) {
    guard condition() else { fputs("Interruption regression failed at \(file):\(line): \(message)\n", stderr); exit(1) }
}
#if !SONGWAVE_DRIVER_BOUNDARY_TEST
struct GlassError: LocalizedError { let errorDescription: String?; init(_ value: String) { errorDescription = value } }
#endif
struct TrackInfo: Equatable { var title: String; var artist: String?; var cover: Data? }
struct PlayerTrack { var id: String; var info: TrackInfo; var duration: Double; var position: Double; var observed: Double }
struct YouTubeState {
    var browser = ""; var category = "music"; var title = ""; var position = 0.0; var duration: Double?; var videoID: String?
    static func playing() -> [Self] { InterruptionHAL.locked { InterruptionHAL.browserMusic ? [Self(browser: "chrome", videoID: "fixture")] : [] } }
    static func family(for bundle: String) -> String? { bundle.contains("Chrome") ? "chrome" : nil }
}
enum TrackCatalog {
    static func metadata(for: PlaybackSource) async -> TrackInfo? { nil }
    static func playing(_ provider: Provider) async -> PlayerTrack? {
        PlayerTrack(id: "spotify:track:fixture", info: TrackInfo(title: "Private fixture title"), duration: 180,
                    position: 10, observed: ProcessInfo.processInfo.systemUptime)
    }
    static func cover(for: PlayerTrack, provider: Provider) async -> Data? { nil }
    static func videoCover(_ id: String?) async -> Data? { nil }
}
enum ListeningDiagnostics { static let macModel = "Mac16,13"; static func outputRoute() -> DiagnosticRoute { .builtIn } }
#if !SONGWAVE_DRIVER_BOUNDARY_TEST
enum ProjectShare { static let canMessage = false; static func message() {}; static func copy() {} }
struct PartyBurst {
    static let length = 45.0, recovery = 60.0
    static func allowed(thermal: ProcessInfo.ThermalState) -> Bool { true }
    static func accent(elapsed: Double) -> Bool { false }
}
final class Trackpad {
    let name = "Fixture trackpad"
    init() throws { InterruptionHAL.locked { InterruptionHAL.motors += 1 } }
    func play(_ tones: [Tone], for milliseconds: Double, level: Double) throws {
        guard !tones.isEmpty, level > 0.005 else { return }
        interruptionRequire(milliseconds > 0 && milliseconds <= 16 && level.isFinite && (0...1).contains(level), "Invalid output packet")
        interruptionRequire(tones.allSatisfy { $0.hertz.isFinite && $0.weight.isFinite }, "Nonfinite output tone")
        InterruptionHAL.locked { InterruptionHAL.writes.append((ProcessInfo.processInfo.systemUptime, level)) }
    }
    deinit { InterruptionHAL.locked { InterruptionHAL.motors -= 1 } }
}
enum OutputVolume { static func read() -> Double { 1 } }
enum OutputTiming {
    static func reportedDelay() -> Double { 0 }
    static func additionalDelay(reported: Double, analysisRate: Double, offsetMS: Double, focus: HapticFocus = .beat) -> Double { max(0, offsetMS / 1000) }
}
final class KeyboardLight { init?() { nil }; func update(beatStrength: Double, now: Double) {} }
#endif
final class IsolatedVocals {
    init() { preconditionFailure("This interruption fixture must not load or replace a separation model") }
    var failure: String? { nil }; var isReady: Bool { false }; var hasPendingAudio: Bool { false }
    var isDrained: Bool { true }; var status: String { "Unused isolation boundary" }; var latency: Double { 0 }
    func reset() {}; func cancel() {}; func finish() {}
    func push(_ samples: [Float], rate: Double, at now: Double) {}
    func read(maximum: Int, at now: Double) -> [Float] { [] }
}
