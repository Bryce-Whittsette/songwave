import AppKit
import CoreAudio
import CoreServices
import SwiftUI

struct PlayerConnectionControls: View {
    @ObservedObject var studio: Studio
    @Binding var playerRequest: Provider?
    @State private var message: String?

    var body: some View {
        VStack(alignment: .leading, spacing: 15) {
            Text("Optional player details").font(.headline).accessibilityAddTraits(.isHeader).accessibilityHeading(.h2)
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
            Button("Automation Settings…", action: studio.automationSettings)
                .accessibilityIdentifier("recovery.player.privacy")
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
    @Environment(\.accessibilityReduceMotion) private var systemReduceMotion
    @Environment(\.songWaveAdditionalMotionReduction) private var additionalMotionReduction
    private var reduceMotion: Bool { AccessibleMotion.reduced(system: systemReduceMotion, additional: additionalMotionReduction) }
    @Environment(\.dismiss) private var dismiss
    @State private var playerRequest: Provider?
    var body: some View {
        VStack(alignment: .leading, spacing: 18) {
            Text(studio.firstSuccessPending && !studio.audioAccessReady && studio.firstSuccess.phase != .recovery ? "Connect Mac audio" : studio.verifyingSetup && studio.firstSuccess.phase != .recovery ? "Make your first connection" : "Listening help")
                .font(.title2.weight(.semibold)).accessibilityAddTraits(.isHeader).accessibilityHeading(.h1).accessibilityIdentifier("support.heading")
            ScrollView { PlaybackAccessContent(studio: studio, playerRequest: $playerRequest).frame(maxWidth: .infinity, alignment: .leading).padding(1) }
                .frame(maxHeight: 540)
            HStack {
                Spacer()
                Button(studio.verifyingSetup || studio.firstSuccessPending ? "Continue without confirmation" : "Done") {
                    if studio.verifyingSetup || studio.firstSuccessPending { studio.completeFirstSuccess() }
                    dismiss()
                }.keyboardShortcut(.cancelAction).accessibilityIdentifier("support.done")
                    .disabled(studio.requestingAudioAccess || playerRequest != nil || studio.testingTrackpad)
            }
        }.padding(24).frame(width: 530)
            .transaction { AccessibleMotion.apply(to: &$0, reduced: reduceMotion) }
            .interactiveDismissDisabled(studio.requestingAudioAccess || playerRequest != nil || studio.testingTrackpad)
    }
}
