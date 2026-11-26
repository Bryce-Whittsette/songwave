import AppKit
import SwiftUI

enum Appearance: String, CaseIterable, Identifiable {
    case system = "System"
    case light = "Light"
    case dark = "Dark"

    var id: Self { self }
    var scheme: ColorScheme? {
        switch self {
        case .system: return nil
        case .light: return .light
        case .dark: return .dark
        }
    }
}

@main
struct SongWaveApp: App {
    @NSApplicationDelegateAdaptor(MenuController.self) private var menuController
    @StateObject private var studio = Studio()
    @StateObject private var updates = AppUpdates()
    @StateObject private var preferences = AppPreferences()
    @Environment(\.openWindow) private var openWindow

    var body: some Scene {
        Window("SongWave", id: "studio") {
            Console(studio: studio)
                .environmentObject(updates)
                .environmentObject(preferences)
                .frame(minWidth: 810, minHeight: 640)
                .preferredColorScheme(preferences.appearance.scheme)
                .onAppear {
                    studio.probe()
                    menuController.attach(to: studio, show: preferences.showMenuControl) { openWindow(id: "studio") }
                    preferences.bindMenuController(menuController)
                }
        }
        .defaultSize(width: 1100, height: 880)
        .windowResizability(.contentMinSize)
        .commands {
            CommandGroup(after: .appInfo) {
                Button("Check for Updates…", action: updates.check).disabled(!updates.canCheck)
            }
            CommandGroup(replacing: .newItem) {
                Button("Open Audio File…", action: studio.chooseAudio).keyboardShortcut("o")
            }
            CommandGroup(after: .toolbar) {
                Toggle("Show SongWave in Menu Bar", isOn: $preferences.showMenuControl)
            }
            CommandMenu("Playback") {
                Button("Toggle Speakers + Haptics", action: studio.toggleAssist)
                Button("Play Demo", action: studio.playDemo).keyboardShortcut("d")
                Button("Stop Trackpad", action: studio.stop).keyboardShortcut(".", modifiers: .command)
            }
        }
        Settings {
            SongWaveSettings(studio: studio)
                .environmentObject(preferences)
                .environmentObject(updates)
                .preferredColorScheme(preferences.appearance.scheme)
                .frame(minWidth: 740, minHeight: 560)
                .onAppear { preferences.bindMenuController(menuController) }
        }
        .defaultSize(width: 800, height: 610)
    }
}

struct Console: View {
    @ObservedObject var studio: Studio
    @Environment(\.accessibilityReduceMotion) private var reduceMotion
    @Environment(\.colorScheme) private var colorScheme
    @State private var showTuning = false
    @State private var showEQDetails = false
    @State private var showSetup = false
    @State private var accessAfterSetup = false
    @State private var showBurst = false
    @State private var burstLights = false
    @State private var burstDemo = false
    @State private var startBurstAfterDismiss = false
    @AppStorage("setupComplete") private var didSetup = false

