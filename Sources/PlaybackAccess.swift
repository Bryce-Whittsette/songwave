import AppKit
import CoreAudio
import CoreServices
import SwiftUI

enum PlaybackAccess {
    static func requestAudio() async throws {
        try await Task.detached(priority: .userInitiated) {
            let excluded = AudioHardware.processList().filter { process in
                var pid: pid_t = 0
                return AudioHardware.read(process, kAudioProcessPropertyPID, into: &pid) == noErr && pid == getpid()
            }
            let description = CATapDescription(stereoGlobalTapButExcludeProcesses: excluded)
            // Start an unmuted tap so macOS can ask. No samples leave the tap.
            withExtendedLifetime(try AudioTap(description: description, mute: false)) {}
        }.value
    }

    static func playerStatus(_ pid: pid_t, ask: Bool) -> OSStatus {
        let target = NSAppleEventDescriptor(processIdentifier: pid)
        return AEDeterminePermissionToAutomateTarget(target.aeDesc, 0x636f7265, 0x67657464, ask)
    }
}

// Reused inline in Settings and inside the single player-owned access sheet.
// Presenting this content does not request any system or player permission.
struct PlaybackAccessContent: View {
    @ObservedObject var studio: Studio
    @Binding var playerRequest: Provider?
    @State private var message: String?

    var body: some View {
        VStack(alignment: .leading, spacing: 15) {
            Text("Allow System Audio Recording to feel music from other apps. Local files work without capture permission.")
            HStack {
                Button(studio.audioAccessHealth.failure != nil ? "Retry Audio Access" : studio.audioAccessReady ? "Check Audio Access" : "Allow System Audio…") {
                    message = nil
                    Task {
                        _ = await studio.prepareAudioAccess()
                    }
                }.disabled(studio.requestingAudioAccess || playerRequest != nil)
                if studio.requestingAudioAccess { ProgressView().controlSize(.small) }
            }
            Text(studio.audioAccessHealth.summary(setupSaved: studio.audioAccessReady))
                .font(.callout).foregroundStyle(.secondary)
            if let failure = studio.audioAccessHealth.failure {
                Text(failure).font(.callout)
                Text("To resume automatic listening, fix access and choose Retry Audio Access. Local files remain available.")
                    .font(.callout).foregroundStyle(.secondary)
            }
            Divider()
            Text("Optional player details").font(.headline)
            Text("Connect a player to show the current title, cover, and progress. Open the player first, then connect it here.")
                .foregroundStyle(.secondary)
            HStack {
                ForEach(Provider.allCases, id: \.self) { player in
                    Button("Connect " + player.rawValue) {
                        guard let app = NSRunningApplication.runningApplications(withBundleIdentifier: player.bundle).first else {
                            message = "Open " + player.appName + ", then try again."
                            return
                        }
                        playerRequest = player
                        message = nil
                        let pid = app.processIdentifier
                        Task {
                            let status = await Task.detached(priority: .userInitiated) {
                                PlaybackAccess.playerStatus(pid, ask: true)
                            }.value
                            message = status == noErr ? player.rawValue + " connected." :
                                "Access to " + player.rawValue + " is off. You can change it in Privacy & Security → Automation."
                            playerRequest = nil
                        }
                    }.disabled(studio.requestingAudioAccess || playerRequest != nil)
                }
                if playerRequest != nil { ProgressView().controlSize(.small) }
            }
            if let message { Text(message).font(.callout).foregroundStyle(.secondary) }
            Button("Privacy Settings…", action: studio.permissions)
        }
        .font(.system(size: 14))
        .fixedSize(horizontal: false, vertical: true)
    }
}

struct PlaybackAccessSheet: View {
    @ObservedObject var studio: Studio
    @Environment(\.dismiss) private var dismiss
    @State private var playerRequest: Provider?

    var body: some View {
        VStack(alignment: .leading, spacing: 18) {
            Text("Playback Access").font(.title2.weight(.semibold))
            PlaybackAccessContent(studio: studio, playerRequest: $playerRequest)
            HStack {
                Spacer()
                Button("Done") { dismiss() }.keyboardShortcut(.defaultAction)
                    .disabled(studio.requestingAudioAccess || playerRequest != nil)
            }
        }.padding(24).frame(width: 480)
            .interactiveDismissDisabled(studio.requestingAudioAccess || playerRequest != nil)
    }
}
