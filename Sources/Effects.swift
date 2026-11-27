import AppKit
import AudioToolbox
import CoreAudio
import ObjectiveC

struct PartyBurst {
    static let length = 45.0
    static let recovery = 60.0
    static func allowed(thermal: ProcessInfo.ThermalState) -> Bool { thermal == .nominal || thermal == .fair }
    static func accent(elapsed: Double) -> Bool {
        elapsed >= 0 && elapsed < length && elapsed.truncatingRemainder(dividingBy: 0.36) < 0.12
    }
}

enum OutputVolume {
    static func read() -> Double {
        var device = AudioObjectID(kAudioObjectUnknown)
        guard AudioHardware.read(AudioHardware.system, kAudioHardwarePropertyDefaultOutputDevice, into: &device) == noErr else { return 1 }
        func get<T>(_ selector: AudioObjectPropertySelector, element: UInt32 = 0, _ initial: T) -> T? {
            var addr = AudioObjectPropertyAddress(mSelector: selector, mScope: kAudioDevicePropertyScopeOutput, mElement: element)
            var value = initial, length = UInt32(MemoryLayout<T>.size)
            guard AudioObjectHasProperty(device, &addr) else { return nil }
            let status = withUnsafeMutablePointer(to: &value) { AudioObjectGetPropertyData(device, &addr, 0, nil, &length, $0) }
            return status == noErr ? value : nil
        }
        if get(kAudioDevicePropertyMute, UInt32(0)) == 1 { return 0 }
        let main = get(kAudioHardwareServiceDeviceProperty_VirtualMainVolume, Float32(0)) ?? get(kAudioDevicePropertyVolumeScalar, Float32(0))
        let channels = main.map { [$0] } ?? [1, 2].compactMap { get(kAudioDevicePropertyVolumeScalar, element: $0, Float32(0)) }
        guard !channels.isEmpty else { return 1 }
        return min(1, max(0, Double(channels.reduce(0,+)) / Double(channels.count)))
    }
}

// A single attack starts a short light pulse. Between attacks the light returns
// close to dark, even when the song has a sustained bass note.
struct KeyboardPulse {
    private var attackTime = -Double.infinity
    private var peak = 0.0
    private var lastStrength = 0.0

    mutating func level(beatStrength: Double, at time: Double) -> Float {
        if beatStrength.isFinite, beatStrength > 0, (time - attackTime >= 0.14 || (beatStrength >= 0.5 && lastStrength < 0.5 && time - attackTime >= 0.045)) {
            attackTime = time
            lastStrength = beatStrength
            peak = beatStrength >= 0.5 ? 0.75 + min(1, beatStrength) * 0.25 : 0.18 + beatStrength * 0.80
        }
        let age = max(0, time - attackTime)
        let fade = max(0, 1 - max(0, age - 0.035) / 0.18)
        return Float(0.015 + (peak - 0.015) * fade * fade)
    }
}

// CoreBrightness exposes one white backlight on supported built-in keyboards.
// Read the original level before the first write and release it on every exit.
final class KeyboardLight {
    typealias Read = @convention(c) (AnyObject, Selector, UInt64) -> Float
    typealias Write = @convention(c) (AnyObject, Selector, Float, Int32, Bool, UInt64) -> Bool
    private let client: NSObject
    private let keyboard: UInt64
    private let read: Read
    private let write: Write
    private let get = NSSelectorFromString("brightnessForKeyboard:")
    private let set = NSSelectorFromString("setBrightness:fadeSpeed:commit:forKeyboard:")
    private let original: Float
    private var last: Float
    private var lastWrite = 0.0
    private var pulse = KeyboardPulse()
    private var touched = false

    init?() {
        guard Bundle(path: "/System/Library/PrivateFrameworks/CoreBrightness.framework")?.load() == true,
              let type = NSClassFromString("KeyboardBrightnessClient") as? NSObject.Type else { return nil }
        let client = type.init()
        let ids = NSSelectorFromString("copyKeyboardBacklightIDs")
        guard client.responds(to: ids), client.responds(to: get), client.responds(to: set),
              let array = client.perform(ids)?.takeRetainedValue() as? [NSNumber], let first = array.first else { return nil }
        self.client = client
        keyboard = first.uint64Value
        read = unsafeBitCast(client.method(for: get), to: Read.self)
        write = unsafeBitCast(client.method(for: set), to: Write.self)
        original = read(client, get, keyboard)
        guard original.isFinite, (0...1).contains(original) else { return nil }
        last = original
    }

