import Foundation

@main struct ListeningHealthRegression {
    static func main() {
        var check = FirstSuccessCheck()
        precondition(!check.confirm(), "Opening setup must not imply sensation.")
        check.begin(); check.observeAudio(true)
        precondition(check.audioDetected && !check.confirm(), "Audio detection is not tactile confirmation.")
        let token = check.beginTest()!
        precondition(check.beginTest() == nil && !check.confirm())
        check.cancel(); check.finishTest(token, succeeded: true)
        precondition(check.phase == .idle, "Late callbacks must not revive a dismissed test.")
        check.begin()
        let failed = check.beginTest()!
        check.finishTest(failed, succeeded: false)
        precondition(check.phase == .recovery && !check.canConfirm)
        let retry = check.beginTest()!
        check.finishTest(failed, succeeded: true)
        precondition(check.testing)
        check.finishTest(retry, succeeded: true)
        precondition(check.canConfirm && check.confirm())
        check.recover(); precondition(!check.confirm())
        let stoppedTest = check.beginTest()!
        check.recover()
        check.finishTest(stoppedTest, succeeded: true)
        precondition(check.phase == .recovery && !check.canConfirm, "Stop/recovery must invalidate a running test callback.")

        for cadence in [0.008, 0.02, 0.035] {
            var schedule = TrackpadCheckSequence(), pulses = 0
            for i in 0...100 { if schedule.pulse(at: Double(i) * cadence) { pulses += 1 } }
            precondition(pulses == 3)
        }
        var late = TrackpadCheckSequence()
        precondition(!late.pulse(at: .nan) && !late.pulse(at: -1) && !late.pulse(at: 1), "Stalls must skip missed pulses.")
        precondition(!late.pulse(at: 1.01))
        for (message, expected) in [("Paused for call audio", ListeningPause.call), ("Speech · haptics paused", .speech), ("YouTube video · haptics paused", .video)] {
            precondition(ListeningHealthSnapshot.pause(active: true, bypassed: false, verifying: false, failure: false, detection: message) == expected)
        }
        precondition(ListeningHealthSnapshot.pause(active: true, bypassed: false, verifying: true, failure: false, detection: "Music detected") == .check)
        let health = ListeningHealthSnapshot(trackpadAvailable: true, capture: .receiving, app: .spotify, pause: .none, error: .none)
        let secret = "/Users/Bryce/Private Song.m4a\nSong: Secret"
        let invalid = SafeDiagnostics(version: secret, build: "$(password)", model: secret, os: .init(majorVersion: 27, minorVersion: 3, patchVersion: 0), route: .bluetooth, health: health).text
        for text in ["Bryce", "Private Song", "/Users", "password", "Secret"] { precondition(!invalid.contains(text)) }
        precondition(invalid.contains("App: unknown (unknown)") && invalid.contains("Bluetooth") && invalid.contains("Spotify"))
        let hostile = SafeDiagnostics(version: "0.5.9", build: "19", model: "Mac16,12\n", os: .init(majorVersion: 27, minorVersion: 3, patchVersion: 0), route: .unknown, health: health).text
        precondition(hostile.contains("Unknown Mac"))
        for model in ["Mac16,12", "MacBookPro18,1", "MacBookAir10,1", "iMac21,1"] {
            let report = SafeDiagnostics(version: "0.5.9", build: "19", model: model, os: .init(majorVersion: 27, minorVersion: 3, patchVersion: 0), route: .builtIn, health: health).text
            precondition(report.contains("Mac: " + model))
        }
        precondition(ListeningHealthSnapshot.app(bundle: "private.company.song-title", localFile: false) == .other)
        print("Explicit sensation confirmation, stale/cancelled tests, retries, bounded tap schedules, pause reasons, and adversarial diagnostics privacy passed.")
    }
}
