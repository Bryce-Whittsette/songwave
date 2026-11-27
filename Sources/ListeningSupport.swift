import SwiftUI

struct AudioSetupContent: View {
    @ObservedObject var studio: Studio
    @Environment(\.accessibilityReduceMotion) private var systemReduceMotion
    @Environment(\.songWaveAdditionalMotionReduction) private var additionalMotionReduction
    private var reduceMotion: Bool { AccessibleMotion.reduced(system: systemReduceMotion, additional: additionalMotionReduction) }
    var body: some View {
        VStack(alignment: .leading, spacing: 16) {
            Text("Allow System Audio Recording so SongWave can follow music playing on this Mac. You won’t need to paste a song link.")
            Text("Next, you’ll see audio activity and can choose a brief trackpad test. No test runs automatically.")
                .font(.callout).foregroundStyle(.secondary)
            Button(studio.audioAccessHealth.failure == nil ? "Allow System Audio…" : "Retry audio access") {
                Task { _ = await studio.prepareAudioAccess() }
            }.buttonStyle(.borderedProminent).disabled(studio.requestingAudioAccess)
                .accessibilityIdentifier("setup.allow")
            if studio.requestingAudioAccess { ProgressView("Checking audio access…").controlSize(.small) }
            if studio.audioAccessHealth.failure != nil {
                Text("Audio access wasn’t available. Check the permission in System Settings, then retry.")
                    .font(.callout)
                Button("Privacy Settings…", action: studio.permissions).accessibilityIdentifier("recovery.capture.settings")
            }
            Button("Open listening help", action: studio.firstSuccessRecovery).disabled(studio.requestingAudioAccess)
                .accessibilityIdentifier("setup.help")
        }.font(.system(size: 14))
            .transaction { AccessibleMotion.apply(to: &$0, reduced: reduceMotion) }
    }
}

struct FirstSuccessContent: View {
    @ObservedObject var studio: Studio
    @Environment(\.accessibilityReduceMotion) private var systemReduceMotion
    @Environment(\.songWaveAdditionalMotionReduction) private var additionalMotionReduction
    private var reduceMotion: Bool { AccessibleMotion.reduced(system: systemReduceMotion, additional: additionalMotionReduction) }
    var body: some View {
        VStack(alignment: .leading, spacing: 18) {
            Text("Play a song in your music app. Rest a finger lightly on the trackpad.")
            Label(studio.firstSuccess.audioStatus,
                  systemImage: studio.firstSuccess.audioPresent ? "checkmark.circle" : "waveform")
                .font(.headline)
            BeatLevelIndicator(display: studio.display)
            Text("During this check, speakers stay unmuted and automatic haptics are paused.")
                .font(.callout).foregroundStyle(.secondary)
            Divider()
            Text("Try three short taps").font(.headline).accessibilityAddTraits(.isHeader).accessibilityHeading(.h2).accessibilityIdentifier("setup.test.heading")
            Text("The test lasts less than a second and generates no speaker audio. You can test before music is detected.")
                .font(.callout).foregroundStyle(.secondary)
            Button(studio.testingTrackpad ? "Testing trackpad…" : "Test trackpad", action: studio.testTrackpad)
                .buttonStyle(.borderedProminent).disabled(studio.testingTrackpad)
                .accessibilityIdentifier("setup.test")
            if studio.testingTrackpad { ProgressView().controlSize(.small).accessibilityLabel("Trackpad test in progress") }
            if studio.firstSuccess.canConfirm {
                Text("Did you feel the taps?").font(.headline).accessibilityAddTraits(.isHeader).accessibilityHeading(.h2).accessibilityIdentifier("setup.confirm.heading")
                HStack {
                    Button("I felt it", action: studio.confirmFirstSuccess).buttonStyle(.borderedProminent)
                        .accessibilityIdentifier("setup.confirm")
                    Button("I didn’t feel anything", action: studio.firstSuccessRecovery)
                        .accessibilityIdentifier("setup.recover")
                }
            }
            Button("Open listening help", action: studio.firstSuccessRecovery).disabled(studio.testingTrackpad)
                .accessibilityIdentifier("setup.help")
            Text("A moving meter confirms audio activity, not a physical sensation. Only your answer confirms the trackpad test.")
                .font(.callout).foregroundStyle(.secondary)
        }.font(.system(size: 14))
            .transaction { AccessibleMotion.apply(to: &$0, reduced: reduceMotion) }
    }
}

