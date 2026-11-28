import CoreAudio
import Foundation

// Compile-time SDK replacements, never runtime interposition. The unmodified
// AudioTap/SampleRing, router, Playback and Studio run above this boundary.
// No real device, TCC service, installed app, recording or phone call is used.
enum InterruptionHAL {
    struct Client { var bundle: String; var input: UInt32 = 0; var output: UInt32 = 1 }
    struct Tap { var uuid: String; var processes: [AudioObjectID]; var muted: Bool }
    struct Callback { var block: AudioDeviceIOBlock; var running = false }
    enum Delivery { case music, stopped, zeros }
    static let lock = NSLock()
    static var clients: [AudioObjectID: Client] = [:]
    static var taps: [AudioObjectID: Tap] = [:]
    static var aggregates: [AudioObjectID: AudioObjectID] = [:]
    static var callbacks: [AudioObjectID: Callback] = [:]
    static var listeners: [(AudioObjectID, AudioObjectPropertyAddress, AudioObjectPropertyListenerBlock)] = []
    static var allowed = true
    static var delivery = Delivery.music
    static var invalidFormat = false
    static var denyRoutingChanges = false
    static var nextID: AudioObjectID = 1000
    static var attempts = 0
    static var denied = 0
    static var opened = 0
    static var closed = 0
    static var motors = 0
    static var writes: [(time: Double, level: Double)] = []
    static var timer: DispatchSourceTimer?
    static var frames = 0
    static var speakerFrames = 0
    static var callbackGate: DispatchSemaphore?
    static var callbackEntries = 0
    static func locked<T>(_ body: () -> T) -> T { lock.lock(); defer { lock.unlock() }; return body() }
    static var counts: (taps: Int, muted: Int, callbacks: Int, listeners: Int, motors: Int, attempts: Int, denied: Int) {
        locked { (taps.count, taps.values.filter(\.muted).count, callbacks.count, listeners.count, motors, attempts, denied) }
    }
    static var packets: [(time: Double, level: Double)] { locked { writes } }
    static func setClients(_ value: [AudioObjectID: Client]) { locked { clients = value } }
    static func grant() { locked { allowed = true; delivery = .music; invalidFormat = false; denyRoutingChanges = false } }
    static func revoke(_ mode: Delivery, invalidate: Bool = false) {
        let watches = locked {
            allowed = false; delivery = mode; invalidFormat = invalidate
            return invalidate ? listeners : []
        }
        for (_, var address, listener) in watches where address.mSelector == kAudioTapPropertyFormat {
            withUnsafePointer(to: &address) { listener(1, $0) }
        }
    }
    static func begin() {
        let source = DispatchSource.makeTimerSource(queue: DispatchQueue(label: "songwave.interruption-fixture"))
        source.schedule(deadline: .now(), repeating: .milliseconds(8))
        source.setEventHandler { pump() }
        timer = source; source.resume()
    }
    static func finish() { timer?.cancel(); timer = nil }
    static func pump() {
        let state = locked { () -> (Int, Delivery, [AudioDeviceIOBlock]) in
            let start = frames; frames += 384
            if clients.values.contains(where: { $0.output != 0 && !$0.bundle.contains("FaceTime") }) { speakerFrames += 384 }
            let active = callbacks.filter { $0.value.running }.compactMap { aggregate, callback -> AudioDeviceIOBlock? in
                guard let tap = aggregates[aggregate].flatMap({ taps[$0] }),
                      tap.processes.isEmpty || tap.processes.contains(where: { clients[$0]?.output == 1 }) else { return nil }
                return callback.block
            }
            return (start, delivery, active)
        }
        guard state.1 != .stopped, !state.2.isEmpty else { return }
        var samples = [Float](repeating: 0, count: 768)
        if state.1 == .music {
            for frame in 0..<384 {
                let t = Double(state.0 + frame) / 48_000
                let voice = (1...8).reduce(0.0) { $0 + 0.045 / Double($1) * sin(2 * .pi * 224 * Double($1) * t) }
                let value = Float(0.18 * sin(2 * .pi * 65 * t) + voice)
                samples[frame * 2] = value; samples[frame * 2 + 1] = value
            }
        }
        samples.withUnsafeMutableBytes { bytes in
            var input = AudioBufferList(mNumberBuffers: 1, mBuffers: AudioBuffer(mNumberChannels: 2,
                mDataByteSize: UInt32(bytes.count), mData: bytes.baseAddress))
            var output = AudioBufferList(mNumberBuffers: 0, mBuffers: AudioBuffer())
            var time = AudioTimeStamp()
            withUnsafePointer(to: &time) { stamp in
                withUnsafePointer(to: &input) { buffer in
                    withUnsafeMutablePointer(to: &output) { out in
                        for block in state.2 { block(stamp, buffer, stamp, out, stamp) }
                    }
                }
            }
        }
    }
}