    var body: some View {
        ScrollView {
            VStack(alignment: .leading, spacing: 24) {
                source
                HStack(alignment: .top, spacing: 20) {
                    VStack(spacing: 16) {
                        track
                        Monitor(display: studio.display, waiting: studio.waiting,
                                status: studio.active && (studio.source == .macAudio || (studio.mode == .trackpad && studio.tuning.vocalQuality == .isolated)) ? studio.detection : nil)
                        transport
                        notice
                    }
                    .frame(maxWidth: .infinity)
                    VStack(spacing: 16) {
                        output
                        equalizer
                    }
                    .frame(width: 348)
                }
            }
            .frame(maxWidth: 1160)
            .padding(.horizontal, 26)
            .padding(.top, 18)
            .padding(.bottom, 24)
            .frame(maxWidth: .infinity)
        }
        .safeAreaInset(edge: .top, spacing: 0) {
            heading
                .frame(maxWidth: 1160)
                .padding(.horizontal, 26).padding(.vertical, 18)
                .frame(maxWidth: .infinity)
                .background(.bar)
        }
        .font(.system(size: 14))
        .background(Color(nsColor: .underPageBackgroundColor))
        .tint(colorScheme == .dark ? Color.white : Color.black)
        .onAppear {
            if didSetup { studio.launchIfConfigured() } else { showSetup = true }
        }
        .sheet(isPresented: $showSetup, onDismiss: {
            if accessAfterSetup { accessAfterSetup = false; studio.showPlaybackAccess = true }
        }) {
            VStack(spacing: 0) {
                ListeningSetup(complete: { auto, genre, focus, gain in
                    accessAfterSetup = !didSetup
                    didSetup = true
                    showSetup = false
                    studio.finishSetup(auto: auto, genre: genre, focus: focus, gain: gain)
                }, genre: studio.genre, focus: studio.focus, intensity: studio.tuning.gain, automatic: studio.launchListen)
                Button(didSetup ? "Cancel" : "Skip setup") {
                    let first = !didSetup
                    didSetup = true
                    showSetup = false
                    if first { accessAfterSetup = true }
                }.buttonStyle(.link).padding(.bottom, 15)
            }.interactiveDismissDisabled(!didSetup)
        }
        .sheet(isPresented: accessPresentation, onDismiss: studio.finishPlaybackAccess) {
            PlaybackAccessSheet(studio: studio)
        }
        .sheet(isPresented: $showBurst, onDismiss: {
            if startBurstAfterDismiss {
                startBurstAfterDismiss = false
                studio.startParty(lights: burstLights, useDemo: burstDemo)
            }
        }) {
            VStack(alignment: .leading, spacing: 14) {
                Text("Insane Ultra").font(.title.bold())
                UltraNotice()
                Toggle("Play the built-in demo", isOn: $burstDemo)
                Toggle("Pulse keyboard backlight", isOn: $burstLights)
                TimelineView(.periodic(from: .now, by: 1)) { _ in
                    HStack {
                        Button("Cancel") { showBurst = false }.keyboardShortcut(.cancelAction)
                        Spacer()
                        Button(studio.cooldown > 0 ? "Available in " + String(Int(ceil(studio.cooldown))) + "s" : (burstDemo ? "Play Ultra Demo" : "Start Ultra")) {
                            startBurstAfterDismiss = true
                            showBurst = false
                        }.disabled(studio.cooldown > 0)
                    }
                }
            }.padding(24).frame(width: 400)
        }
        .sheet(isPresented: $showTuning) { tuningSheet }
        .sheet(isPresented: $showEQDetails) { eqSheet }
    }

    private static let brandMark = Bundle.main.url(forResource: "SongWave", withExtension: "icns")
        .flatMap(NSImage.init(contentsOf:))

    // A recovery request from the menu bar waits for the current sheet to close.
    // Settings embeds access content inline and never becomes a second presenter.
    private var accessPresentation: Binding<Bool> {
        Binding(get: {
            studio.showPlaybackAccess && !showSetup && !showTuning && !showEQDetails && !showBurst
        }, set: { presented in
            if !presented { studio.showPlaybackAccess = false }
        })
    }

    private var heading: some View {
        HStack(alignment: .center, spacing: 11) {
            if let mark = Self.brandMark {
                Image(nsImage: mark).resizable().interpolation(.high)
                    .aspectRatio(contentMode: .fit)
                    .frame(width: 42, height: 42)
                    .accessibilityHidden(true)
            }
            Text("SongWave").font(.system(size: 28, weight: .semibold)).tracking(-0.65)
                .accessibilityAddTraits(.isHeader)
            Spacer()
            Label(studio.device ?? "Trackpad unavailable", systemImage: "trackpad")
                .font(.callout).foregroundStyle(.secondary)
            Menu {
                Button("Share via Messages…", action: ProjectShare.message)
                    .disabled(NSSharingService(named: .composeMessage) == nil)
                Button("Copy Repository Link", action: ProjectShare.copy)
            } label: {
                Label("Share", systemImage: "square.and.arrow.up")
                    .font(.system(size: 14, weight: .medium))
                    .padding(.horizontal, 10).padding(.vertical, 7)
                    .glassSurface(Capsule(), interactive: true)
            }.menuStyle(.borderlessButton).menuIndicator(.hidden).fixedSize()
                .labelStyle(.titleAndIcon)
                .accessibilityLabel("Share SongWave")
            SettingsLink {
                Label("Settings", systemImage: "gearshape")
                    .font(.system(size: 14, weight: .medium))
            }
            .glassControlButton()
            .labelStyle(.titleAndIcon)
            .help("Open SongWave settings (Command-comma)")
            .accessibilityLabel("Settings")
        }
    }

