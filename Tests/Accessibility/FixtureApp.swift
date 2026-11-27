import AppKit
import SwiftUI

@main struct AccessibilityFixture: App {
    @StateObject private var studio: Studio
    @State private var configured = false
    private let screen: String
    private let reduceMotion: Bool
    private let scheme: ColorScheme
    init() {
        let env = ProcessInfo.processInfo.environment
        screen = env["SONGWAVE_AX_SCREEN"] ?? "confirmation"
        reduceMotion = env["SONGWAVE_AX_REDUCE_MOTION"] == "1"
        scheme = env["SONGWAVE_AX_SCHEME"] == "light" ? .light : .dark
        UserDefaults.standard.setVolatileDomain(["setupComplete": false, "launchListen": false,
            "audioAccessConfigured": screen != "permission", "firstSuccessPending": false], forName: UserDefaults.argumentDomain)
        _studio = StateObject(wrappedValue: Studio())
    }
    var body: some Scene {
        WindowGroup("SongWave accessibility fixture") {
            PlaybackAccessSheet(studio: studio)
                .environment(\.songWaveAdditionalMotionReduction, reduceMotion)
                .preferredColorScheme(scheme)
                .tint(scheme == .dark ? .white : .black)
                .task {
                    guard !configured else { return }
                    configured = true
                    studio.probe()
                    if screen == "permission" { studio.markFirstSuccessPending() }
                    else {
                        studio.beginFirstSuccess()
                        let frame = SignalFrame(tones: [], level: 0.4, bands: Array(repeating: 0.4, count: 44), inputRMS: 0.05, hasAudio: true, beatStrength: 0.8)
                        Playback.lastUpdate?(PlaybackUpdate(signal: frame, device: "Mock trackpad", detection: "Music detected"))
                        if screen == "confirmation" || screen == "testing" {
                            studio.testTrackpad()
                            if screen == "confirmation" { Playback.testCompletion?(nil) }
                        }
                        if screen == "recovery" { studio.firstSuccessRecovery() }
                        Playback.lastUpdate?(PlaybackUpdate(signal: frame, device: "Mock trackpad", detection: "Music detected"))
                        studio.display.submit(SignalFrame(tones: [], level: 0.4,
                            bands: Array(repeating: 0.4, count: 44), inputRMS: 0.05, hasAudio: true, beatStrength: 0.8))
                    }
                }
        }
    }
}
