import AppKit
import SwiftUI

struct SongWaveSettings: View {
    @ObservedObject var studio: Studio
    @EnvironmentObject private var preferences: AppPreferences
    @EnvironmentObject private var updates: AppUpdates
    @Environment(\.openWindow) private var openWindow
    @Environment(\.colorScheme) private var colorScheme
    @State private var selection: Page = .general
    @State private var playerRequest: Provider?
    @State private var filterMessage: String?
    @State private var copiedLink = false

    private enum Page: String, CaseIterable, Identifiable {
        case general = "General"
        case playback = "Listening Help"
        case effects = "Effects"
        case updates = "Updates"
        case help = "Help"

        var id: Self { self }
        var icon: String {
            switch self {
            case .general: return "gearshape"
            case .playback: return "speaker.wave.2"
            case .effects: return "waveform"
            case .updates: return "arrow.down.circle"
            case .help: return "questionmark.circle"
            }
        }
        var detail: String {
            switch self {
            case .general: return "Appearance, launch behavior and listening preferences."
            case .playback: return "Connection status, setup check and privacy-safe diagnostics."
            case .effects: return "Volume following, keyboard light and music filtering."
            case .updates: return "Check for new versions and choose how to hear about them."
            case .help: return "Guides, support and the SongWave project."
            }
        }
    }

    var body: some View {
        TabView(selection: $selection) {
            ForEach(Page.allCases) { page in
                Form {
                    sections(for: page)
                }
                .formStyle(.grouped)
                .tabItem { Label(page.rawValue, systemImage: page.icon) }
                .tag(page)
            }
        }
        .font(.system(size: 14))
        .tint(colorScheme == .dark ? Color.white : Color.black)
        .frame(minWidth: 740, minHeight: 560)
        .onAppear { applyRequestedPage() }
        .onChange(of: studio.requestedSettingsPage) { _, _ in applyRequestedPage() }
    }

    private func applyRequestedPage() {
        if let name = studio.requestedSettingsPage, let page = Page(rawValue: name) {
            selection = page; studio.requestedSettingsPage = nil
        }
    }

    @ViewBuilder private func sections(for page: Page) -> some View {
        switch page {
        case .general: general
        case .playback: playback
        case .effects: effects
        case .updates: updateSettings
        case .help: help
        }
    }

    @ViewBuilder private var general: some View {
        Section("Appearance") {
            Picker("Appearance", selection: $preferences.appearance) {
                ForEach(Appearance.allCases) { Text($0.rawValue).tag($0) }
            }.pickerStyle(.segmented)
        }
        Section("Everyday behavior") {
            Toggle("Show SongWave in menu bar", isOn: $preferences.showMenuControl)
            Toggle("Listen when SongWave opens", isOn: $studio.launchListen)
            Text("Closing the player window keeps SongWave running. Use SongWave → Quit SongWave to exit.")
                .foregroundStyle(.secondary)
        }
        Section("Listening preferences") {
            Picker("Usual genre", selection: Binding(get: { studio.genre }, set: studio.setGenre)) {
                ForEach(ListeningGenre.allCases) { Text($0.rawValue).tag($0) }
            }
            Picker("What should stand out?", selection: Binding(get: { studio.focus }, set: { focus in
                studio.finishSetup(auto: studio.launchListen, genre: studio.genre,
                                   focus: focus, gain: studio.tuning.gain)
            })) {
                ForEach(ListeningFocus.allCases) { Text($0.rawValue).tag($0) }
            }
            Text("Changing these choices reapplies the starting EQ in both output modes. You can adjust each band in the player afterward.")
                .foregroundStyle(.secondary)
            Button("Open Player", action: openPlayer)
        }
    }

    @ViewBuilder private var playback: some View {
        Section {
            PlaybackAccessContent(studio: studio, playerRequest: $playerRequest)
        }
        Section("Guide") {
            Button("Open Player", action: openPlayer)
            Link("Troubleshooting", destination: projectURL("docs/troubleshooting.md"))
        }
    }

