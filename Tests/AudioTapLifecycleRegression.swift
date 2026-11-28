import CoreAudio
import Foundation

struct GlassError: LocalizedError { let errorDescription: String?; init(_ text: String) { errorDescription = text } }

// SDK boundary replacements exercise the production AudioTap ownership and
// notification code without opening devices, recording or changing the route.
enum FakeHAL {
    static var fail = ""
    static var createdTap = 0, destroyedTap = 0, createdAggregate = 0, destroyedAggregate = 0
    static var createdCallback = 0, destroyedCallback = 0, started = 0, stopped = 0
    static var watches: [(AudioObjectID, AudioObjectPropertyAddress, AudioObjectPropertyListenerBlock)] = []
    static var rateOnStart: Double?
    static var muteWrites = 0
    static var rate = 48000.0
    static var channels: UInt32 = 2, bits: UInt32 = 32, frameBytes: UInt32 = 8, packetFrames: UInt32 = 1
    static var flags: AudioFormatFlags = kAudioFormatFlagIsFloat
    static func reset(_ failure: String = "") {
        fail = failure; createdTap = 0; destroyedTap = 0; createdAggregate = 0; destroyedAggregate = 0
        createdCallback = 0; destroyedCallback = 0; started = 0; stopped = 0; watches = []; rate = 48000; rateOnStart = nil
        channels = 2; bits = 32; frameBytes = 8; packetFrames = 1; flags = kAudioFormatFlagIsFloat; muteWrites = 0
    }
    static func format() -> AudioStreamBasicDescription {
        AudioStreamBasicDescription(mSampleRate: rate, mFormatID: kAudioFormatLinearPCM,
            mFormatFlags: flags, mBytesPerPacket: frameBytes, mFramesPerPacket: packetFrames,
            mBytesPerFrame: frameBytes, mChannelsPerFrame: channels, mBitsPerChannel: bits, mReserved: 0)
    }
    static func notify(_ selector: AudioObjectPropertySelector) {
        let current = watches
        for (_, var address, listener) in current where address.mSelector == selector {
            withUnsafePointer(to: &address) { listener(1, $0) }
        }
    }
}
@discardableResult func AudioHardwareCreateProcessTap(_ description: CATapDescription, _ id: UnsafeMutablePointer<AudioObjectID>) -> OSStatus {
    if FakeHAL.fail == "tap" { return -1 }; id.pointee = 101; FakeHAL.createdTap += 1; return noErr
}
@discardableResult func AudioHardwareDestroyProcessTap(_ id: AudioObjectID) -> OSStatus { FakeHAL.destroyedTap += 1; return noErr }
@discardableResult func AudioHardwareCreateAggregateDevice(_ description: CFDictionary, _ id: UnsafeMutablePointer<AudioObjectID>) -> OSStatus {
    if FakeHAL.fail == "aggregate" { return -1 }; id.pointee = 201; FakeHAL.createdAggregate += 1; return noErr
}
@discardableResult func AudioHardwareDestroyAggregateDevice(_ id: AudioObjectID) -> OSStatus { FakeHAL.destroyedAggregate += 1; return noErr }
@discardableResult func AudioDeviceCreateIOProcIDWithBlock(_ proc: UnsafeMutablePointer<AudioDeviceIOProcID?>, _ id: AudioObjectID,
                                      _ queue: DispatchQueue?, _ block: @escaping AudioDeviceIOBlock) -> OSStatus {
    if FakeHAL.fail == "callback" { return -1 }
    proc.pointee = { _, _, _, _, _, _, _ in noErr }; FakeHAL.createdCallback += 1; return noErr
}
@discardableResult func AudioDeviceDestroyIOProcID(_ id: AudioObjectID, _ proc: AudioDeviceIOProcID) -> OSStatus { FakeHAL.destroyedCallback += 1; return noErr }
@discardableResult func AudioDeviceStart(_ id: AudioObjectID, _ proc: AudioDeviceIOProcID?) -> OSStatus {
    if FakeHAL.fail == "start" { return -1 }; FakeHAL.started += 1
    if let changed = FakeHAL.rateOnStart { FakeHAL.rate = changed }
    return noErr
}
@discardableResult func AudioDeviceStop(_ id: AudioObjectID, _ proc: AudioDeviceIOProcID?) -> OSStatus { FakeHAL.stopped += 1; return noErr }
@discardableResult func AudioObjectGetPropertyData(_ id: AudioObjectID, _ address: UnsafePointer<AudioObjectPropertyAddress>,
                               _ qualifierSize: UInt32, _ qualifier: UnsafeRawPointer?,
                               _ size: UnsafeMutablePointer<UInt32>, _ data: UnsafeMutableRawPointer) -> OSStatus {
    if address.pointee.mSelector == kAudioTapPropertyFormat {
        if FakeHAL.fail == "format" { return -1 }
        data.assumingMemoryBound(to: AudioStreamBasicDescription.self).pointee = FakeHAL.format()
    } else if address.pointee.mSelector == kAudioHardwarePropertyDefaultOutputDevice {
        data.assumingMemoryBound(to: AudioObjectID.self).pointee = 82
    } else { return -1 }
    return noErr
}
@discardableResult func AudioObjectAddPropertyListenerBlock(_ id: AudioObjectID, _ address: UnsafePointer<AudioObjectPropertyAddress>,
                                        _ queue: DispatchQueue?, _ listener: @escaping AudioObjectPropertyListenerBlock) -> OSStatus {
    if FakeHAL.fail == "watch" { return -1 }
    FakeHAL.watches.append((id, address.pointee, listener)); return noErr
}
@discardableResult func AudioObjectRemovePropertyListenerBlock(_ id: AudioObjectID, _ address: UnsafePointer<AudioObjectPropertyAddress>,
                                           _ queue: DispatchQueue?, _ listener: @escaping AudioObjectPropertyListenerBlock) -> OSStatus {
    if let index = FakeHAL.watches.firstIndex(where: { $0.0 == id && $0.1.mSelector == address.pointee.mSelector }) { FakeHAL.watches.remove(at: index) }
    return noErr
}
@discardableResult func AudioObjectSetPropertyData(_ id: AudioObjectID, _ address: UnsafePointer<AudioObjectPropertyAddress>,
                               _ qualifierSize: UInt32, _ qualifier: UnsafeRawPointer?, _ size: UInt32, _ data: UnsafeRawPointer) -> OSStatus {
    FakeHAL.muteWrites += 1
    return FakeHAL.fail == "mute" ? -1 : noErr
}