    private var source: some View {
        VStack(alignment: .leading, spacing: 9) {
            HStack {
                Button(action: studio.routeMacAudio) {
                    Label(studio.active && studio.source == .macAudio ? "Stop listening" : "Listen to Mac audio",
                          systemImage: studio.active && studio.source == .macAudio ? "stop.fill" : "speaker.wave.2")
                }
                .primaryGlassAction()
                .help("Automatically follow music from Spotify, Music, browsers, and other apps on this Mac.")
                Spacer()
                Button("Open File…", action: studio.chooseAudio)
                Button("Play Demo", action: studio.playDemo)
            }
            HStack(alignment: .center, spacing: 10) {
                HStack(alignment: .center, spacing: 9) {
                    Image(systemName: "link").foregroundStyle(.secondary).accessibilityHidden(true)
                    TextField("Optional Spotify or Apple Music link", text: $studio.link, axis: .vertical)
                        .textFieldStyle(.plain)
                        .font(.body)
                        .lineLimit(1...3)
                        .accessibilityLabel("Spotify or Apple Music link")
                        .help(studio.link)
                    Button("Paste", action: studio.paste)
                        .buttonStyle(.borderless)
                        .font(.callout)
                }
                .padding(.horizontal, 10).padding(.vertical, 8)
                .frame(minHeight: 35)
                .glassSurface(RoundedRectangle(cornerRadius: 11), interactive: true)
                Button("Open & Route", action: studio.playLink)
                    .primaryGlassAction()
                    .keyboardShortcut(.return, modifiers: [.command])
                    .disabled(studio.link.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty)
            }
        }
    }

    private var liveAppName: String? {
        guard studio.source == .macAudio, let id = studio.detectedApp else { return nil }
        if id.hasPrefix("com.spotify.client") { return "Spotify" }
        if id == "com.apple.Music" { return "Apple Music" }
        if id.contains("WebKit") || id == "com.apple.Safari" { return "Safari" }
        return NSRunningApplication.runningApplications(withBundleIdentifier: id).first?.localizedName
    }

    private var track: some View {
        HStack(spacing: 13) {
            cover
            VStack(alignment: .leading, spacing: 4) {
                Text(studio.metadata?.title ?? liveAppName ?? studio.source?.title ?? "No source loaded")
                    .font(.system(size: 20, weight: .semibold))
                    .lineLimit(2)
                if let artist = studio.metadata?.artist {
                    Text(artist).font(.callout).foregroundStyle(.secondary).lineLimit(1)
                }
                if let source = studio.source {
                    Text(source.detail).font(.system(size: 13)).foregroundStyle(.secondary).lineLimit(1)
                }
            }
            Spacer(minLength: 4)
            if case .player(let link) = studio.source {
                Link(destination: link.url) {
                    Image(systemName: "arrow.up.right.square").font(.system(size: 16))
                }
                .foregroundStyle(.secondary)
                .accessibilityLabel("Open in \(link.provider.rawValue)")
                .help("Open source link")
            }
        }
        .padding(12)
        .panel()
    }

    private var cover: some View {
        ZStack {
            Rectangle().fill(.primary.opacity(0.07))
            if let data = studio.metadata?.cover {
                Artwork(data: data).equatable()
            } else {
                Image(systemName: studio.source?.icon ?? "music.note")
                    .font(.system(size: 22, weight: .regular)).foregroundStyle(.secondary)
            }
        }
        .frame(width: 66, height: 66)
        .clipShape(RoundedRectangle(cornerRadius: 5))
        .accessibilityHidden(true)
    }

