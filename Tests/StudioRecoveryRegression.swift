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
        precondition(!studio.active && studio.audioAccessHealth.requiresRecovery && studio.healthSnapshot.capture == .localFile)
        PlaybackAccess.failure = nil
        _ = await studio.prepareAudioAccess()
        let deadline = Date(timeIntervalSinceNow: 2)
        while !studio.verifyingSetup && Date() < deadline { try? await Task.sleep(nanoseconds: 5_000_000) }
        precondition(studio.verifyingSetup && !studio.requestingAudioAccess && Playback.runs.last?.haptics == false,
            "A successful permission retry must enter non-actuating verification after the check settles.")
        studio.completeFirstSuccess()
        // Each recovery retry stays on the same screen and never substitutes
        // permission success, capture activity or probing for a felt test.
        studio.beginFirstSuccess(); studio.firstSuccessRecovery()
        let testsBeforeRetry = Playback.tests
        await studio.retryCapture()
        await Task.yield()
        precondition(studio.firstSuccess.phase == .recovery && Playback.tests == testsBeforeRetry)
        precondition(Playback.runs.last?.haptics == false && Playback.runs.last?.mode == .assist)
        let activeUpdate = Playback.lastUpdate!
        activeUpdate(PlaybackUpdate(signal: SignalFrame(tones: [], level: 0.2, bands: [], inputRMS: 0.1, hasAudio: true), appBundle: "com.spotify.client", detection: "Music detected"))
        precondition(studio.firstSuccess.audioPresent && !studio.firstSuccess.canConfirm)
        activeUpdate(PlaybackUpdate(detection: "Waiting for Mac audio"))
        precondition(!studio.firstSuccess.audioPresent && studio.firstSuccess.audioDetected && studio.firstSuccess.audioStatus.contains("earlier"))
        studio.retryListening()
        precondition(studio.firstSuccess.phase == .recovery && Playback.runs.last?.haptics == false)
        Playback.probeDevice = nil; Playback.probeFailure = "Private trackpad failure /Users/private"
        studio.probe(force: true)
        precondition(!studio.healthSnapshot.trackpadAvailable && studio.healthSnapshot.error == .trackpad)
        Playback.probeDevice = "Private device name"; Playback.probeFailure = nil
        studio.probe(force: true)
        precondition(studio.healthSnapshot.trackpadAvailable && studio.trackpadFailure == nil)
        studio.completeFirstSuccess()

        // Local-file retries keep position and manual bypass. Capture is not
        // involved even if system recording permission previously failed.
        studio.start(file, from: 51); studio.localBypass = true
        PlaybackAccess.failure = "Denied private recording /Users/private/song.m4a"
        _ = await studio.prepareAudioAccess()
        let requests = PlaybackAccess.requests
        await studio.retryCapture()
        precondition(PlaybackAccess.requests == requests && studio.healthSnapshot.capture == .localFile)
        studio.retryListening()
        precondition(Playback.runs.last?.position == 51 && Playback.runs.last?.haptics == false && studio.localBypass)
        precondition(studio.retrySourceTitle == "Retry local file")
        studio.error = "Private title /Users/private/song.m4a"
        studio.metadata = TrackInfo(title: "Private title", artist: "Private artist")
        let report = studio.diagnosticsReport
        for secret in ["/Users", "Private title", "Private artist", "Private device", "song.m4a", "Denied private"] { precondition(!report.contains(secret)) }
        precondition(report.contains("Selected app: Local file") && report.contains("Output route: Built-in audio"))
        studio.stop()

        // An explicit live retry that waits for permission must retain the
        // listener's haptics-off choice when that permission finally succeeds.
        studio.source = .macAudio; studio.localBypass = true
        studio.retryListening()
        PlaybackAccess.failure = nil
        await studio.retryCapture()
        precondition(studio.active && studio.localBypass && Playback.runs.last?.haptics == false)
        studio.stop()

        // Permission may finish after the window closes. Save its result, but
        // do not reopen verification or start a new audio/haptic session.
        PlaybackAccess.failure = nil
        studio.source = .macAudio; studio.markFirstSuccessPending()
        PlaybackAccess.holdRequests = true
        let runsBeforeClose = Playback.runs.count
        let permission = Task { await studio.prepareAudioAccess() }
        while PlaybackAccess.requestContinuation == nil { await Task.yield() }
        studio.finishPlaybackAccess()
        let completion = PlaybackAccess.requestContinuation!
        PlaybackAccess.requestContinuation = nil; PlaybackAccess.holdRequests = false
        completion.resume()
        _ = await permission.value
        await Task.yield()
        precondition(!studio.verifyingSetup && !studio.active && Playback.runs.count == runsBeforeClose)
        precondition(studio.audioAccessHealth.status == .checked)
        print("Real Studio restores paused/playing file context, keeps preview non-actuating, rejects stopped/closed test callbacks, and persists explicit confirmation.")
        print("Recovery retries stay in place without actuation, retain file position/bypass, clear probe failures, report current audio honestly, and exclude private data from real controller diagnostics; closed permission requests cannot reopen setup.")
    }
}
