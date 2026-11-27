import AppKit
import Foundation

// The real Studio coordinates state. Replace only audio/hardware/catalog edges;
// this executable uses its own preference domain and no recording permission.
struct GlassError: LocalizedError { let errorDescription: String?; init(_ value: String) { errorDescription = value } }
struct TrackInfo: Equatable { var title: String; var artist: String?; var cover: Data? }
struct PlayerTrack { var id: String; var info: TrackInfo; var duration: Double; var position: Double; var observed: Double }
struct YouTubeState { var browser = ""; var title = ""; var position = 0.0; var duration: Double?; var videoID: String? }
enum TrackCatalog {
    static func metadata(for: PlaybackSource) async -> TrackInfo? { nil }
    static func playing(_ provider: Provider) async -> PlayerTrack? { nil }
    static func cover(for: PlayerTrack, provider: Provider) async -> Data? { nil }
    static func videoCover(_ id: String?) async -> Data? { nil }
}
enum ListeningDiagnostics { static let macModel = "Mac16,13"; static func outputRoute() -> DiagnosticRoute { .builtIn } }
enum PlaybackAccess {
    static var failure: String?
    static var requests = 0
    static var holdRequests = false
    static var requestContinuation: CheckedContinuation<Void, Never>?
    static func playerStatus(_ pid: pid_t, ask: Bool) -> Int32 { 0 }
    static func requestAudio() async throws {
        requests += 1
        if holdRequests { await withCheckedContinuation { requestContinuation = $0 } }
        if let failure { throw GlassError(failure) }
    }
}
struct PartyBurst {
    static let length = 45.0, recovery = 60.0
    static func allowed(thermal: ProcessInfo.ThermalState) -> Bool { true }
}
struct PlaybackUpdate {
    var signal = SignalFrame.empty; var elapsed = 0.0; var duration: Double?; var device: String?
    var waiting = false; var video: YouTubeState?; var appBundle: String?; var detection: String?
    var processingDelay = 0.0; var partyOverheated = false; var finished = false; var error: String?
}
final class Playback {
    struct Run { let source: PlaybackSource; let mode: OutputMode; let haptics: Bool; let position: Double }
    static var runs: [Run] = []
    static var pattern: HapticPattern?
    static var lastUpdate: ((PlaybackUpdate) -> Void)?
    static var testCompletion: ((String?) -> Void)?
    static var tests = 0
    static var probes = 0
    static var probeDevice: String? = "Mock trackpad"
    static var probeFailure: String?
    func start(_ source: PlaybackSource, tuning: Tuning, mode: OutputMode, playerPath: String?, startAt: Double,
               partyDeadline: Double = 0, hapticsEnabled: Bool = true, update: @escaping (PlaybackUpdate) -> Void) {
        Self.lastUpdate = update
        Self.runs.append(Run(source: source, mode: mode, haptics: hapticsEnabled, position: startAt))
    }
    func testTrackpad(_ result: @escaping (String?) -> Void) { Self.tests += 1; Self.testCompletion = result }
    func setEffects(followVolume: Bool, keyboard: Bool, partyKeyboard: Bool) {}
    func setPattern(_ pattern: HapticPattern?) { Self.pattern = pattern }
    func set(tuning: Tuning) {}
    func setMacMode(_ mode: OutputMode) {}
    func setHaptics(_ enabled: Bool) {}
    func party(until: Double) {}
    func confirmPlayer(_ bundle: String?) {}
    func stop() {}
    func shutDown(_ completion: @escaping () -> Void) { completion() }
    func probe(_ result: @escaping (String?, String?) -> Void) { Self.probes += 1; result(Self.probeDevice, Self.probeFailure) }
}

// The Console fixture never sends a message or touches the user's clipboard.
enum ProjectShare {
    static let canMessage = false
    static func message() {}
    static func copy() {}
}
