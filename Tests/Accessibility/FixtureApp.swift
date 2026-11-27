import AppKit
import SwiftUI

@main struct AccessibilityFixture: App {
    @StateObject private var studio: Studio
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
        .commands {
            CommandMenu("Test fixture") {
                Button("Export native accessibility tree", action: NativeAXFixtureReport.write)
                    .keyboardShortcut("j", modifiers: [.command, .shift])
            }
        }
    }
}

// Only this test app exports its own tree. No system-wide AX access, VoiceOver
// preference changes or inspection of the user's other applications is used.
@MainActor enum NativeAXFixtureReport {
    static func write() {
        guard let path = ProcessInfo.processInfo.environment["SONGWAVE_AX_REPORT"] else { return }
        var nodes: [[String: String]] = []
        var seen = Set<ObjectIdentifier>()
        func walk(_ object: Any, depth: Int) {
            guard depth < 40, let e = object as? NSAccessibilityProtocol else { return }
            let identity = ObjectIdentifier(e as AnyObject)
            guard seen.insert(identity).inserted else { return }
            nodes.append(["id": e.accessibilityIdentifier() ?? "", "role": e.accessibilityRole()?.rawValue ?? "",
                          "subrole": e.accessibilitySubrole()?.rawValue ?? "", "description": e.accessibilityRoleDescription() ?? "",
                          "label": e.accessibilityLabel() ?? ""])
            let ordered = e.accessibilityChildrenInNavigationOrder() ?? []
            for child in ordered.isEmpty ? e.accessibilityChildren() ?? [] : ordered { walk(child, depth: depth + 1) }
        }
        for window in NSApp.windows { if let content = window.contentView { walk(content, depth: 0) } }
        if let data = try? JSONSerialization.data(withJSONObject: nodes, options: [.sortedKeys]) { try? data.write(to: URL(fileURLWithPath: path), options: .atomic) }
    }
}
