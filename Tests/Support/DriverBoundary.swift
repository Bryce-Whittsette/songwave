import AppKit
import CoreAudio
import Foundation

// Only the private ABI edge is replaced. Production Trackpad builds/releases
// each normalized waveform and handles actuator errors; no framework is opened.
enum DriverBoundary {
    static var opened = 0, closed = 0, packets = 0
    static var failed = false
    static var times: [Double] = []
    static var symbols: Set<String> = []
}
private let fixtureList: Trackpad.List = { .passRetained([NSNumber(value: 1)] as CFArray) }
private let fixtureID: Trackpad.ID = { _, output in output.pointee = 1; return 0 }
private let fixtureBuiltIn: Trackpad.BuiltIn = { _ in true }
private let fixtureCreate: Trackpad.Create = { _ in Unmanaged<CFTypeRef>.passRetained("Fixture actuator" as CFString) }
private let fixtureOpen: Trackpad.Access = { _ in
    InterruptionHAL.locked { InterruptionHAL.motors += 1; DriverBoundary.opened += 1 }; return 0
}
private let fixtureClose: Trackpad.Access = { _ in
    InterruptionHAL.locked { InterruptionHAL.motors -= 1; DriverBoundary.closed += 1 }; return 0
}
private let fixtureShape: Trackpad.Shape = { dictionary, _ in
    let value = dictionary as NSDictionary
    guard let base = value["BaseWaveform"] as? [String: Any], let duration = base["DurationMS"] as? Double,
          let tones = value["Tones"] as? [[String: Any]], !tones.isEmpty else {
        interruptionRequire(false, "Driver waveform shape was invalid"); return nil
    }
    interruptionRequire(duration > 0 && duration <= 16, "Unsafe driver duration")
    var total = 0.0
    for tone in tones {
        guard let amplitude = tone["Amplitude"] as? Double, let frequency = tone["FrequencykHz"] as? Double else {
            interruptionRequire(false, "Missing driver tone fields"); return nil
        }
        interruptionRequire(amplitude.isFinite && amplitude >= 0 && amplitude <= 1 && frequency.isFinite && frequency > 0,
            "Nonfinite/out-of-range private driver payload")
        total += amplitude
    }
    interruptionRequire(total <= 1.000001, "Driver waveform was not normalized")
    return Unmanaged.passRetained(dictionary).toOpaque()
}
private let fixtureActuate: Trackpad.Actuate = { _, _, _, gain, _ in
    interruptionRequire(gain.isFinite && (0...1).contains(gain), "Unsafe driver gain")
    return InterruptionHAL.locked {
        let now = ProcessInfo.processInfo.systemUptime
        DriverBoundary.packets += 1; DriverBoundary.times.append(now)
        InterruptionHAL.writes.append((now, Double(gain)))
        return DriverBoundary.failed ? -1 : 0
    }
}
func dlopen(_ path: String, _ flags: Int32) -> UnsafeMutableRawPointer? {
    interruptionRequire(path.hasSuffix("/MultitouchSupport.framework/MultitouchSupport"), "Unexpected framework access")
    return UnsafeMutableRawPointer(bitPattern: 1)
}
func dlsym(_ handle: UnsafeMutableRawPointer, _ name: String) -> UnsafeMutableRawPointer? {
    InterruptionHAL.locked { _ = DriverBoundary.symbols.insert(name) }
    switch name {
    case "MTDeviceCreateList": return unsafeBitCast(fixtureList, to: UnsafeMutableRawPointer.self)
    case "MTDeviceGetDeviceID": return unsafeBitCast(fixtureID, to: UnsafeMutableRawPointer.self)
    case "MTDeviceIsBuiltIn": return unsafeBitCast(fixtureBuiltIn, to: UnsafeMutableRawPointer.self)
    case "MTActuatorCreateFromDeviceID": return unsafeBitCast(fixtureCreate, to: UnsafeMutableRawPointer.self)
    case "MTActuatorOpen": return unsafeBitCast(fixtureOpen, to: UnsafeMutableRawPointer.self)
    case "MTActuatorClose": return unsafeBitCast(fixtureClose, to: UnsafeMutableRawPointer.self)
    case "MTActuationCreateFromDictionary": return unsafeBitCast(fixtureShape, to: UnsafeMutableRawPointer.self)
    case "MTActuationActuate": return unsafeBitCast(fixtureActuate, to: UnsafeMutableRawPointer.self)
    default: interruptionRequire(false, "Unexpected private driver symbol"); return nil
    }
}
@discardableResult func dlclose(_ handle: UnsafeMutableRawPointer?) -> Int32 { 0 }
func AudioObjectHasProperty(_ id: AudioObjectID, _ address: UnsafePointer<AudioObjectPropertyAddress>) -> Bool { false }

// File output is outside this live-source test; fail before any speaker opens.
final class AVAudioPlayer {
    var currentTime = 0.0
    var isPlaying: Bool { false }
    init(contentsOf: URL) throws { throw GlassError("Unexpected file output in source test") }
    func prepareToPlay() -> Bool { false }
    func play() -> Bool { false }
    func stop() {}
}
