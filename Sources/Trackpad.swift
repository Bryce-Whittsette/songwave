import Foundation

// Private MultitouchSupport ABI and waveform keys documented by NO SPEAKER.
// See Resources/NO-SPEAKER-LICENSE.txt.
final class Trackpad {
    typealias List = @convention(c) () -> Unmanaged<CFArray>?
    typealias ID = @convention(c) (UnsafeMutableRawPointer, UnsafeMutablePointer<UInt64>) -> Int32
    typealias BuiltIn = @convention(c) (UnsafeMutableRawPointer) -> Bool
    typealias Create = @convention(c) (UInt64) -> Unmanaged<CFTypeRef>?
    typealias Access = @convention(c) (CFTypeRef) -> Int32
    typealias Shape = @convention(c) (CFDictionary, Int32) -> UnsafeMutableRawPointer?
    typealias Actuate = @convention(c) (UnsafeMutableRawPointer, UnsafeMutableRawPointer, UInt32, Float, Float) -> Int32

    let name: String
    private let framework: UnsafeMutableRawPointer
    private let actuator: CFTypeRef
    private let close: Access
    private let shape: Shape
    private let actuate: Actuate
    private var consecutiveFailures = 0

    init() throws {
        let path = "/System/Library/PrivateFrameworks/MultitouchSupport.framework/MultitouchSupport"
        guard let handle = dlopen(path, RTLD_NOW | RTLD_LOCAL) else {
            throw GlassError("The trackpad interface is unavailable on this version of macOS.")
        }
        func symbol<T>(_ name: String, as type: T.Type) -> T? {
            dlsym(handle, name).map { unsafeBitCast($0, to: type) }
        }
        guard let list = symbol("MTDeviceCreateList", as: List.self),
              let identify = symbol("MTDeviceGetDeviceID", as: ID.self),
              let builtIn = symbol("MTDeviceIsBuiltIn", as: BuiltIn.self),
              let create = symbol("MTActuatorCreateFromDeviceID", as: Create.self),
              let open = symbol("MTActuatorOpen", as: Access.self),
              let close = symbol("MTActuatorClose", as: Access.self),
              let shape = symbol("MTActuationCreateFromDictionary", as: Shape.self),
              let actuate = symbol("MTActuationActuate", as: Actuate.self) else {
            dlclose(handle)
            throw GlassError("This version of macOS does not expose the required trackpad controls.")
        }
        guard let devices = list()?.takeRetainedValue() else {
            dlclose(handle)
            throw GlassError("Connect a Force Touch trackpad and try again.")
        }
        let candidates = (0..<CFArrayGetCount(devices)).compactMap { index -> (UInt64, Bool)? in
            guard let value = CFArrayGetValueAtIndex(devices, index) else { return nil }
            let device = UnsafeMutableRawPointer(mutating: value)
            var identifier: UInt64 = 0
            guard identify(device, &identifier) == 0 else { return nil }
            return (identifier, builtIn(device))
        }.sorted { $0.1 && !$1.1 }
        for (identifier, internalDevice) in candidates {
            if let motor = create(identifier)?.takeRetainedValue(), open(motor) == 0 {
                framework = handle
                actuator = motor
                self.close = close
                self.shape = shape
                self.actuate = actuate
                name = internalDevice ? "Built-in trackpad" : "External trackpad"
                return
            }
        }
        dlclose(handle)
        throw GlassError("A Force Touch actuator could not be opened. Reconnect the trackpad and try again.")
    }

    func play(_ tones: [Tone], for milliseconds: Double, level: Double) throws {
        guard !tones.isEmpty, level > 0.005 else { return }
        let total = max(0.0001, tones.reduce(0) { $0 + $1.weight })
        let waveform: [String: Any] = [
            "BaseWaveform": ["Type": "Gaussian", "Amplitude": 0.0, "DurationMS": milliseconds],
            "Tones": tones.map { tone in
                [
                    "Type": "Sine", "Amplitude": tone.weight / total,
                    "DurationMS": milliseconds, "DelayMS": 0.0, "FrequencykHz": tone.hertz / 1000
                ] as [String: Any]
            }
        ]
        guard let pulse = shape(waveform as CFDictionary, 0) else {
            throw GlassError("The trackpad driver rejected the waveform.")
        }
        defer { Unmanaged<AnyObject>.fromOpaque(pulse).release() }
        let motor = Unmanaged.passUnretained(actuator).toOpaque()
        let result = actuate(pulse, motor, 0, Float(min(level, 1)), 0)
        consecutiveFailures = result == 0 ? 0 : consecutiveFailures + 1
        if consecutiveFailures >= 4 {
            throw GlassError("The trackpad stopped responding. Stop and reconnect it before trying again.")
        }
    }

    deinit {
        _ = close(actuator)
        dlclose(framework)
    }
}

struct GlassError: LocalizedError {
    let errorDescription: String?
    init(_ message: String) { errorDescription = message }
}
