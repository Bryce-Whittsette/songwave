import AppKit
import CoreAudio
import CoreServices

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