    private var transport: some View {
        VStack(alignment: .leading, spacing: 12) {
        HStack(spacing: 12) {
            if studio.source?.isLive != true {
            Button(action: studio.toggle) {
                Label(studio.active ? "Stop playback" : "Play source",
                      systemImage: studio.active ? "stop.fill" : "play.fill")
            }
            .controlSize(.regular)
            .accessibilityLabel(studio.active ? "Stop trackpad output" : "Play through trackpad")
            }
            if studio.partyEnd > 0 {
                TimelineView(.periodic(from: .now, by: 1)) { _ in
                    let seconds = max(0, Int(ceil(studio.partyEnd - ProcessInfo.processInfo.systemUptime)))
                    Label("\(seconds)s", systemImage: "sparkles")
                        .font(.caption.monospacedDigit()).foregroundStyle(.purple)
                        .accessibilityLabel("Insane Ultra, \(seconds) seconds remaining")
                }
            }
            if studio.localBypass { Text("Speakers only").font(.system(size: 13)).foregroundStyle(.secondary) }
            if let duration = studio.duration, duration > 0 {
                Text(timestamp(studio.elapsed)).monospacedDigit().font(.callout)
                Meter(value: min(1, studio.elapsed / duration), label: "Playback progress", party: studio.partyEnd > 0)
                    .frame(height: studio.partyEnd > 0 ? 6 : 4)
                Text(timestamp(duration)).monospacedDigit().font(.callout).foregroundStyle(.secondary)
            } else {
                Text(studio.active && (studio.source == .macAudio || (studio.mode == .trackpad && studio.tuning.vocalQuality == .isolated)) ? studio.detection : studio.waiting ? "Waiting for audio" : studio.active ? "Routing audio" : "Ready")
                    .foregroundStyle(.secondary)
                    .font(.callout)
                if studio.partyEnd > 0 {
                    TimelineView(.animation(minimumInterval: reduceMotion ? 0.25 : 0.05)) { _ in
                        Meter(value: max(0, min(1, 1 - (studio.partyEnd - ProcessInfo.processInfo.systemUptime) / PartyBurst.length)),
                              label: "Ultra burst progress", party: true).frame(height: 5)
                    }
                } else { Spacer() }
            }
        }
            Divider()
            HStack(spacing: 16) {
                Toggle("Keyboard light", isOn: $studio.keyboard)
                    .toggleStyle(.checkbox)
                    .help("Pulse a supported keyboard backlight with detected beats.")
                Spacer(minLength: 8)
                Toggle("Follow Mac volume", isOn: $studio.followVolume)
                    .toggleStyle(.checkbox)
                    .help("Scale haptic strength with your current audio output's volume.")
            }
            .font(.system(size: 13))
        }
        .padding(16)
        .panel()
    }

    private var output: some View {
        VStack(alignment: .leading, spacing: 10) {
            HStack {
                Text("Output").font(.system(size: 16, weight: .semibold)).accessibilityAddTraits(.isHeader)
                Spacer()
                if studio.mode == .assist {
                    Toggle("Haptics", isOn: Binding(
                        get: { studio.active && !studio.localBypass },
                        set: { enabled in
                            guard enabled != (studio.active && !studio.localBypass) else { return }
                            if studio.active { studio.toggleAssist() }
                            else if enabled { studio.toggle() }
                        }))
                        .toggleStyle(.switch).controlSize(.small)
                        .help("Turn trackpad haptics on or off while the song keeps playing.")
                }
            }
            ModeSwitch(mode: $studio.mode)
            if let name = studio.patternName, studio.mode == .assist {
                Text("Custom pattern · " + name).font(.system(size: 13, weight: .medium)).lineLimit(1)
                Text(studio.patternNote ?? "").font(.system(size: 13)).foregroundStyle(.secondary)
            } else {
                Text("Automatic haptics").font(.system(size: 13, weight: .medium))
                Text(studio.mode == .assist ? "Shapes rhythm and texture from the music playing on your Mac." : "Follows vocals from the music playing on your Mac.")
                    .font(.system(size: 13)).foregroundStyle(.secondary)
                    .fixedSize(horizontal: false, vertical: true)
            }
            Divider()
            if studio.mode == .trackpad {
                Picker("Vocal quality", selection: $studio.tuning.vocalQuality) {
                    ForEach(VocalQuality.allCases) { Text($0.rawValue).tag($0) }
                }
                .pickerStyle(.segmented)
                Text(studio.tuning.vocalQuality.description)
                    .font(.system(size: 13)).foregroundStyle(.secondary)
                    .fixedSize(horizontal: false, vertical: true)
                HStack {
                    Text("Vocal tone")
                    Spacer()
                    Picker("Vocal tone", selection: $studio.tuning.profile) {
                        ForEach(Profile.allCases) { Text($0.rawValue).tag($0) }
                    }
                    .labelsHidden().fixedSize().help(studio.tuning.profile.description)
                }
            }
            PrecisionWheel(title: "Intensity", value: $studio.tuning.gain, range: 0...1, step: 0.01,
                        label: "\(Int((studio.tuning.gain * 100).rounded()))%")
            Text("Point at a value and swipe with two fingers. Click for a slider.")
                .font(.system(size: 13)).foregroundStyle(.secondary).fixedSize(horizontal: false, vertical: true)
            Picker("Genre", selection: Binding(get: { studio.genre }, set: studio.setGenre)) {
                ForEach(ListeningGenre.allCases) { Text($0.rawValue).tag($0) }
            }
            HStack {
                Button("Fine Tune…") { showTuning = true }
                Spacer()
                Button(studio.partyEnd > 0 ? "Stop Ultra" : "Insane Ultra…") {
                    if studio.partyEnd > 0 { studio.cancelParty() }
                    else { burstLights = !reduceMotion; burstDemo = false; showBurst = true }
                }
            }
            if case .file = studio.source {
                HStack {
                    Button("Attach Pattern…", action: studio.choosePattern)
                        .disabled(studio.mode != .assist)
                    if studio.patternName != nil {
                        Button("Use Automatic", action: studio.clearPattern)
                    }
                }
                Text("Optional authored haptics for this local audio file.")
                    .font(.system(size: 13)).foregroundStyle(.secondary)
            }
        }
        .padding(18)
        .panel()
    }

