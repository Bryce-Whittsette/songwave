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
    static func requestAudio() async throws { if let failure { throw GlassError(failure) } }
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
    static var testCompletion: ((String?) -> Void)?
    func start(_ source: PlaybackSource, tuning: Tuning, mode: OutputMode, playerPath: String?, startAt: Double,
               partyDeadline: Double = 0, hapticsEnabled: Bool = true, update: @escaping (PlaybackUpdate) -> Void) {
        Self.runs.append(Run(source: source, mode: mode, haptics: hapticsEnabled, position: startAt))
    }
    func testTrackpad(_ result: @escaping (String?) -> Void) { Self.testCompletion = result }
    func setEffects(followVolume: Bool, keyboard: Bool, partyKeyboard: Bool) {}
    func setPattern(_ pattern: HapticPattern?) { Self.pattern = pattern }
    func set(tuning: Tuning) {}
    func setMacMode(_ mode: OutputMode) {}
    func setHaptics(_ enabled: Bool) {}
    func party(until: Double) {}
    func confirmPlayer(_ bundle: String?) {}
    func stop() {}
    func shutDown(_ completion: @escaping () -> Void) { completion() }
    func probe(_ result: @escaping (String?, String?) -> Void) { result("Mock trackpad", nil) }
}

@main struct StudioRecoveryRegression {
    @MainActor static func main() async {
        let defaults = UserDefaults.standard
        let domain = ProcessInfo.processInfo.processName
        defaults.setVolatileDomain(["setupComplete": false, "launchListen": false, "audioAccessConfigured": true,
            "firstSuccessPending": false], forName: UserDefaults.argumentDomain)
        defer { defaults.removePersistentDomain(forName: domain) }
        let studio = Studio()
        let file = PlaybackSource.file(URL(fileURLWithPath: "/tmp/songwave-private-fixture.m4a"))
        studio.source = file; studio.elapsed = 42; studio.duration = 180
        let patternURL = FileManager.default.temporaryDirectory.appendingPathComponent("SongWaveRecovery-" + UUID().uuidString + ".ahap")
        try! Data(#"{"Version":1,"Pattern":[{"Event":{"Time":0,"EventType":"HapticTransient"}}]}"#.utf8).write(to: patternURL)
        defer { try? FileManager.default.removeItem(at: patternURL) }
        await studio.attachPattern(patternURL)
        let patternName = studio.patternName
        precondition(patternName != nil && Playback.pattern != nil)
        studio.metadata = TrackInfo(title: "Private title", artist: "Private artist")
        studio.beginFirstSuccess()
        precondition(studio.verifyingSetup && Playback.runs.last?.mode == .assist && Playback.runs.last?.haptics == false)
        precondition(!studio.assistEnabled, "The menu bar must not report haptics on during verification.")
        studio.testTrackpad()
        let first = Playback.testCompletion!
        studio.stop()
        first(nil)
        precondition(!studio.testingTrackpad && studio.firstSuccess.phase == .recovery,
            "External Stop must invalidate the test, not strand the confirmation UI.")
        studio.completeFirstSuccess()
        precondition(studio.source == file && studio.elapsed == 42 && studio.duration == 180 && studio.metadata?.title == "Private title")
        precondition(studio.selectedAppLabel == "Local audio file")
        precondition(!studio.active && !studio.firstSuccessPending && studio.patternName == patternName && Playback.pattern != nil)
        studio.beginFirstSuccess(); studio.testTrackpad()
        let closed = Playback.testCompletion!
        studio.finishPlaybackAccess()
        closed(nil)
        precondition(studio.source == file && !studio.testingTrackpad && !studio.verifyingSetup)
        studio.beginFirstSuccess(); studio.testTrackpad()
        Playback.testCompletion?(nil)
        precondition(studio.firstSuccess.canConfirm)
        studio.confirmFirstSuccess()
        precondition(studio.source == file && !studio.active && !studio.firstSuccessPending)
        precondition(defaults.bool(forKey: "firstSuccessConfirmed"))
        studio.start(file, from: 37)
        studio.localBypass = true
        studio.beginFirstSuccess(); studio.completeFirstSuccess()
        precondition(studio.source == file && studio.active && Playback.runs.last?.source == file && Playback.runs.last?.position == 37)
        precondition(studio.localBypass && Playback.runs.last?.haptics == false,
            "Restoration must start bypassed, without a brief enabled output packet.")
        studio.stop()
        let other = PlaybackSource.file(URL(fileURLWithPath: "/tmp/songwave-other-fixture.m4a"))
        studio.start(other)
        await studio.attachPattern(patternURL, expectedSource: file)
        precondition(studio.patternName == nil && Playback.pattern == nil,
            "A deferred pattern selection must not attach to a different source.")
        studio.stop()
        studio.markFirstSuccessPending()
        PlaybackAccess.failure = "Denied /Users/private"
        _ = await studio.prepareAudioAccess()
        studio.finishPlaybackAccess()
        precondition(!studio.active && studio.audioAccessHealth.requiresRecovery && studio.healthSnapshot.capture == .failed)
        PlaybackAccess.failure = nil
        _ = await studio.prepareAudioAccess()
        let deadline = Date(timeIntervalSinceNow: 2)
        while !studio.verifyingSetup && Date() < deadline { try? await Task.sleep(nanoseconds: 5_000_000) }
        precondition(studio.verifyingSetup && !studio.requestingAudioAccess && Playback.runs.last?.haptics == false,
            "A successful permission retry must enter non-actuating verification after the check settles.")
        studio.completeFirstSuccess()
        print("Real Studio restores paused/playing file context, keeps preview non-actuating, rejects stopped/closed test callbacks, and persists explicit confirmation.")
    }
}