struct RecoveryContent: View {
    @ObservedObject var studio: Studio
    @Environment(\.accessibilityReduceMotion) private var systemReduceMotion
    @Environment(\.songWaveAdditionalMotionReduction) private var additionalMotionReduction
    private var reduceMotion: Bool { AccessibleMotion.reduced(system: systemReduceMotion, additional: additionalMotionReduction) }
    @Binding var playerRequest: Provider?
    @Environment(\.openSettings) private var openSettings
    @State private var showPlayerAccess = false
    @State private var copied = false
    private var busy: Bool { studio.requestingAudioAccess || studio.testingTrackpad || playerRequest != nil }
    var body: some View {
        let health = studio.healthSnapshot
        VStack(alignment: .leading, spacing: 16) {
            if studio.firstSuccess.phase == .recovery && studio.trackpadFailure == nil {
                Text("The trackpad sensation is unconfirmed. Check the connection below, then choose Run setup check to try again.")
                    .font(.callout)
            }
            Text("Check each part of the connection. Retry never bypasses call or speech filtering.")
                .font(.callout).foregroundStyle(.secondary)
            status("Trackpad", value: health.trackpadAvailable ? (studio.trackpadFailure != nil ? "Detected; tap test needs attention" : studio.device ?? "Available") : "Unavailable or not checked", icon: "trackpad") {
                Button("Retry trackpad") { studio.probe(force: true) }.disabled(busy).accessibilityIdentifier("recovery.trackpad.retry")
                Button("Trackpad Settings…", action: studio.trackpadSettings).accessibilityIdentifier("recovery.trackpad.settings")
            }
            Divider()
            status("Audio capture", value: health.capture.rawValue, icon: "waveform") {
                Button(studio.audioAccessReady ? "Retry capture" : "Allow System Audio…") {
                    Task { await studio.retryCapture() }
                }.disabled(busy || health.capture == .localFile).accessibilityIdentifier("recovery.capture.retry")
                Button("Privacy Settings…", action: studio.permissions).accessibilityIdentifier("recovery.capture.settings")
            }
            Divider()
            status("Selected app", value: studio.selectedAppLabel, icon: "app") {
                Button(studio.retrySourceTitle, action: studio.retryListening).accessibilityIdentifier("recovery.app.retry").disabled(busy)
                Button("Player access…") { showPlayerAccess = true }.accessibilityIdentifier("recovery.app.settings")
            }
            if showPlayerAccess {
                PlayerConnectionControls(studio: studio, playerRequest: $playerRequest)
                    .padding(12).background(.quaternary, in: RoundedRectangle(cornerRadius: 10))
            }
            Divider()
            status("Listening state", value: health.pause.rawValue, icon: "pause.circle") {
                Button("Retry listening", action: studio.retryListening).accessibilityIdentifier("recovery.pause.retry").disabled(busy)
                Button("Filter settings…") { studio.requestedSettingsPage = "Effects"; openSettings() }.accessibilityIdentifier("recovery.pause.settings")
            }
            if studio.trackpadFailure != nil {
                Text("The trackpad check needs attention. Check the connection, then retry. End any active call before running the tap test.")
                    .font(.callout).foregroundStyle(.secondary)
            }
            Divider()
            HStack {
                Button("Run setup check", action: studio.beginFirstSuccess).disabled(busy).accessibilityIdentifier("recovery.check")
                Spacer()
                Button(copied ? "Diagnostics copied" : "Copy diagnostics") { studio.copyDiagnostics(); copied = true }.accessibilityIdentifier("recovery.copy")
            }
            Text("Diagnostics contain app/build, Mac model, macOS, output transport, app category and connection states. No song titles, recordings, device names or personal paths are copied. Nothing is sent automatically.")
                .font(.caption).foregroundStyle(.secondary)
        }.font(.system(size: 14))
            .transaction { AccessibleMotion.apply(to: &$0, reduced: reduceMotion) }
    }
    private func status<Actions: View>(_ title: String, value: String, icon: String, @ViewBuilder actions: () -> Actions) -> some View {
        VStack(alignment: .leading, spacing: 8) {
            Label(title, systemImage: icon).font(.headline).accessibilityAddTraits(.isHeader).accessibilityHeading(.h2)
                .accessibilityIdentifier("recovery.heading." + title)
            Text(value).textSelection(.enabled)
            HStack(spacing: 12, content: actions).controlSize(.small)
        }.frame(maxWidth: .infinity, alignment: .leading)
            .accessibilityElement(children: .contain).accessibilityLabel(title)
    }
}

// Small, local motion only. No full-screen flashes or color-coded states.
struct BeatLevelIndicator: View {
    @ObservedObject var display: SignalDisplay
    @Environment(\.accessibilityReduceMotion) private var systemReduceMotion
    @Environment(\.songWaveAdditionalMotionReduction) private var additionalMotionReduction
    private var reduceMotion: Bool { AccessibleMotion.reduced(system: systemReduceMotion, additional: additionalMotionReduction) }
    var body: some View {
        Group {
            if reduceMotion {
                indicator(beat: 0)
            } else {
                TimelineView(.animation(minimumInterval: 1.0 / 30, paused: !display.isVisible || !display.frame.hasAudio)) { _ in
                    indicator(beat: display.beat(at: ProcessInfo.processInfo.systemUptime))
                }
            }
        }
        .transaction { AccessibleMotion.apply(to: &$0, reduced: reduceMotion) }
    }
    private func indicator(beat: Double) -> some View {
        let state = VisualActivityPresentation(signal: display.frame, beat: beat, recentBeat: display.recentBeat,
            reduceMotion: reduceMotion, visible: display.isVisible)
        return HStack(spacing: 10) {
            Circle().fill(.primary.opacity(state.opacity))
                .frame(width: 12, height: 12).scaleEffect(state.scale)
                .frame(width: 20, height: 20).accessibilityHidden(true)
            Text(state.beatDetected ? "Beat detected" : "Beat").font(.callout).frame(width: 96, alignment: .leading)
            ProgressView(value: state.level).tint(.primary)
            Text("\(Int(state.level * 100))%").font(.caption.monospacedDigit()).frame(width: 36, alignment: .trailing)
        }
        .accessibilityRepresentation {
            ProgressView(value: state.level)
                .accessibilityLabel("Visual music activity")
                .accessibilityValue(state.accessibilityValue)
                .accessibilityIdentifier("music.activity")
        }
    }
}
