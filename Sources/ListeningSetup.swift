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
                .accessibilityAddTraits(.isHeader).accessibilityIdentifier("onboarding.heading")
            if practice {
                Text("Point at the number and swipe up or down with two fingers. Click it for a slider or an exact value.")
                PrecisionWheel(title: "Intensity", value: $intensity, range: 0...1, step: 0.01,
                               label: "\(Int((intensity * 100).rounded()))%")
                Divider()
                Toggle("Listen for music when SongWave opens", isOn: $automatic)
                ScrollView { ListeningOrientation() }.frame(maxHeight: 255)
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
            Text("Ultra follows your music for \(Int(PartyBurst.length)) seconds with a temporary punchier EQ, lifted accents and stronger beat lighting. Your saved EQ and intensity stay unchanged. You can stop it at any time. Allow a minute between runs.")
            Text("Repeated strong vibration may add heat and motor wear. Long-term effects on adhesives and fasteners are unknown. Apple provides no safe continuous-run rating for this use.")
            Text("The keyboard light pulses if enabled and supported. Leave lighting off if pulsing light bothers you.")
        }.font(.callout).foregroundStyle(.secondary)
    }
}

// Shared orientation for first-time setup and the one-time 1.0 upgrade note.
// It describes existing choices without changing playback or requesting access.
struct ListeningOrientation: View {
    var body: some View {
        VStack(alignment: .leading, spacing: 14) {
            item("Play normally", "Play music in Spotify, Music or your browser. No link needed. Listening help has connection status and an optional trackpad test.")
            item("Feel it or follow visually", "Choose Beat, Voice or Both. Haptics off keeps music and visual feedback running. Ultra adds a glow.")
            item("Find your tools", "Tools groups Sound (genre and Fine Tune), Trackpad EQ, and Experiments (keyboard light and Ultra).")
            item("Updates you approve", "SongWave checks about once an hour. Smaller downloads include only changes when possible. You approve downloading and installing. Turn automatic checks off in Settings → Updates.")
        }
    }
    private func item(_ title: String, _ detail: String) -> some View {
        VStack(alignment: .leading, spacing: 4) {
            Text(title).font(.callout.weight(.semibold)).accessibilityAddTraits(.isHeader)
            Text(detail).font(.callout).foregroundStyle(.secondary)
                .fixedSize(horizontal: false, vertical: true)
        }
    }
}

struct UpgradeOrientation: View {
    let done: () -> Void
    var body: some View {
        VStack(alignment: .leading, spacing: 18) {
            Text("Welcome to SongWave 1.0").font(.title2.weight(.semibold)).accessibilityAddTraits(.isHeader)
                .accessibilityIdentifier("upgrade.heading")
            Text("Your listening preferences stay as you left them.")
                .font(.callout).foregroundStyle(.secondary)
            ScrollView { ListeningOrientation().frame(maxWidth: .infinity, alignment: .leading) }
                .frame(maxHeight: 380)
            HStack { Spacer(); Button("Continue", action: done).keyboardShortcut(.defaultAction) }
        }.padding(24).frame(width: 450)
            .accessibilityElement(children: .contain).accessibilityLabel("SongWave 1.0 orientation")
            .accessibilityIdentifier("upgrade.content")
    }
}