    private var equalizer: some View {
        VStack(alignment: .leading, spacing: 9) {
            HStack {
                Text("Trackpad EQ").font(.system(size: 16, weight: .semibold)).accessibilityAddTraits(.isHeader)
                Spacer()
                Toggle("Enable trackpad equalizer", isOn: $studio.tuning.eq.enabled)
                    .labelsHidden().toggleStyle(.switch).controlSize(.mini)
            }
            if !studio.tuning.eq.enabled {
                Text("Bypassed · adjust a band to enable EQ").font(.system(size: 13)).foregroundStyle(.secondary)
            }
            EQCurve(eq: studio.tuning.eq, wetMix: studio.tuning.eq.enabled ? 1 : 0)
                .opacity(studio.tuning.eq.enabled ? 1 : 0.44)
                .frame(height: 70)
                .accessibilityHidden(true)
            ForEach(Band.allCases) { band in
                let binding = bandBinding(band)
                HStack(spacing: 6) {
                    PrecisionWheel(title: band.rawValue, value: binding.gain, range: -12...12, step: 0.5,
                                   label: signedDB(binding.gain.wrappedValue))
                    Stepper(band.rawValue + " gain", value: binding.gain, in: -12...12, step: 0.5)
                        .labelsHidden().controlSize(.small)
                        .help("Raise or lower " + band.rawValue.lowercased() + " by half a decibel")
                }

            }
            HStack {
                Button("Reset EQ") { studio.tuning.eq = EQ(enabled: studio.tuning.eq.enabled) }
                Spacer()
                Button("Band Settings…") { showEQDetails = true }
            }
            .controlSize(.small)
        }
        .padding(18)
        .panel()
        .animation(reduceMotion ? nil : .easeInOut(duration: 0.28), value: studio.tuning.eq.enabled)
    }

