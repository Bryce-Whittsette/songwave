import AppKit
import Foundation

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