    @ViewBuilder private var effects: some View {
        Section("Music response") {
            Toggle("Follow Mac volume", isOn: $studio.followVolume)
            Text("Adjusts haptic strength with the selected audio output’s volume in Speakers + haptics. Trackpad only always uses your manual intensity. Fixed-level outputs also keep manual intensity.")
                .foregroundStyle(.secondary)
            Toggle("Sync keyboard light", isOn: $studio.keyboard)
            Text("Pulses a supported MacBook’s white backlight with detected beats. The previous brightness is restored when the effect stops. Ambient light can affect visibility.")
                .foregroundStyle(.secondary)
        }
        Section("Insane Ultra") {
            UltraNotice()
            Text("Start or stop Ultra from the player. It follows your current music or local file and stays quiet when nothing is playing.")
            Button("Open Player", action: openPlayer)
        }
        Section("YouTube music filter · Optional") {
            Text("The browser filter reads the playing video’s category so talking videos and ads can pause haptics. Audio-only recognition can mistake an instrumental video intro for music.")
            Text("Chrome: open chrome://extensions, turn on Developer mode, then choose Load unpacked and select the Chrome folder revealed in Finder.")
            Text("Firefox: open about:debugging → This Firefox → Load Temporary Add-on and select manifest.json from the Firefox folder. Repeat after restarting Firefox.")
            Text("Keep SongWave in Applications so the browser can find it. Safari uses audio recognition.")
                .foregroundStyle(.secondary)
            HStack {
                Button("Set Up Chrome…") { setUpFilter("Chrome") }
                Button("Set Up Firefox…") { setUpFilter("Firefox") }
            }
            if let filterMessage {
                Text(filterMessage).fixedSize(horizontal: false, vertical: true)
            }
        }
    }

    @ViewBuilder private var updateSettings: some View {
        Section("Current version") {
            LabeledContent("SongWave", value: version)
            Button("Check for Updates…", action: updates.check).disabled(!updates.canCheck)
        }
        Section("Automatic checks") {
            Toggle("Check for updates automatically", isOn: Binding(
                get: { updates.checksAutomatically }, set: updates.setAutomaticChecks))
            Text("Checks roughly once a day. SongWave asks before downloading and installing an update, so you choose when to update.")
            Text("Update checks contact GitHub. Audio, song titles and listening history are not sent.")
                .foregroundStyle(.secondary)
            DisclosureGroup("How updates work") {
                Text("SongWave verifies signed release information and the downloaded app before installation. Your approval starts the update; background checks do not install it for you. You can also install a new version from the project’s DMG.")
                    .fixedSize(horizontal: false, vertical: true)
            }
        }
    }

    @ViewBuilder private var help: some View {
        Section("SongWave") {
            LabeledContent("Version", value: version)
            LabeledContent("Trackpad", value: studio.device ?? "Not checked yet")
            Text("Feel music playing on your Mac through its Force Touch trackpad. A song link or local file is optional.")
        }
        Section("Guides and support") {
            Link("User guide", destination: projectURL("docs/guide.md"))
            Link("Troubleshooting", destination: projectURL("docs/troubleshooting.md"))
            Link("Report a problem", destination: URL(string: "https://github.com/Bryce-Whittsette/songwave/issues/new/choose")!)
            Button("Listening Help") { selection = .playback }
        }
        Section("Share SongWave") {
            Link("SongWave on GitHub", destination: ProjectShare.url)
            Button("Share via Messages…", action: ProjectShare.message)
                .disabled(!ProjectShare.canMessage)
            Button("Copy SongWave Link") { ProjectShare.copy(); copiedLink = true }
            if copiedLink { Text("SongWave link copied.").foregroundStyle(.secondary) }
        }
        Section("Open source") {
            Link("Version history", destination: projectURL("CHANGELOG.md"))
            Link("MIT license", destination: projectURL("LICENSE"))
            Link("Third-party notices", destination: projectURL("docs/credits.md"))
        }
    }

    private var version: String {
        let info = Bundle.main.infoDictionary ?? [:]
        let version = info["CFBundleShortVersionString"] as? String ?? "Development build"
        if let build = info["CFBundleVersion"] as? String { return "\(version) (\(build))" }
        return version
    }

    private func projectURL(_ path: String) -> URL {
        URL(string: "https://github.com/Bryce-Whittsette/songwave/blob/main/" + path)!
    }

    private func openPlayer() {
        openWindow(id: "studio")
        NSApp.activate(ignoringOtherApps: true)
    }

    private func setUpFilter(_ browser: String) {
        do {
            try YouTubeState.setUp(browser)
            filterMessage = "Browser connection saved. Finish the steps above using the folder opened in Finder."
        } catch { filterMessage = error.localizedDescription }
    }
}
