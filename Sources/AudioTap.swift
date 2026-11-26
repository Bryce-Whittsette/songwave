import CoreAudio
import AudioToolbox
import Foundation
import os

enum AudioHardware {
    static let system = AudioObjectID(kAudioObjectSystemObject)

    static func read<T>(_ object: AudioObjectID, _ selector: AudioObjectPropertySelector, into value: inout T) -> OSStatus {
        var address = AudioObjectPropertyAddress(mSelector: selector,
            mScope: kAudioObjectPropertyScopeGlobal, mElement: kAudioObjectPropertyElementMain)
        var size = UInt32(MemoryLayout<T>.size)
        return withUnsafeMutablePointer(to: &value) {
            AudioObjectGetPropertyData(object, &address, 0, nil, &size, $0)
        }
    }

    static func processList() -> [AudioObjectID] {
        var address = AudioObjectPropertyAddress(mSelector: kAudioHardwarePropertyProcessObjectList,
            mScope: kAudioObjectPropertyScopeGlobal, mElement: kAudioObjectPropertyElementMain)
        var size: UInt32 = 0
        guard AudioObjectGetPropertyDataSize(system, &address, 0, nil, &size) == noErr, size > 0 else { return [] }
        let stride = MemoryLayout<AudioObjectID>.stride
        var objects = Array(repeating: AudioObjectID(0), count: Int(size) / stride)
        let result = objects.withUnsafeMutableBytes {
            AudioObjectGetPropertyData(system, &address, 0, nil, &size, $0.baseAddress!)
        }
        guard result == noErr else { return [] }
        return Array(objects.prefix(Int(size) / stride))
    }

    static func processIDs(for bundle: String, appPath: String) -> [AudioObjectID] {
        processList().filter { object in
            var identifier: Unmanaged<CFString>?
            if read(object, kAudioProcessPropertyBundleID, into: &identifier) == noErr,
               let identifier = identifier?.takeRetainedValue() as String?,
               identifier == bundle || identifier.hasPrefix(bundle + ".") {
                return true
            }
            var pid: pid_t = 0
            guard read(object, kAudioProcessPropertyPID, into: &pid) == noErr, pid > 0 else { return false }
            var path = [CChar](repeating: 0, count: Int(MAXPATHLEN) * 4)
            guard proc_pidpath(pid, &path, UInt32(path.count)) > 0 else { return false }
            return String(cString: path).hasPrefix(appPath + "/")
        }
    }
}

// The audio callback only moves PCM into bounded memory. It never drives the motor.
final class SampleRing {
    private let lock = OSAllocatedUnfairLock()
    private var samples = [Float](repeating: 0, count: 32_768)
    private var writeIndex = 0
    private var count = 0

    func push(_ input: UnsafePointer<AudioBufferList>) {
        let buffers = UnsafeMutableAudioBufferListPointer(UnsafeMutablePointer(mutating: input))
        guard let first = buffers.first, first.mData != nil, first.mNumberChannels > 0,
              lock.lockIfAvailable() else { return }
        defer { lock.unlock() }

        let channels = Int(first.mNumberChannels)
        let values = first.mData!.assumingMemoryBound(to: Float.self)
        let frames = Int(first.mDataByteSize) / MemoryLayout<Float>.stride / channels
        if channels == 1, buffers.count >= 2, let second = buffers[1].mData,
           buffers[1].mDataByteSize >= first.mDataByteSize {
            let right = second.assumingMemoryBound(to: Float.self)
            for frame in 0..<frames { add(fold(values[frame], right[frame])) }
        } else {
            for frame in 0..<frames {
                let i = frame * channels
                add(channels > 1 ? fold(values[i], values[i + 1]) : values[i])
            }
        }
    }

    private func add(_ sample: Float) {
        samples[writeIndex] = sample
        writeIndex = (writeIndex + 1) % samples.count
        count = min(count + 1, samples.count)
    }

    func takeNewest(maximum: Int, into destination: inout [Float]) {
        destination.removeAll(keepingCapacity: true)
        lock.lock()
        defer { lock.unlock() }
        let length = min(count, max(0, maximum))
        let start = (writeIndex - length + samples.count) % samples.count
        for offset in 0..<length { destination.append(samples[(start + offset) % samples.count]) }
        count = 0
    }
}