    private var tuningSheet: some View {
        VStack(alignment: .leading, spacing: 14) {
            Text("Fine Tune").font(.title2.weight(.semibold))
            Text(studio.mode.rawValue).foregroundStyle(.secondary)
            if studio.mode == .assist {
                PrecisionWheel(title: "Bass sustain", value: $studio.tuning.bassSustain, range: 0...1, step: 0.01,
                               label: "\(Int((studio.tuning.bassSustain * 100).rounded()))%")
                    .help("Adds a softer continuous layer for detected low bass. Set to zero for taps only.")
                PrecisionWheel(title: "Transient emphasis", value: $studio.tuning.impact, range: 0...1, step: 0.01,
                               label: "\(Int((studio.tuning.impact * 100).rounded()))%")
                    .help("Changes the fade after a detected percussion hit. Higher values make shorter, crisper taps; lower values leave a longer tail. It does not change beat timing.")
                Text("Higher emphasis makes drum taps shorter and crisper.")
                    .font(.system(size: 13)).foregroundStyle(.secondary)
            }
            if studio.mode == .trackpad {
                PrecisionWheel(title: "Tone balance", value: $studio.tuning.tone, range: -1...1, step: 0.01,
                            label: toneLabel)
                PrecisionWheel(title: "Pitch smoothing", value: $studio.tuning.smoothing, range: 0...90, step: 1,
                            label: "\(Int(studio.tuning.smoothing)) ms")
                    .help("Smooth sustained notes. Lower values react faster to pitch changes.")
                Stepper(value: $studio.tuning.partials, in: 2...8) {
                    LabeledContent("Maximum tones", value: "\(studio.tuning.partials)")
                        .monospacedDigit()
                }
                .help("More tones preserve more of a dense mix. Fewer tones give each note more strength.")
            }
            if studio.mode == .assist {
                Toggle("Match audio output timing", isOn: $studio.tuning.automaticTiming)
                    .onChange(of: studio.tuning.automaticTiming) { _, automatic in
                        if !automatic { studio.tuning.delay = max(0, studio.tuning.delay) }
                    }
                PrecisionWheel(title: studio.tuning.automaticTiming ? "Timing offset" : "Haptic delay",
                               value: $studio.tuning.delay,
                               range: studio.tuning.automaticTiming ? -100...300 : 0...300, step: 2,
                               label: String(format: "%+.0f ms", studio.tuning.delay))
                    .help("Positive values add delay. Negative values reduce the automatic delay.")
                Text("Automatic timing uses the selected audio output’s reported latency.")
                    .font(.system(size: 13)).foregroundStyle(.secondary)
            }
            HStack {
                Button("Reset Tuning") {
                    let eq = studio.tuning.eq
                    var defaults = studio.mode.defaults
                    defaults.eq = eq
                    studio.tuning = defaults
                }
                Spacer()
                Button("Done") { showTuning = false }.keyboardShortcut(.defaultAction)
            }
        }
        .padding(23).frame(width: 380)
    }

    private var eqSheet: some View {
        VStack(alignment: .leading, spacing: 13) {
            Text("EQ Band Settings").font(.title2.weight(.semibold))
            EQCurve(eq: studio.tuning.eq, wetMix: studio.tuning.eq.enabled ? 1 : 0).frame(height: 80).accessibilityHidden(true)
            ForEach(Band.allCases) { band in
                let binding = bandBinding(band)
                VStack(alignment: .leading, spacing: 3) {
                    Text(band.rawValue).font(.headline)
                    PrecisionWheel(title: "\(band.rawValue) frequency", value: binding.frequency,
                                range: band.range, step: 1, label: "\(Int(binding.frequency.wrappedValue)) Hz")
                    PrecisionWheel(title: "\(band.rawValue) width (Q)", value: binding.q,
                                range: 0.35...3.5, step: 0.05, label: String(format: "%.2f", binding.q.wrappedValue))
                }
            }
            HStack {
                Spacer()
                Button("Done") { showEQDetails = false }.keyboardShortcut(.defaultAction)
            }
        }
        .padding(23).frame(width: 390)
    }

    @ViewBuilder private var notice: some View {
        if let error = studio.error {
            noticeRow(error, symbol: "exclamationmark.circle")
        } else if studio.captureHelp {
            noticeRow("If audio is already playing, check System Audio Recording access. Some protected tracks can be silent.", symbol: "info.circle")
        }
    }

    private func noticeRow(_ message: String, symbol: String) -> some View {
        HStack(alignment: .top, spacing: 8) {
            Image(systemName: symbol)
            Text(message).frame(maxWidth: .infinity, alignment: .leading)
            if studio.captureHelp { Button("Audio Privacy Settings…", action: studio.permissions).controlSize(.small) }
        }
        .font(.callout)
        .padding(10)
        .panel()
    }

    private func bandBinding(_ band: Band) -> Binding<EQBand> {
        Binding(get: { studio.tuning.eq[band] }, set: { var next = studio.tuning; next.eq[band] = $0; next.eq.enabled = true; studio.tuning = next })
    }

