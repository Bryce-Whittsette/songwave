import SwiftUI

enum ListeningGenre: String, CaseIterable, Identifiable {
    case mixed = "A mix", pop = "Pop / R&B", beats = "Hip-hop / Electronic", rock = "Rock / Metal", acoustic = "Acoustic / Folk", jazz = "Jazz / Classical"
    var id: Self { self }
    var gains: [Double] {
        switch self {
        case .mixed: return [0, 0, 0]
        case .pop: return [1, 0.5, 0]
        case .beats: return [2.5, -0.5, 0.5]
        case .rock: return [1, 1, 0.5]
        case .acoustic: return [-0.5, 1.5, 0.5]
        case .jazz: return [0.5, 1, -0.5]
        }
    }
}

enum ListeningFocus: String, CaseIterable, Identifiable {
    case natural = "Balanced", rhythm = "More bass", clarity = "Clearer notes"
    var id: Self { self }
    func apply(genre: ListeningGenre, to tuning: inout Tuning) {
        let gains = genre.gains
        tuning.profile = self == .clarity ? .detail : self == .rhythm ? .pulse : .balanced
        tuning.eq.bass.gain = gains[0] + (self == .rhythm ? 2 : 0)
        tuning.eq.mid.gain = gains[1] + (self == .clarity ? 1.5 : 0)
        tuning.eq.treble.gain = gains[2] + (self == .clarity ? 1 : 0)
        tuning.eq.enabled = true
    }
}

struct ListeningSetup: View {
    let complete: (Bool, ListeningGenre, ListeningFocus, Double) -> Void
    @State var genre: ListeningGenre
    @State var focus: ListeningFocus
    @State var intensity: Double
    @State var automatic: Bool
    @State private var practice = false

    var body: some View {
        VStack(alignment: .leading, spacing: 16) {
            Text(practice ? "Try the intensity wheel" : "How do you listen?").font(.title.weight(.semibold))
            if practice {
                Text("Point at the number and swipe up or down with two fingers. Click it for a slider or an exact value.")
                PrecisionWheel(title: "Intensity", value: $intensity, range: 0...1, step: 0.01,
                               label: "\(Int((intensity * 100).rounded()))%")
                Divider()
                Toggle("Listen for music when SongWave opens", isOn: $automatic)
                Text("Playback Access opens next. Set up Mac audio and optionally connect Spotify or Music for track details. The waveform near the clock turns haptics on or off.")
                    .font(.callout).foregroundStyle(.secondary)
                Text("Trackpad only follows vocals. Choose Light for speed or Isolated for cleaner separation.")
                    .font(.caption).foregroundStyle(.secondary)
                Text("Repeated strong vibration can add heat and motor wear. Ultra plays brief accents for up to \(Int(PartyBurst.length)) seconds.")
                    .font(.caption).foregroundStyle(.secondary)
                DisclosureGroup("Insane Ultra and hardware wear") { UltraNotice() }
            } else {
                Picker("What do you play most?", selection: $genre) {
                    ForEach(ListeningGenre.allCases) { Text($0.rawValue).tag($0) }
                }
                Picker("What should stand out?", selection: $focus) {
                    ForEach(ListeningFocus.allCases) { Text($0.rawValue).tag($0) }
                }.pickerStyle(.radioGroup)
                Text("These choices set the starting trackpad EQ. You can change each band later.")
                    .font(.callout).foregroundStyle(.secondary)
            }
            HStack {
                if practice { Button("Back") { practice = false } }
                Spacer()
                if practice {
                    Button("Finish Setup") { complete(automatic, genre, focus, intensity) }.keyboardShortcut(.defaultAction)
                } else {
                    Button("Continue") { practice = true }.keyboardShortcut(.defaultAction)
                }
            }
        }.padding(24).frame(width: 425)
    }
}

struct UltraNotice: View {
    var body: some View {
        VStack(alignment: .leading, spacing: 8) {
            Text("Ultra follows your music for \(Int(PartyBurst.length)) seconds with stronger haptic accents. You can stop it at any time. Allow a minute between runs.")
            Text("Repeated strong vibration may add heat and motor wear. Long-term effects on adhesives and fasteners are unknown. Apple provides no safe continuous-run rating for this use.")
            Text("The keyboard light pulses if enabled and supported. Leave lighting off if pulsing light bothers you.")
        }.font(.callout).foregroundStyle(.secondary)
    }
}
