import AppKit
import CoreAudio
import CoreServices

enum PlaybackAccess {
    static func requestAudio(timeout: Duration = .seconds(60)) async throws {
        // This opens output capture only. It is not proof that permission was
        // granted or audio was received; first-success verification checks that.
        guard let request = CaptureRequest(description: {
            let excluded = AudioHardware.processList().filter { process in
                var pid: pid_t = 0
                return AudioHardware.read(process, kAudioProcessPropertyPID, into: &pid) == noErr && pid == getpid()
            }
            return CATapDescription(stereoGlobalTapButExcludeProcesses: excluded)
        }, mute: false) else { throw CaptureRequest.Failure.busy }
        withExtendedLifetime(try await request.wait(timeout: timeout)) {}
    }

    static func playerStatus(_ pid: pid_t, ask: Bool) -> OSStatus {
        let target = NSAppleEventDescriptor(processIdentifier: pid)
        return AEDeterminePermissionToAutomateTarget(target.aeDesc, 0x636f7265, 0x67657464, ask)
    }
}