    func update(beatStrength: Double, now: Double) {
        let next = pulse.level(beatStrength: beatStrength, at: now)
        // Send attacks immediately and render their release at up to 30 Hz.
        guard beatStrength > 0 || now - lastWrite >= 1.0 / 30 else { return }
        guard abs(next - last) > 0.008 else { return }
        lastWrite = now
        // The envelope already includes the fade. A second hardware fade obscures the attack.
        if write(client, set, next, 0, false, keyboard) { last = next; touched = true }
    }

    deinit { if touched { _ = write(client, set, original, 200, false, keyboard) } }
}

enum ProjectShare {
    static let url = URL(string: "https://github.com/Bryce-Whittsette/songwave")!
    @MainActor static func message() {
        let text = "Try SongWave. It lets you feel the music playing on your Mac through the trackpad. " + url.absoluteString
        NSSharingService(named: .composeMessage)?.perform(withItems: [text])
    }
    @MainActor static func copy() {
        NSPasteboard.general.clearContents()
        NSPasteboard.general.setString(url.absoluteString, forType: .string)
    }
}

enum OutputTiming {
    static func reportedDelay() -> Double {
        var device = AudioObjectID(kAudioObjectUnknown)
        guard AudioHardware.read(AudioHardware.system, kAudioHardwarePropertyDefaultOutputDevice, into: &device) == noErr else { return 0 }
        func read<T>(_ object: AudioObjectID, _ selector: AudioObjectPropertySelector,
                     scope: AudioObjectPropertyScope = kAudioDevicePropertyScopeOutput, initial: T) -> T? {
            var address = AudioObjectPropertyAddress(mSelector: selector, mScope: scope, mElement: kAudioObjectPropertyElementMain)
            var value = initial
            var length = UInt32(MemoryLayout<T>.size)
            guard AudioObjectHasProperty(object, &address) else { return nil }
            let status = withUnsafeMutablePointer(to: &value) {
                AudioObjectGetPropertyData(object, &address, 0, nil, &length, $0)
            }
            return status == noErr ? value : nil
        }
        guard let rate = read(device, kAudioDevicePropertyNominalSampleRate,
                              scope: kAudioObjectPropertyScopeGlobal, initial: 0.0),
              rate.isFinite, rate > 0 else { return 0 }
        let latency = read(device, kAudioDevicePropertyLatency, initial: UInt32(0)) ?? 0
        let safety = read(device, kAudioDevicePropertySafetyOffset, initial: UInt32(0)) ?? 0
        let buffer = read(device, kAudioDevicePropertyBufferFrameSize,
                          scope: kAudioObjectPropertyScopeGlobal, initial: UInt32(0)) ?? 0
        var address = AudioObjectPropertyAddress(mSelector: kAudioDevicePropertyStreams,
            mScope: kAudioDevicePropertyScopeOutput, mElement: kAudioObjectPropertyElementMain)
        var bytes: UInt32 = 0
        var streamLatency: UInt32 = 0
        if AudioObjectGetPropertyDataSize(device, &address, 0, nil, &bytes) == noErr, bytes > 0 {
            var streams = [AudioObjectID](repeating: 0, count: Int(bytes) / MemoryLayout<AudioObjectID>.size)
            let status = streams.withUnsafeMutableBytes {
                AudioObjectGetPropertyData(device, &address, 0, nil, &bytes, $0.baseAddress!)
            }
            if status == noErr {
                streamLatency = streams.compactMap {
                    read($0, kAudioStreamPropertyLatency, scope: kAudioObjectPropertyScopeGlobal, initial: UInt32(0))
                }.max() ?? 0
            }
        }
        return min(0.5, (Double(latency) + Double(safety) + Double(buffer) + Double(streamLatency)) / rate)
    }

    static func additionalDelay(reported: Double, analysisRate: Double, offsetMS: Double, focus: HapticFocus = .beat) -> Double {
        let halfWindow = analysisRate <= 32000 && focus == .beat ? 512.0 : 1024.0
        let analysis = halfWindow / max(1, analysisRate) + 0.004
        return min(0.8, max(0, max(0, reported - analysis) + offsetMS / 1000))
    }
}