@discardableResult func AudioHardwareCreateProcessTap(_ description: CATapDescription, _ id: UnsafeMutablePointer<AudioObjectID>) -> OSStatus {
    InterruptionHAL.locked {
        InterruptionHAL.attempts += 1
        guard InterruptionHAL.allowed else { InterruptionHAL.denied += 1; return kAudioDevicePermissionsError }
        InterruptionHAL.nextID += 1; id.pointee = InterruptionHAL.nextID
        InterruptionHAL.taps[id.pointee] = .init(uuid: description.uuid.uuidString,
            processes: description.processes, muted: description.muteBehavior != .unmuted)
        InterruptionHAL.opened += 1
        return noErr
    }
}
@discardableResult func AudioHardwareDestroyProcessTap(_ id: AudioObjectID) -> OSStatus {
    InterruptionHAL.locked { if InterruptionHAL.taps.removeValue(forKey: id) != nil { InterruptionHAL.closed += 1 }; return noErr }
}
@discardableResult func AudioHardwareCreateAggregateDevice(_ description: CFDictionary, _ id: UnsafeMutablePointer<AudioObjectID>) -> OSStatus {
    InterruptionHAL.locked {
        let dictionary = description as NSDictionary
        guard let list = dictionary[kAudioAggregateDeviceTapListKey] as? [[String: Any]],
              let uuid = list.first?[kAudioSubTapUIDKey] as? String,
              let tap = InterruptionHAL.taps.first(where: { $0.value.uuid == uuid })?.key else { return -1 }
        InterruptionHAL.nextID += 1; id.pointee = InterruptionHAL.nextID
        InterruptionHAL.aggregates[id.pointee] = tap; return noErr
    }
}
@discardableResult func AudioHardwareDestroyAggregateDevice(_ id: AudioObjectID) -> OSStatus {
    InterruptionHAL.locked { InterruptionHAL.aggregates.removeValue(forKey: id); return noErr }
}
@discardableResult func AudioDeviceCreateIOProcIDWithBlock(_ proc: UnsafeMutablePointer<AudioDeviceIOProcID?>, _ id: AudioObjectID,
                                      _ queue: DispatchQueue?, _ block: @escaping AudioDeviceIOBlock) -> OSStatus {
    let gate = InterruptionHAL.locked { InterruptionHAL.callbackEntries += 1; return InterruptionHAL.callbackGate }
    gate?.wait()
    return InterruptionHAL.locked {
        proc.pointee = { _, _, _, _, _, _, _ in noErr }
        InterruptionHAL.callbacks[id] = .init(block: block); return noErr
    }
}
@discardableResult func AudioDeviceDestroyIOProcID(_ id: AudioObjectID, _ proc: AudioDeviceIOProcID) -> OSStatus {
    InterruptionHAL.locked { InterruptionHAL.callbacks.removeValue(forKey: id); return noErr }
}
@discardableResult func AudioDeviceStart(_ id: AudioObjectID, _ proc: AudioDeviceIOProcID?) -> OSStatus {
    InterruptionHAL.locked { InterruptionHAL.callbacks[id]?.running = true; return noErr }
}
@discardableResult func AudioDeviceStop(_ id: AudioObjectID, _ proc: AudioDeviceIOProcID?) -> OSStatus {
    InterruptionHAL.locked { InterruptionHAL.callbacks[id]?.running = false; return noErr }
}
@discardableResult func AudioObjectGetPropertyDataSize(_ id: AudioObjectID, _ address: UnsafePointer<AudioObjectPropertyAddress>,
                               _ qualifierSize: UInt32, _ qualifier: UnsafeRawPointer?, _ size: UnsafeMutablePointer<UInt32>) -> OSStatus {
    InterruptionHAL.locked {
        guard address.pointee.mSelector == kAudioHardwarePropertyProcessObjectList else { return -1 }
        size.pointee = UInt32(InterruptionHAL.clients.count * MemoryLayout<AudioObjectID>.stride); return noErr
    }
}
@discardableResult func AudioObjectGetPropertyData(_ id: AudioObjectID, _ address: UnsafePointer<AudioObjectPropertyAddress>,
                               _ qualifierSize: UInt32, _ qualifier: UnsafeRawPointer?,
                               _ size: UnsafeMutablePointer<UInt32>, _ data: UnsafeMutableRawPointer) -> OSStatus {
    InterruptionHAL.locked {
        switch address.pointee.mSelector {
        case kAudioHardwarePropertyProcessObjectList:
            let values = Array(InterruptionHAL.clients.keys).sorted()
            guard Int(size.pointee) >= values.count * MemoryLayout<AudioObjectID>.stride else { return kAudioHardwareBadPropertySizeError }
            values.withUnsafeBytes { if let base = $0.baseAddress, !$0.isEmpty { data.copyMemory(from: base, byteCount: $0.count) } }
            size.pointee = UInt32(values.count * MemoryLayout<AudioObjectID>.stride)
        case kAudioTapPropertyFormat:
            guard !InterruptionHAL.invalidFormat else { return kAudioDevicePermissionsError }
            data.assumingMemoryBound(to: AudioStreamBasicDescription.self).pointee = AudioStreamBasicDescription(
                mSampleRate: 48000, mFormatID: kAudioFormatLinearPCM, mFormatFlags: kAudioFormatFlagIsFloat,
                mBytesPerPacket: 8, mFramesPerPacket: 1, mBytesPerFrame: 8, mChannelsPerFrame: 2, mBitsPerChannel: 32, mReserved: 0)
        case kAudioHardwarePropertyDefaultOutputDevice: data.assumingMemoryBound(to: AudioObjectID.self).pointee = 82
        default:
            guard let client = InterruptionHAL.clients[id] else { return -1 }
            switch address.pointee.mSelector {
            case kAudioProcessPropertyIsRunningOutput: data.assumingMemoryBound(to: UInt32.self).pointee = client.output
            case kAudioProcessPropertyIsRunningInput: data.assumingMemoryBound(to: UInt32.self).pointee = client.input
            case kAudioProcessPropertyPID: data.assumingMemoryBound(to: pid_t.self).pointee = pid_t(500000 + id)
            case kAudioProcessPropertyBundleID: data.assumingMemoryBound(to: Unmanaged<CFString>?.self).pointee = .passRetained(client.bundle as CFString)
            default: return -1
            }
        }
        return noErr
    }
}
@discardableResult func AudioObjectAddPropertyListenerBlock(_ id: AudioObjectID, _ address: UnsafePointer<AudioObjectPropertyAddress>,
                                        _ queue: DispatchQueue?, _ listener: @escaping AudioObjectPropertyListenerBlock) -> OSStatus {
    InterruptionHAL.locked { InterruptionHAL.listeners.append((id, address.pointee, listener)); return noErr }
}
@discardableResult func AudioObjectRemovePropertyListenerBlock(_ id: AudioObjectID, _ address: UnsafePointer<AudioObjectPropertyAddress>,
                                           _ queue: DispatchQueue?, _ listener: @escaping AudioObjectPropertyListenerBlock) -> OSStatus {
    InterruptionHAL.locked {
        if let i = InterruptionHAL.listeners.firstIndex(where: { $0.0 == id && $0.1.mSelector == address.pointee.mSelector }) { InterruptionHAL.listeners.remove(at: i) }
        return noErr
    }
}
@discardableResult func AudioObjectSetPropertyData(_ id: AudioObjectID, _ address: UnsafePointer<AudioObjectPropertyAddress>,
                               _ qualifierSize: UInt32, _ qualifier: UnsafeRawPointer?, _ size: UInt32, _ data: UnsafeRawPointer) -> OSStatus {
    InterruptionHAL.locked {
        guard !InterruptionHAL.denyRoutingChanges else { return kAudioDevicePermissionsError }
        let description = data.assumingMemoryBound(to: Unmanaged<CATapDescription>.self).pointee.takeUnretainedValue()
        InterruptionHAL.taps[id]?.muted = description.muteBehavior != .unmuted; return noErr
    }
}
