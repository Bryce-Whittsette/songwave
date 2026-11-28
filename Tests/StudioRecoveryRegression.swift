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

        // Recovery entered directly from permission/setup must save context
        // before its first non-actuating retry replaces the selected source.
        studio.start(file, from: 49); studio.localBypass = true
        studio.firstSuccessRecovery(); studio.retryListening()
        precondition(studio.firstSuccess.phase == .recovery && Playback.runs.last?.haptics == false)
        studio.completeFirstSuccess()
        precondition(studio.source == file && Playback.runs.last?.position == 49 && studio.localBypass)
        studio.stop()

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
        studio.stop(); studio.probe(force: true)
        precondition(studio.error == "Private title /Users/private/song.m4a", "Trackpad retry must not clear an unrelated playback error.")
        let report = studio.diagnosticsReport
        for secret in ["/Users", "Private title", "Private artist", "Private device", "song.m4a", "Denied private"] { precondition(!report.contains(secret)) }
        precondition(report.contains("Selected app: Local file") && report.contains("Output route: Built-in audio") && report.contains("Error state: playback"))
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
        let dismissal = Studio()
        dismissal.start(file, initialBypass: true)
        dismissal.beginFirstSuccess()
        dismissal.finishPlaybackAccess()
        precondition(dismissal.localBypass && !dismissal.active, "Closing setup must retain the previous haptics-off selection without resuming.")
        dismissal.completeFirstSuccess()
        dismissal.retryListening()
        precondition(dismissal.localBypass && Playback.runs.last?.haptics == false)
        dismissal.stop()
        let genericFailure = Studio()
        genericFailure.start(.macAudio)
        Playback.lastUpdate?(PlaybackUpdate(error: "Mock motor failure"))
        precondition(genericFailure.healthSnapshot.error == .playback && genericFailure.healthSnapshot.capture != .failed,
            "A generic playback or motor error is not proof that capture permission failed.")
        genericFailure.stop()
        TrackCatalog.playingResult = PlayerTrack(id: "spotify:track:verified", info: TrackInfo(title: "Fixture music"), duration: 180, position: 30, observed: 0)
        let dictation = Studio()
        dictation.start(.macAudio)
        let musicUpdate = Playback.lastUpdate!
        musicUpdate(PlaybackUpdate(appBundle: "com.spotify.client", detection: "Music detected"))
        let confirmationDeadline = Date(timeIntervalSinceNow: 2)
        while Playback.confirmedBundle != "com.spotify.client" && Date() < confirmationDeadline { await Task.yield() }
        precondition(Playback.confirmedBundle == "com.spotify.client")
        TrackCatalog.playingResult = nil
        musicUpdate(PlaybackUpdate(detection: "Speech · haptics paused", dictationActive: true))
        precondition(dictation.detectedApp == "com.spotify.client" && Playback.confirmedBundle == "com.spotify.client",
            "Dictation's temporary source gap must not revoke verified player confirmation.")
        musicUpdate(PlaybackUpdate(detection: "Paused for call audio", dictationActive: true))
        precondition(dictation.healthSnapshot.pause == .call, "Dictation must never override an actual call pause.")
        musicUpdate(PlaybackUpdate(detection: "Listening for music"))
        precondition(dictation.detectedApp == nil && Playback.confirmedBundle == nil,
            "Source retention must end when Dictation is no longer active.")
        dictation.stop()
        let stalled = Studio()
        stalled.start(.macAudio)
        Playback.lastUpdate?(PlaybackUpdate(detection: "Audio capture unavailable · open Listening help", captureFailed: true))
        precondition(stalled.healthSnapshot.capture == .failed && stalled.healthSnapshot.error == .capture,
            "A typed capture failure must reach recovery without relying on a permission-message string.")
        stalled.stop()
        let interrupted = Studio()
        interrupted.start(.macAudio)
        Playback.lastUpdate?(PlaybackUpdate(waiting: true, detection: "Waiting for Mac audio"))
        precondition(interrupted.captureHealth == .waiting && !interrupted.captureHelp,
            "Ordinary startup waiting must not invent a lost capture episode.")
        Playback.lastUpdate?(PlaybackUpdate(waiting: true, detection: "Audio signal interrupted · check recording access", captureInterrupted: true))
        precondition(interrupted.captureHealth == .interrupted && interrupted.captureHelp && interrupted.error == nil)
        precondition(interrupted.healthSnapshot.pause == .waiting && interrupted.healthSnapshot.error == .none &&
            !interrupted.audioAccessHealth.requiresRecovery,
            "An uncertain signal interruption must not turn into authoritative permission denial.")
        Playback.lastUpdate?(PlaybackUpdate(signal: SignalFrame(tones: [], level: 0.2, bands: [], inputRMS: 0.1, hasAudio: true), detection: "Music detected"))
        precondition(interrupted.captureHealth == .receiving && !interrupted.captureHelp,
            "Fresh audio must clear interrupted capture guidance without another access prompt.")
        Playback.lastUpdate?(PlaybackUpdate(detection: "Paused for call audio", captureInterrupted: true))
        precondition(interrupted.healthSnapshot.pause == .call, "Call protection must retain priority over signal-loss guidance.")
        interrupted.stop()
        let sleeping = Studio()
        sleeping.start(.macAudio, initialBypass: true)
        sleeping.suspendForSleep()
        sleeping.suspendForSleep() // duplicate sleep notifications must retain resume intent
        precondition(!sleeping.active && sleeping.localBypass)
        sleeping.resumeAfterWake()
        precondition(sleeping.active && sleeping.localBypass && Playback.runs.last?.haptics == false,
            "Waking must preserve Haptics off instead of unexpectedly actuating.")
        sleeping.suspendForSleep()
        sleeping.stop()
        sleeping.resumeAfterWake()
        precondition(!sleeping.active, "Stop must cancel a pending wake reconnection.")
        sleeping.stop()
        // Exercise the real NSWorkspace notification binding as well as the
        // controller methods above. Posting here affects this test process only;
        // it does not sleep the Mac or synthesize a hardware wake.
        let menu = MenuController()
        let workspace = NSWorkspace.shared.notificationCenter
        let notified = Studio()
        menu.attach(to: notified, show: false, openWindow: {})
        menu.attach(to: notified, show: false, openWindow: {})
        notified.start(.macAudio, initialBypass: true)
        let beforeSleep = Playback.lastUpdate!
        workspace.post(name: NSWorkspace.willSleepNotification, object: nil)
        workspace.post(name: NSWorkspace.willSleepNotification, object: nil)
        precondition(!notified.active && notified.localBypass)
        let runsBeforeWake = Playback.runs.count
        workspace.post(name: NSWorkspace.didWakeNotification, object: nil)
        precondition(notified.active && notified.localBypass && Playback.runs.last?.haptics == false)
        precondition(Playback.runs.count == runsBeforeWake + 1, "Reattaching the menu controller duplicated wake handling")
        beforeSleep(PlaybackUpdate(captureFailed: true, error: "A stale pre-sleep capture result"))
        precondition(notified.active && notified.error == nil && notified.healthSnapshot.capture != .failed,
                     "A pre-sleep callback changed the resumed session")
        workspace.post(name: NSWorkspace.willSleepNotification, object: nil)
        notified.stop()
        workspace.post(name: NSWorkspace.didWakeNotification, object: nil)
        precondition(!notified.active, "Explicit Stop must cancel notification-driven resume")
        notified.start(file, from: 29, initialBypass: true)
        workspace.post(name: NSWorkspace.willSleepNotification, object: nil)
        workspace.post(name: NSWorkspace.didWakeNotification, object: nil)
        precondition(!notified.active && notified.source == file && notified.elapsed == 29 && notified.localBypass,
                     "Sleep must preserve local-file position without starting a live source on wake")
        notified.start(.macAudio)
        workspace.post(name: NSWorkspace.willSleepNotification, object: nil)
        PlaybackAccess.failure = "Injected access-check failure"
        _ = await notified.prepareAudioAccess()
        workspace.post(name: NSWorkspace.didWakeNotification, object: nil)
        precondition(!notified.active && notified.audioAccessHealth.requiresRecovery,
                     "Wake must not restart capture after a failed access recheck")
        PlaybackAccess.failure = nil
        notified.stop()
        print("Real Studio restores paused/playing file context, keeps preview non-actuating, rejects stopped/closed test callbacks, and persists explicit confirmation.")
        print("Recovery retries stay in place without actuation, retain file position/bypass, clear probe failures, report current audio honestly, and exclude private data from real controller diagnostics; closed permission requests cannot reopen setup.")
        print("Real menu/NSWorkspace sleep-wake bindings preserve bypass/file position, ignore stale results, avoid duplicate resumes and honor Stop/access failures; notifications are injected, not physical sleep.")
    }
}
