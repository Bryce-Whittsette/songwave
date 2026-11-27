import SwiftUI

struct AudioSetupContent: View {
    @ObservedObject var studio: Studio
    var body: some View {
        VStack(alignment: .leading, spacing: 16) {
            Text("Allow System Audio Recording so SongWave can follow music playing on this Mac. You won’t need to paste a song link.")
            Text("Next, you’ll see audio activity and can choose a brief trackpad test. No test runs automatically.")
                .font(.callout).foregroundStyle(.secondary)
            Button(studio.audioAccessHealth.failure == nil ? "Allow System Audio…" : "Retry audio access") {
                Task { _ = await studio.prepareAudioAccess() }
            }.buttonStyle(.borderedProminent).disabled(studio.requestingAudioAccess)
            if studio.requestingAudioAccess { ProgressView("Checking audio access…").controlSize(.small) }
            if studio.audioAccessHealth.failure != nil {
                Text("Audio access wasn’t available. Check the permission in System Settings, then retry.")
                    .font(.callout)
                Button("Privacy Settings…", action: studio.permissions)
            }
            Button("Open listening help", action: studio.firstSuccessRecovery).disabled(studio.requestingAudioAccess)
        }.font(.system(size: 14))
    }
}

struct FirstSuccessContent: View {
    @ObservedObject var studio: Studio
    var body: some View {
        VStack(alignment: .leading, spacing: 18) {
            Text("Play a song in your music app. Rest a finger lightly on the trackpad.")
            Label(studio.firstSuccess.audioDetected ? "Audio detected" : "Waiting for music on your Mac",
                  systemImage: studio.firstSuccess.audioDetected ? "checkmark.circle" : "waveform")
                .font(.headline)
            BeatLevelIndicator(display: studio.display)
            Text("During this check, speakers stay unmuted and automatic haptics are paused.")
                .font(.callout).foregroundStyle(.secondary)
            Divider()
            Text("Try three short taps").font(.headline)
            Text("The test lasts less than a second and generates no speaker audio. You can test before music is detected.")
                .font(.callout).foregroundStyle(.secondary)
            Button(studio.testingTrackpad ? "Testing trackpad…" : "Test trackpad", action: studio.testTrackpad)
                .buttonStyle(.borderedProminent).disabled(studio.testingTrackpad)
            if studio.testingTrackpad { ProgressView().controlSize(.small).accessibilityLabel("Trackpad test in progress") }
            if studio.firstSuccess.canConfirm {
                Text("Did you feel the taps?").font(.headline)
                HStack {
                    Button("I felt it", action: studio.confirmFirstSuccess).buttonStyle(.borderedProminent)
                    Button("I didn’t feel anything", action: studio.firstSuccessRecovery)
                }
            }
            Button("Open listening help", action: studio.firstSuccessRecovery).disabled(studio.testingTrackpad)
            Text("A moving meter confirms audio activity, not a physical sensation. Only your answer confirms the trackpad test.")
                .font(.callout).foregroundStyle(.secondary)
        }.font(.system(size: 14))
    }
}

struct RecoveryContent: View {
    @ObservedObject var studio: Studio
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
                Button("Retry") { studio.probe(force: true) }.disabled(busy)
                Button("Trackpad Settings…", action: studio.trackpadSettings)
            }
            Divider()
            status("Audio capture", value: health.capture.rawValue, icon: "waveform") {
                Button(studio.audioAccessReady ? "Retry capture" : "Allow System Audio…") {
                    Task {
                        let failure = await studio.prepareAudioAccess()
                        if failure == nil && !studio.firstSuccessPending && !studio.verifyingSetup { studio.retryListening() }
                    }
                }.disabled(busy)
                Button("Privacy Settings…", action: studio.permissions)
            }
            Divider()
            status("Selected app", value: studio.selectedAppLabel, icon: "app") {
                Button("Scan / Retry", action: studio.retryListening).disabled(busy)
                Button("Player access…") { showPlayerAccess = true }
            }
            if showPlayerAccess {
                PlayerConnectionControls(studio: studio, playerRequest: $playerRequest)
                    .padding(12).background(.quaternary, in: RoundedRectangle(cornerRadius: 10))
            }
            Divider()
            status("Listening state", value: health.pause.rawValue, icon: "pause.circle") {
                Button("Retry listening", action: studio.retryListening).disabled(busy)
                Button("Filter settings…") { studio.requestedSettingsPage = "Effects"; openSettings() }
            }
            if studio.trackpadFailure != nil {
                Text("The trackpad check needs attention. Check the connection, then retry. End any active call before running the tap test.")
                    .font(.callout).foregroundStyle(.secondary)
            }
            Divider()
            HStack {
                Button("Run setup check", action: studio.beginFirstSuccess).disabled(busy)
                Spacer()
                Button(copied ? "Diagnostics copied" : "Copy diagnostics") { studio.copyDiagnostics(); copied = true }
            }
            Text("Diagnostics contain app/build, Mac model, macOS, output transport, app category and connection states. No song titles, recordings, device names or personal paths are copied. Nothing is sent automatically.")
                .font(.caption).foregroundStyle(.secondary)
        }.font(.system(size: 14))
    }
    private func status<Actions: View>(_ title: String, value: String, icon: String, @ViewBuilder actions: () -> Actions) -> some View {
        VStack(alignment: .leading, spacing: 8) {
            Label(title, systemImage: icon).font(.headline)
            Text(value).textSelection(.enabled)
            HStack(spacing: 12, content: actions).controlSize(.small)
        }.frame(maxWidth: .infinity, alignment: .leading)
    }
}

// Small, local motion only. No full-screen flashes or color-coded states.
struct BeatLevelIndicator: View {
    @ObservedObject var display: SignalDisplay
    @Environment(\.accessibilityReduceMotion) private var reduceMotion
    var body: some View {
        TimelineView(.animation(minimumInterval: 1.0 / 30, paused: !display.isVisible || !display.frame.hasAudio)) { _ in
            let beat = display.beat(at: ProcessInfo.processInfo.systemUptime)
            let signal = display.frame
            let level = signal.inputRMS.isFinite && signal.inputRMS > 0 ? min(1, max(0, 1 + 20 * log10(signal.inputRMS) / 60)) : 0
            HStack(spacing: 10) {
                Circle().fill(.primary.opacity(beat > 0 ? 0.9 : 0.22))
                    .frame(width: 12, height: 12)
                    .scaleEffect(reduceMotion ? 1 : 1 + beat * 0.25)
                    .frame(width: 20, height: 20).accessibilityHidden(true)
                Text(beat > 0 ? "Beat detected" : "Beat").font(.callout).frame(width: 96, alignment: .leading)
                ProgressView(value: level).tint(.primary)
                Text("\(Int(level * 100))%").font(.caption.monospacedDigit()).frame(width: 36, alignment: .trailing)
            }
            .accessibilityElement(children: .ignore)
            .accessibilityLabel("Visual music activity")
            .accessibilityValue("\(signal.hasAudio ? "Audio detected" : "No audio"). Level \(Int(level * 100)) percent. \(beat > 0 ? "Beat detected." : "")")
        }
    }
}