func fold(_ left: Float, _ right: Float) -> Float {
    let mid = (left + right) * 0.5
    return abs(mid) < abs(left) * 0.2 ? left * 0.5 : mid
}

// Core Audio aggregate setup follows Apple's process tap sample and AudioCap.
// See Resources/AUDIOCAP-LICENSE.txt.
final class AudioTap {
    let ring = SampleRing()
    let rate: Double
    private let description: CATapDescription
    private let tap: AudioObjectID
    private var aggregate = AudioObjectID(kAudioObjectUnknown)
    private var callback: AudioDeviceIOProcID?
    private var running = false
    private let ioQueue = DispatchQueue(label: "songwave.capture", qos: .userInteractive)

    init(description: CATapDescription, mute: Bool) throws {
        self.description = description
        description.name = "SongWave"
        description.uuid = UUID()
        description.isPrivate = true
        description.muteBehavior = mute ? .mutedWhenTapped : .unmuted

        var tap = AudioObjectID(kAudioObjectUnknown)
        try Self.check(AudioHardwareCreateProcessTap(description, &tap), "create the audio tap")
        var format = AudioStreamBasicDescription()
        let formatStatus = AudioHardware.read(tap, kAudioTapPropertyFormat, into: &format)
        guard formatStatus == noErr, format.mSampleRate > 0, format.mBitsPerChannel == 32,
              format.mFormatID == kAudioFormatLinearPCM, format.mFormatFlags & kAudioFormatFlagIsFloat != 0 else {
            AudioHardwareDestroyProcessTap(tap)
            throw GlassError("macOS did not provide a usable audio format.")
        }
        self.tap = tap
        rate = format.mSampleRate
        // A tap-only aggregate exposes the captured mix as its sole input, including
        // when the default output is a duplex USB device with microphone channels.
        let configuration: [String: Any] = [
            kAudioAggregateDeviceNameKey: "SongWave Process Tap",
            kAudioAggregateDeviceUIDKey: UUID().uuidString,
            kAudioAggregateDeviceIsPrivateKey: true,
            kAudioAggregateDeviceIsStackedKey: false,
            kAudioAggregateDeviceTapAutoStartKey: true,
            kAudioAggregateDeviceTapListKey: [[
                kAudioSubTapUIDKey: description.uuid.uuidString,
                kAudioSubTapDriftCompensationKey: true
            ]]
        ]
        try Self.check(AudioHardwareCreateAggregateDevice(configuration as CFDictionary, &aggregate), "prepare audio routing")
        let ring = self.ring
        try Self.check(AudioDeviceCreateIOProcIDWithBlock(&callback, aggregate, ioQueue) { _, input, _, _, _ in
            ring.push(input)
        }, "attach to the audio stream")
        try Self.check(AudioDeviceStart(aggregate, callback), "start the audio tap")
        running = true
    }

    func setMuted(_ mute: Bool) throws {
        let behavior: CATapMuteBehavior = mute ? .mutedWhenTapped : .unmuted
        guard description.muteBehavior != behavior else { return }
        let previous = description.muteBehavior
        description.muteBehavior = behavior
        var address = AudioObjectPropertyAddress(mSelector: kAudioTapPropertyDescription,
            mScope: kAudioObjectPropertyScopeGlobal, mElement: kAudioObjectPropertyElementMain)
        var ref = Unmanaged.passUnretained(description)
        let status = AudioObjectSetPropertyData(tap, &address, 0, nil,
            UInt32(MemoryLayout.size(ofValue: ref)), &ref)
        if status != noErr { description.muteBehavior = previous }
        try Self.check(status, "update speaker routing")
    }

    private static func check(_ status: OSStatus, _ operation: String) throws {
        guard status == noErr else {
            throw GlassError("Couldn’t \(operation) (\(status)). Check System Audio Recording permission, then retry.")
        }
    }

    deinit {
        if running { AudioDeviceStop(aggregate, callback) }
        if let callback { AudioDeviceDestroyIOProcID(aggregate, callback) }
        if aggregate != kAudioObjectUnknown { AudioHardwareDestroyAggregateDevice(aggregate) }
        AudioHardwareDestroyProcessTap(tap)
    }
}
