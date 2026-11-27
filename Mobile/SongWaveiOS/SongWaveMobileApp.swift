import MusicKit
import SwiftUI
import UniformTypeIdentifiers

@main
struct SongWaveMobileApp: App {
    @StateObject private var player = MobilePlayer()
    @Environment(\.scenePhase) private var scenePhase
    var body: some Scene {
        WindowGroup {
            MobileContentView(player: player)
                .onChange(of: scenePhase) { _, phase in player.setForeground(phase == .active) }
        }
    }
}

struct MobileContentView: View {
    @ObservedObject var player: MobilePlayer
    @Environment(\.colorScheme) private var scheme
    @State private var importing = false
    @State private var settings = false
    @State private var query = ""
    var body: some View {
        NavigationStack {
            ScrollView {
                VStack(alignment: .leading, spacing: 22) {
                    Text("Music through touch.").font(.title2.weight(.semibold))
                    Text("iPhone development preview").font(.subheadline).foregroundStyle(.secondary)
                    Picker("Music source", selection: $player.source) {
                        ForEach(MobilePlayer.Source.allCases, id: \.self) { Text($0.rawValue).tag($0) }
                    }.pickerStyle(.segmented)
                    if player.source == .files {
                        Button { importing = true } label: { Label("Open audio file", systemImage: "doc.badge.plus") }
                            .buttonStyle(.borderedProminent).disabled(player.busy)
                        Text("Files stay on this iPhone. Voice, Beat and Both use lightweight analysis; no AI isolation model is loaded.")
                            .font(.footnote).foregroundStyle(.secondary)
                    } else {
                        if !player.connected {
                            Button("Connect Apple Music") { Task { await player.connect() } }.buttonStyle(.borderedProminent)
                        } else {
                            HStack {
                                TextField("Search songs", text: $query).textFieldStyle(.roundedBorder).submitLabel(.search)
                                    .onSubmit { Task { await player.search(query) } }
                                Button("Search") { Task { await player.search(query) } }.disabled(player.searching)
                            }
                        }
                        Text("Apple Music playback needs a subscription. Haptics use Apple’s matched song tracks when available. SongWave cannot capture audio from other iPhone apps.")
                            .font(.footnote).foregroundStyle(.secondary)
                    }
                    if player.busy || player.searching { ProgressView() }
                    if let message = player.message { Text(message).font(.callout).accessibilityAddTraits(.updatesFrequently) }
                    playerCard
                    if player.source == .files {
                        VStack(alignment: .leading, spacing: 12) {
                            Text("Feel").font(.headline)
                            Picker("Haptic focus", selection: $player.focus) {
                                ForEach(HapticFocus.allCases) { Text($0.rawValue).tag($0) }
                            }.pickerStyle(.segmented)
                            Text(player.focus.description).font(.footnote).foregroundStyle(.secondary)
                            HStack { Text("Intensity"); Spacer(); Text("\(Int(player.intensity * 100))%").monospacedDigit() }
                            Slider(value: $player.intensity, in: 0...1).accessibilityLabel("Haptic intensity")
                            Toggle("Play audio", isOn: $player.audible)
                            Text("Custom haptics work while SongWave is on screen. Haptics-only playback pauses when the app enters the background.")
                                .font(.footnote).foregroundStyle(.secondary)
                        }
                    }
                    Text(player.hapticStatus).font(.callout).foregroundStyle(.secondary)
                    if player.source == .appleMusic {
                        ForEach(player.songs, id: \.id) { song in
                            Button { Task { await player.select(song) } } label: {
                                HStack(spacing: 12) {
                                    AsyncImage(url: song.artwork?.url(width: 100, height: 100)) { image in image.resizable().scaledToFill() } placeholder: { Color.secondary.opacity(0.12) }
                                        .frame(width: 48, height: 48).clipShape(RoundedRectangle(cornerRadius: 8))
                                    VStack(alignment: .leading) { Text(song.title).font(.body.weight(.medium)); Text(song.artistName).font(.caption).foregroundStyle(.secondary) }
                                    Spacer(); Image(systemName: "chevron.right").font(.caption)
                                }.contentShape(Rectangle())
                            }.buttonStyle(.plain).padding(.vertical, 5)
                        }
                    }
                }.padding(22)
            }
            .navigationTitle("SongWave").navigationBarTitleDisplayMode(.inline)
            .toolbar { ToolbarItem(placement: .topBarTrailing) { Button("Settings") { settings = true } } }
            .tint(scheme == .dark ? .white : .black)
            .fileImporter(isPresented: $importing, allowedContentTypes: [.audio]) { result in
                if case .success(let url) = result { Task { await player.open(url) } }
            }
            .sheet(isPresented: $settings) {
                NavigationStack {
                    Form {
                        Section("Supported sources") {
                            Text("Imported mono/stereo audio files: SongWave Voice/Beat/Both haptics on a supported physical iPhone.")
                            Text("Apple Music: playback inside SongWave with Apple’s Music Haptics for supported songs and devices. App setup is required before this development build can connect.")
                            Text("Spotify and audio playing in other apps are not captured by this iPhone build.")
                        }
                        Section("Accessibility") {
                            Text("A tactile way to explore music, including for Deaf and hard-of-hearing listeners. This preview still needs physical-device and accessibility-user testing.")
                        }
                        Section("Project") {
                            Link("Guide and source code", destination: URL(string: "https://github.com/Bryce-Whittsette/songwave/blob/main/docs/mobile.md")!)
                            ShareLink(item: URL(string: "https://github.com/Bryce-Whittsette/songwave")!) { Label("Share SongWave", systemImage: "square.and.arrow.up") }
                        }
                    }.navigationTitle("Settings")
                        .toolbar { ToolbarItem(placement: .confirmationAction) { Button("Done") { settings = false } } }
                }
            }
        }
    }

