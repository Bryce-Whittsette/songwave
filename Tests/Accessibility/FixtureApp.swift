import AppKit
import SwiftUI

@main struct AccessibilityFixture: App {
    @StateObject private var studio: Studio
    @State private var configured = false
    private let screen: String
    private let reduceMotion: Bool
    private let scheme: ColorScheme
    private let compact: Bool
    init() {
        let env = ProcessInfo.processInfo.environment
        compact = env["SONGWAVE_AX_COMPACT"] == "1"
        screen = env["SONGWAVE_AX_SCREEN"] ?? "confirmation"
        reduceMotion = env["SONGWAVE_AX_REDUCE_MOTION"] == "1"
        scheme = env["SONGWAVE_AX_SCHEME"] == "light" ? .light : .dark
        UserDefaults.standard.setVolatileDomain(["setupComplete": screen == "player", "launchListen": false,
            "audioAccessConfigured": screen != "permission", "firstSuccessPending": false], forName: UserDefaults.argumentDomain)
        _studio = StateObject(wrappedValue: Studio())
    }
    var body: some Scene {
        WindowGroup("SongWave accessibility fixture") {
            Group {
                if screen == "player" { Console(studio: studio).frame(minWidth: compact ? 810 : 1000, minHeight: compact ? 640 : 760) }
                else { PlaybackAccessSheet(studio: studio) }
            }
                .environment(\.songWaveAdditionalMotionReduction, reduceMotion)
                .preferredColorScheme(scheme)
                .tint(scheme == .dark ? .white : .black)
                .task {
                    guard !configured else { return }
                    configured = true
                    studio.probe()
                    if screen == "player" {
                        if compact {
                            // Exercise the real minimum content size regardless
                            // of SwiftUI's previous window restoration record.
                            NSApp.windows.first { $0.title == "SongWave accessibility fixture" }?
                                .setContentSize(NSSize(width: 810, height: 640))
                        }
                        return
                    }
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
        .defaultSize(width: 600, height: compact ? 450 : 800)
        .commands {
            CommandMenu("Test fixture") {
                Button("Complete simulated trackpad test") { Playback.testCompletion?(nil) }
                    .keyboardShortcut("t", modifiers: [.command, .shift])
                Button("Simulate music with haptics off") {
                    studio.start(.macAudio, initialBypass: true)
                    Playback.lastUpdate?(PlaybackUpdate(signal: SignalFrame(tones: [], level: 0.4,
                        bands: Array(repeating: 0.4, count: 44), inputRMS: 0.05, hasAudio: true,
                        beatStrength: 0.8), device: "Mock trackpad", detection: "Music detected"))
                }.keyboardShortcut("m", modifiers: [.command, .shift])
                Button("Simulate silence") {
                    Playback.lastUpdate?(PlaybackUpdate(device: "Mock trackpad", waiting: true, detection: "Waiting for Mac audio"))
                }.keyboardShortcut("s", modifiers: [.command, .shift])
            }
        }
    }
}