    private var toneLabel: String {
        let value = Int((studio.tuning.tone * 100).rounded())
        if value == 0 { return "Neutral" }
        return "\(abs(value))% \(value < 0 ? "bass" : "detail")"
    }
}

private struct Artwork: View, Equatable {
    let data: Data
    var body: some View {
        if let image = NSImage(data: data) { Image(nsImage: image).resizable().aspectRatio(contentMode: .fill) }
    }
}

private let surface = Color(nsColor: .controlBackgroundColor)

private extension View {
    func panel() -> some View {
        background(Color(nsColor: .controlBackgroundColor), in: RoundedRectangle(cornerRadius: 16, style: .continuous))
            .overlay { RoundedRectangle(cornerRadius: 16, style: .continuous)
                .strokeBorder(Color(nsColor: .separatorColor).opacity(0.6), lineWidth: 0.5) }
    }

    @ViewBuilder func primaryGlassAction() -> some View {
        if #available(macOS 26.0, *) {
            self.buttonStyle(.glassProminent).controlSize(.large)
        } else {
            self.buttonStyle(.borderedProminent).controlSize(.large)
        }
    }

    @ViewBuilder func glassControlButton() -> some View {
        if #available(macOS 26.0, *) {
            self.buttonStyle(.glass).controlSize(.large)
        } else {
            self.buttonStyle(.bordered).controlSize(.large)
        }
    }
}

private struct Monitor: View {
    @ObservedObject var display: SignalDisplay
    let waiting: Bool
    let status: String?
    @Environment(\.accessibilityReduceMotion) private var reduceMotion

    var body: some View {
        let signal = display.frame
        VStack(alignment: .leading, spacing: 8) {
            HStack {
                Text("Signal Monitor").font(.system(size: 16, weight: .semibold)).accessibilityAddTraits(.isHeader)
                Spacer()
                Text(signal.hasAudio ? "Signal" : waiting ? "Waiting" : "Idle")
                    .font(.system(size: 13, weight: .medium)).foregroundStyle(.secondary)
            }
            ZStack {
                TimelineView(.animation(minimumInterval: reduceMotion ? 0.10 : 1.0 / 60, paused: !signal.hasAudio && !display.settling)) { _ in
                    Trace(values: display.bands(at: ProcessInfo.processInfo.systemUptime))
                }
                .accessibilityHidden(true)
                if !signal.hasAudio && !display.settling {
                    Text(status ?? (waiting ? "Play audio in your source app." : "No signal"))
                        .font(.callout).foregroundStyle(.secondary)
                        .padding(.horizontal, 9).padding(.vertical, 4)
                        .background(surface, in: RoundedRectangle(cornerRadius: 4))
                }
            }
            .frame(height: 179)
            HStack {
                Text("65 Hz")
                Spacer()
                Text("510 Hz")
                Spacer()
                Text("4 kHz")
            }
            .font(.system(size: 13)).foregroundStyle(.secondary)
            Divider()
            HStack {
                Text("Level").font(.system(size: 13)).foregroundStyle(.secondary)
                if signal.inputRMS > 0 {
                    let decibels = 20 * log10(signal.inputRMS)
                    Meter(value: min(1, max(0, 1 + decibels / 60)))
                        .frame(height: 4)
                    Text("\(Int(decibels.rounded())) dB").font(.caption.monospacedDigit())
                        .foregroundStyle(.secondary).frame(width: 48, alignment: .trailing)
                } else {
                    Meter(value: 0).frame(height: 4)
                    Text("— dB").font(.system(size: 13)).foregroundStyle(.secondary).frame(width: 48, alignment: .trailing)
                }
            }
        }
        .padding(18)
        .panel()
    }
}

