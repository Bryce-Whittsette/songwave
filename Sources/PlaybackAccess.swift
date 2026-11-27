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

struct PlayerConnectionControls: View {
    @ObservedObject var studio: Studio
    @Binding var playerRequest: Provider?
    @State private var message: String?

    var body: some View {
        VStack(alignment: .leading, spacing: 15) {
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

struct PlaybackAccessContent: View {
    @ObservedObject var studio: Studio
    @Binding var playerRequest: Provider?
    @State private var visualOwner = UUID()
    var body: some View {
      Group {
        if studio.firstSuccessPending && !studio.audioAccessReady && studio.firstSuccess.phase != .recovery {
            AudioSetupContent(studio: studio)
        } else if studio.verifyingSetup && studio.firstSuccess.phase != .recovery {
            FirstSuccessContent(studio: studio)
        } else {
            RecoveryContent(studio: studio, playerRequest: $playerRequest)
        }
      }
      .background { PlayerWindowVisibility { studio.display.setVisible($0, owner: visualOwner) } }
      .onDisappear {
          studio.display.setVisible(false, owner: visualOwner)
          if studio.testingTrackpad { studio.finishPlaybackAccess() }
      }
    }
}

struct PlaybackAccessSheet: View {
    @ObservedObject var studio: Studio
    @Environment(\.dismiss) private var dismiss
    @State private var playerRequest: Provider?
    var body: some View {
        VStack(alignment: .leading, spacing: 18) {
            Text(studio.firstSuccessPending && !studio.audioAccessReady && studio.firstSuccess.phase != .recovery ? "Connect Mac audio" : studio.verifyingSetup && studio.firstSuccess.phase != .recovery ? "Make your first connection" : "Listening help")
                .font(.title2.weight(.semibold)).accessibilityAddTraits(.isHeader)
            ScrollView { PlaybackAccessContent(studio: studio, playerRequest: $playerRequest).frame(maxWidth: .infinity, alignment: .leading).padding(1) }
                .frame(maxHeight: 540)
            HStack {
                Spacer()
                Button(studio.verifyingSetup || studio.firstSuccessPending ? "Continue without confirmation" : "Done") {
                    if studio.verifyingSetup || studio.firstSuccessPending { studio.completeFirstSuccess() }
                    dismiss()
                }.keyboardShortcut(.cancelAction)
                    .disabled(studio.requestingAudioAccess || playerRequest != nil || studio.testingTrackpad)
            }
        }.padding(24).frame(width: 530)
            .interactiveDismissDisabled(studio.requestingAudioAccess || playerRequest != nil || studio.testingTrackpad)
    }
}