    private var playerCard: some View {
        VStack(alignment: .leading, spacing: 16) {
            HStack(spacing: 14) {
                Group {
                    if let image = player.fileArtwork { Image(uiImage: image).resizable().scaledToFill() }
                    else if let artwork = player.artwork { AsyncImage(url: artwork) { image in image.resizable().scaledToFill() } placeholder: { Color.secondary.opacity(0.12) } }
                    else { Image(systemName: "waveform").font(.largeTitle).frame(maxWidth: .infinity, maxHeight: .infinity).background(.quaternary) }
                }.frame(width: 76, height: 76).clipShape(RoundedRectangle(cornerRadius: 12)).accessibilityHidden(true)
                VStack(alignment: .leading, spacing: 5) { Text(player.title).font(.headline); Text(player.artist).font(.subheadline).foregroundStyle(.secondary) }
            }
            ProgressView(value: min(player.duration, player.position), total: max(1, player.duration)).accessibilityLabel("Playback progress")
            HStack {
                Text(time(player.position)).monospacedDigit(); Spacer(); Text(time(player.duration)).monospacedDigit()
            }.font(.caption).foregroundStyle(.secondary)
            HStack(spacing: 20) {
                Button { Task { await player.toggle() } } label: { Label(player.isPlaying ? "Pause" : "Play", systemImage: player.isPlaying ? "pause.fill" : "play.fill") }
                    .buttonStyle(.borderedProminent).disabled(!player.ready || player.starting || player.busy)
                Button("Stop", systemImage: "stop.fill") { player.stopPlayback() }.disabled(!player.ready)
            }
        }.padding(18).background(.regularMaterial, in: RoundedRectangle(cornerRadius: 20))
    }
    private func time(_ seconds: Double) -> String { let n = max(0, Int(seconds.isFinite ? seconds : 0)); return String(format: "%d:%02d", n / 60, n % 60) }
}