private struct Trace: View {
    let values: [Double]
    var body: some View {
        Canvas { context, size in
            plotGrid(context, size: size)
            let mid = size.height * 0.5
            let points = values.enumerated().map { i, v in
                CGPoint(x: size.width * Double(i) / Double(values.count - 1),
                        y: mid - max(0.5, v * size.height * 0.43))
            }
            func contour(_ points: [CGPoint]) -> Path {
                var path = Path()
                path.move(to: points[0])
                for i in 1..<points.count {
                    let end = CGPoint(x: (points[i].x + points[i-1].x) * 0.5,
                                      y: (points[i].y + points[i-1].y) * 0.5)
                    path.addQuadCurve(to: end, control: points[i-1])
                }
                path.addLine(to: points.last!)
                return path
            }
            let crest = contour(points)
            let reflection = crest.applying(CGAffineTransform(a: 1, b: 0, c: 0, d: -0.60, tx: 0, ty: mid * 1.60))
            for (edge, alpha) in [(crest, 0.70), (reflection, 0.26)] {
                var fill = edge
                fill.addLine(to: CGPoint(x: size.width, y: mid))
                fill.addLine(to: CGPoint(x: 0, y: mid))
                fill.closeSubpath()
                context.fill(fill, with: .linearGradient(Gradient(colors: [.primary.opacity(alpha * 0.54), .primary.opacity(0.05)]),
                    startPoint: CGPoint(x: 0, y: edge.boundingRect.minY), endPoint: CGPoint(x: 0, y: mid + 0.5)))
                context.stroke(edge, with: .color(.primary.opacity(alpha)), lineWidth: 1.4)
            }
        }
    }
}

private struct EQCurve: View, Animatable {
    let eq: EQ
    var wetMix: Double
    var animatableData: Double {
        get { wetMix }
        set { wetMix = newValue }
    }

    var body: some View {
        Canvas { context, size in
            plotGrid(context, size: size)
            func x(_ frequency: Double) -> CGFloat {
                size.width * log(frequency / 65) / log(4000.0 / 65)
            }
            func y(_ frequency: Double) -> CGFloat {
                var enabledEQ = eq
                enabledEQ.enabled = true
                let gain = wetMix * min(12, max(-12, enabledEQ.response(at: frequency)))
                return size.height / 2 - size.height * gain / 26
            }

            var path = Path()
            for index in 0...92 {
                let progress = Double(index) / 92
                let frequency = 65 * pow(4000.0 / 65, progress)
                let point = CGPoint(x: size.width * progress, y: y(frequency))
                if index == 0 { path.move(to: point) } else { path.addLine(to: point) }
            }
            context.stroke(path, with: .color(.primary.opacity(0.34 + wetMix * 0.56)), lineWidth: 1.45)
            if wetMix > 0.001 {
                for band in Band.allCases {
                    let frequency = eq[band].frequency
                    let dot = CGRect(x: x(frequency) - 2.25, y: y(frequency) - 2.25, width: 4.5, height: 4.5)
                    context.fill(Path(ellipseIn: dot), with: .color(.primary.opacity(wetMix)))
                }
            }
        }
    }
}

private func plotGrid(_ context: GraphicsContext, size: CGSize) {
    var path = Path()
    for index in 0...8 {
        let x = size.width * CGFloat(index) / 8
        path.move(to: CGPoint(x: x, y: 0))
        path.addLine(to: CGPoint(x: x, y: size.height))
    }
    for index in 0...4 {
        let y = size.height * CGFloat(index) / 4
        path.move(to: CGPoint(x: 0, y: y))
        path.addLine(to: CGPoint(x: size.width, y: y))
    }
    context.stroke(path, with: .color(.primary.opacity(0.1)), lineWidth: 0.75)
}

private struct Meter: View {
    let value: Double
    var label = "Signal level"
    var party = false
    var body: some View {
        GeometryReader { proxy in
            ZStack(alignment: .leading) {
                Capsule().fill(.primary.opacity(0.12))
                if party {
                    Capsule().fill(LinearGradient(colors: [.pink, .orange, .yellow, .mint, .cyan, .purple],
                        startPoint: .leading, endPoint: .trailing))
                        .frame(width: proxy.size.width * value).shadow(color: .purple.opacity(0.6), radius: 3)
                } else {
                    Capsule().fill(.primary.opacity(0.75)).frame(width: proxy.size.width * value)
                }
            }
        }
        .accessibilityLabel(label)
        .accessibilityValue("\(Int(value * 100)) percent")
    }
}

private func signedDB(_ value: Double) -> String { String(format: "%+.1f dB", value) }

private func timestamp(_ seconds: Double) -> String {
    let time = Int(exactly: max(0, seconds).rounded(.down)) ?? 0
    return String(format: "%d:%02d", time / 60, time % 60)
}
