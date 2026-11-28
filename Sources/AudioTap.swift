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
    private let clock: () -> ContinuousClock.Instant
    private var lastInput: ContinuousClock.Instant?
    private var samples = [Float](repeating: 0, count: 32_768)
    private var writeIndex = 0
    private var count = 0

    init(clock: @escaping () -> ContinuousClock.Instant = { .now }) { self.clock = clock }

    func push(_ input: UnsafePointer<AudioBufferList>) {
        let bufferCount = input.pointee.mNumberBuffers
        guard bufferCount == 1 || bufferCount == 2 else { return }
        let buffers = UnsafeMutableAudioBufferListPointer(UnsafeMutablePointer(mutating: input))
        let first = buffers[0]
        guard (1...2).contains(first.mNumberChannels), Self.validStorage(first) else { return }
        if bufferCount == 2 {
            let right = buffers[1]
            guard first.mNumberChannels == 1, right.mNumberChannels == 1,
                  right.mDataByteSize == first.mDataByteSize, Self.validStorage(right) else { return }
        } else {
            guard Int(first.mDataByteSize) % (MemoryLayout<Float>.stride * Int(first.mNumberChannels)) == 0 else { return }
        }
        guard lock.lockIfAvailable() else { return }
        defer { lock.unlock() }

        let channels = Int(first.mNumberChannels)
        let values = first.mData!.assumingMemoryBound(to: Float.self)
        let frames = Int(first.mDataByteSize) / MemoryLayout<Float>.stride / channels
        guard frames > 0 else { return }
        lastInput = clock()
        // Callback work stays bounded even if HAL supplies a large valid packet.
        let start = max(0, frames - samples.count)
        if bufferCount == 2, let second = buffers[1].mData {
            let right = second.assumingMemoryBound(to: Float.self)
            for frame in start..<frames { add(fold(values[frame], right[frame])) }
        } else {
            for frame in start..<frames {
                let i = frame * channels
                add(channels > 1 ? fold(values[i], values[i + 1]) : values[i])
            }
        }
    }

    private static func validStorage(_ buffer: AudioBuffer) -> Bool {
        guard let pointer = buffer.mData, buffer.mDataByteSize > 0, buffer.mDataByteSize <= 1_048_576 else { return false }
        return Int(bitPattern: pointer) % MemoryLayout<Float>.alignment == 0 &&
            Int(buffer.mDataByteSize) % MemoryLayout<Float>.stride == 0
    }

    private func add(_ sample: Float) {
        // Float PCM is normalized audio. Preserve normal headroom, while keeping
        // NaN/infinity and corrupt outliers out of classifier/filter state.
        samples[writeIndex] = sample.isFinite && abs(sample) <= 16 ? sample : 0
        writeIndex = (writeIndex + 1) % samples.count
        count = min(count + 1, samples.count)
    }

    func takeNewest(maximum: Int, into destination: inout [Float]) {
        destination.removeAll(keepingCapacity: true)
        lock.lock()
        defer { lock.unlock() }
        // Continuous time includes system sleep. PCM retained before a stalled
        // consumer or sleep must not masquerade as fresh music on resume.
        guard let lastInput,
              (.zero ... .milliseconds(200)).contains(lastInput.duration(to: clock())) else {
            count = 0
            return
        }
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
    private let routeQueue = DispatchQueue(label: "songwave.capture-route", qos: .userInitiated)
    private let reconfigure = OSAllocatedUnfairLock(initialState: false)
    private var listeners: [(AudioObjectID, AudioObjectPropertyAddress, AudioObjectPropertyListenerBlock)] = []
    var needsReconnect: Bool { reconfigure.withLock { $0 } }

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
        guard formatStatus == noErr, Self.supports(format) else {
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
        // HAL notifications only mark state; the playback queue owns rebuilding.
        // No extra timer or synchronous property reads are added to rendering.
        try watch(tap, selector: kAudioTapPropertyFormat, expectedFormat: format)
        try watch(AudioHardware.system, selector: kAudioHardwarePropertyDefaultOutputDevice)
        var outputDevice = AudioObjectID(kAudioObjectUnknown)
        if AudioHardware.read(AudioHardware.system, kAudioHardwarePropertyDefaultOutputDevice, into: &outputDevice) == noErr,
           outputDevice != kAudioObjectUnknown {
            try watch(outputDevice, selector: kAudioDevicePropertyNominalSampleRate)
        }
        // A route may change while AudioDeviceStart is waiting, before any
        // listener exists. Recheck once on this startup worker before handoff.
        var current = AudioStreamBasicDescription()
        if AudioHardware.read(tap, kAudioTapPropertyFormat, into: &current) != noErr || !Self.sameFormat(current, format) {
            reconfigure.withLock { $0 = true }
        }
    }

    private static func sameFormat(_ current: AudioStreamBasicDescription, _ expected: AudioStreamBasicDescription) -> Bool {
        current.mSampleRate == expected.mSampleRate && current.mFormatID == expected.mFormatID &&
        current.mFormatFlags == expected.mFormatFlags && current.mBitsPerChannel == expected.mBitsPerChannel &&
        current.mChannelsPerFrame == expected.mChannelsPerFrame && current.mBytesPerFrame == expected.mBytesPerFrame &&
        current.mFramesPerPacket == expected.mFramesPerPacket && current.mBytesPerPacket == expected.mBytesPerPacket
    }

    private static func supports(_ format: AudioStreamBasicDescription) -> Bool {
        guard format.mSampleRate.isFinite, (8000...768000).contains(format.mSampleRate),
              (1...2).contains(format.mChannelsPerFrame), format.mBitsPerChannel == 32,
              format.mFormatID == kAudioFormatLinearPCM, format.mFormatFlags & kAudioFormatFlagIsFloat != 0,
              format.mFormatFlags & (kAudioFormatFlagIsBigEndian | kAudioFormatFlagIsSignedInteger) == 0 else { return false }
        let planar = format.mFormatFlags & kAudioFormatFlagIsNonInterleaved != 0
        let bytes = UInt32(MemoryLayout<Float>.stride) * (planar ? 1 : format.mChannelsPerFrame)
        return format.mFramesPerPacket == 1 && format.mBytesPerFrame == bytes && format.mBytesPerPacket == bytes
    }

    private func watch(_ object: AudioObjectID, selector: AudioObjectPropertySelector,
                       expectedFormat: AudioStreamBasicDescription? = nil) throws {
        let flag = reconfigure
        let listener: AudioObjectPropertyListenerBlock = { _, _ in
            if let expected = expectedFormat {
                var current = AudioStreamBasicDescription()
                if AudioHardware.read(object, kAudioTapPropertyFormat, into: &current) == noErr,
                   Self.sameFormat(current, expected) { return }
            }
            flag.withLock { $0 = true }
        }
        var address = AudioObjectPropertyAddress(mSelector: selector,
            mScope: kAudioObjectPropertyScopeGlobal, mElement: kAudioObjectPropertyElementMain)
        try Self.check(AudioObjectAddPropertyListenerBlock(object, &address, routeQueue, listener), "watch audio routing")
        listeners.append((object, address, listener))
    }

    func setMuted(_ mute: Bool) throws {
        let behavior: CATapMuteBehavior = mute ? .mutedWhenTapped : .unmuted
        guard description.muteBehavior != behavior else { return }
        guard !mute || !needsReconnect else { throw GlassError("The audio output changed before speaker routing was ready.") }
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
        for (object, var address, listener) in listeners {
            AudioObjectRemovePropertyListenerBlock(object, &address, routeQueue, listener)
        }
        if running { AudioDeviceStop(aggregate, callback) }
        if let callback { AudioDeviceDestroyIOProcID(aggregate, callback) }
        if aggregate != kAudioObjectUnknown { AudioHardwareDestroyAggregateDevice(aggregate) }
        AudioHardwareDestroyProcessTap(tap)
    }
}