@main struct AudioTapLifecycleRegression {
    static func formatEdges() throws {
        for rate in [8000.0, 11025, 16000, 22050, 24000, 32000, 44100, 48000, 88200, 96000, 176400, 192000, 352800, 384000, 705600, 768000] {
            FakeHAL.reset(); FakeHAL.rate = rate
            var tap: AudioTap? = try AudioTap(description: CATapDescription(stereoMixdownOfProcesses: [111]), mute: false)
            precondition(tap?.rate == rate)
            tap = nil
            precondition(FakeHAL.createdTap == FakeHAL.destroyedTap && FakeHAL.watches.isEmpty)
        }
        func rejects() {
            do { _ = try AudioTap(description: CATapDescription(stereoMixdownOfProcesses: [111]), mute: false); preconditionFailure("Invalid PCM format was accepted") } catch {}
            precondition(FakeHAL.createdTap == FakeHAL.destroyedTap && FakeHAL.createdAggregate == 0)
        }
        for rate in [0.0, -1, 7999, 768001, Double.nan, Double.infinity, Double.greatestFiniteMagnitude] {
            FakeHAL.reset(); FakeHAL.rate = rate; rejects()
        }
        for channels: UInt32 in [0, 3, UInt32.max] { FakeHAL.reset(); FakeHAL.channels = channels; rejects() }
        for bytes: UInt32 in [0, 1, 4, 7, 16, UInt32.max] { FakeHAL.reset(); FakeHAL.frameBytes = bytes; rejects() }
        FakeHAL.reset(); FakeHAL.bits = 16; rejects()
        FakeHAL.reset(); FakeHAL.packetFrames = 2; rejects()
        FakeHAL.reset(); FakeHAL.flags |= kAudioFormatFlagIsBigEndian; rejects()
        FakeHAL.reset(); FakeHAL.flags |= kAudioFormatFlagIsSignedInteger; rejects()
        FakeHAL.reset(); FakeHAL.flags = 0; rejects()
        FakeHAL.reset(); FakeHAL.flags |= kAudioFormatFlagIsNonInterleaved; FakeHAL.frameBytes = 4
        var planar: AudioTap? = try AudioTap(description: CATapDescription(stereoMixdownOfProcesses: [111]), mute: false)
        precondition(planar != nil); planar = nil
        print("16 valid rates from 8–768 kHz, planar Float32 and malformed/nonfinite/out-of-range format metadata passed at the real capture boundary.")
    }
    static func main() throws {
        try formatEdges()
        for failure in ["tap", "format", "aggregate", "callback", "start", "watch"] {
            FakeHAL.reset(failure)
            do { _ = try AudioTap(description: CATapDescription(stereoMixdownOfProcesses: [111]), mute: false); preconditionFailure("Injected SDK failure was ignored") } catch {}
            precondition(FakeHAL.createdTap == FakeHAL.destroyedTap, "A failed initialization leaked a tap")
            precondition(FakeHAL.createdAggregate == FakeHAL.destroyedAggregate, "A failed initialization leaked an aggregate")
            precondition(FakeHAL.createdCallback == FakeHAL.destroyedCallback, "A failed initialization leaked an I/O proc")
            precondition(FakeHAL.started == FakeHAL.stopped && FakeHAL.watches.isEmpty)
        }
        FakeHAL.reset()
        var tap: AudioTap? = try AudioTap(description: CATapDescription(stereoMixdownOfProcesses: [111]), mute: false)
        precondition(FakeHAL.watches.count == 3 && !tap!.needsReconnect)
        FakeHAL.notify(kAudioTapPropertyFormat)
        precondition(!tap!.needsReconnect, "An unchanged format notification must not cause reconnect loops")
        FakeHAL.rate = 44100
        FakeHAL.notify(kAudioTapPropertyFormat)
        precondition(tap!.needsReconnect, "A changed tap format must request a rebuild")
        do { try tap!.setMuted(true); preconditionFailure("A stale tap newly muted speakers") } catch {}
        precondition(FakeHAL.muteWrites == 0, "A stale tap reached the HAL muting setter")
        tap = nil
        precondition(FakeHAL.watches.isEmpty && FakeHAL.createdTap == FakeHAL.destroyedTap)
        for selector in [kAudioHardwarePropertyDefaultOutputDevice, kAudioDevicePropertyNominalSampleRate] {
            FakeHAL.reset()
            var route: AudioTap? = try AudioTap(description: CATapDescription(stereoMixdownOfProcesses: [111]), mute: false)
            FakeHAL.notify(selector)
            precondition(route!.needsReconnect)
            route = nil
            precondition(FakeHAL.watches.isEmpty && FakeHAL.createdAggregate == FakeHAL.destroyedAggregate)
        }
        FakeHAL.reset(); FakeHAL.rateOnStart = 44100
        var changedDuringStart: AudioTap? = try AudioTap(description: CATapDescription(stereoMixdownOfProcesses: [111]), mute: false)
        precondition(changedDuringStart!.needsReconnect, "A format change during startup was missed before listener registration")
        changedDuringStart = nil
        precondition(FakeHAL.createdTap == FakeHAL.destroyedTap && FakeHAL.watches.isEmpty)
        print("Real AudioTap releases resources at every injected SDK failure, removes listeners, ignores unchanged format notifications and flags route/rate changes.")
    }
}
