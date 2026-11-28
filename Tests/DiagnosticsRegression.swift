import CoreAudio
import Foundation

enum Fixture {
    static let scenario = CommandLine.arguments.dropFirst().first ?? "normal"
    static var modelCalls = 0
    static var failDevice = false, failTransport = false
    static var transport: UInt32 = kAudioDeviceTransportTypeBuiltIn
    static var properties: [UInt32] = []
}
// Compile-time replacements: no host hardware, route or personal name is read.
func sysctlbyname(_ name: String, _ old: UnsafeMutableRawPointer?, _ size: UnsafeMutablePointer<Int>?,
                  _ new: UnsafeMutableRawPointer?, _ newSize: Int) -> Int32 {
    precondition(name == "hw.model" && new == nil && newSize == 0)
    Fixture.modelCalls += 1
    guard let size else { return -1 }
    if old == nil {
        if Fixture.scenario == "size-failure" { return -1 }
        size.pointee = ["zero-size": 0, "negative-size": -1, "large-size": 128, "huge-size": Int.max][Fixture.scenario] ?? 9
        return 0
    }
    if Fixture.scenario == "read-failure" { return -1 }
    let bytes: [UInt8] = Fixture.scenario == "missing-nul" ? Array("Mac16,13X".utf8) :
        Fixture.scenario == "invalid-utf8" ? [0xff, 0xfe, 0] :
        Fixture.scenario == "empty-model" ? [0] : Array("Mac16,13\0".utf8)
    precondition(bytes.count <= size.pointee)
    bytes.withUnsafeBytes { old!.copyMemory(from: $0.baseAddress!, byteCount: $0.count) }
    if Fixture.scenario == "returned-zero" { size.pointee = 0 }
    if Fixture.scenario == "returned-short" { size.pointee = 8 }
    if Fixture.scenario == "returned-too-large" { size.pointee += 1 }
    return 0
}
enum AudioHardware {
    static let system = AudioObjectID(kAudioObjectSystemObject)
    static func read<T>(_ id: AudioObjectID, _ selector: AudioObjectPropertySelector, into value: inout T) -> OSStatus {
        Fixture.properties.append(selector)
        switch selector {
        case kAudioHardwarePropertyDefaultOutputDevice:
            guard !Fixture.failDevice else { return -1 }
            value = AudioObjectID(82) as! T
        case kAudioDevicePropertyTransportType:
            precondition(id == 82)
            guard !Fixture.failTransport else { return -1 }
            value = Fixture.transport as! T
        default: preconditionFailure("Diagnostics requested non-category or private hardware data")
        }
        return noErr
    }
}
@main struct DiagnosticsRegression {
    static func main() {
        setbuf(stdout, nil)
        let model = ListeningDiagnostics.macModel
        let expected = Fixture.scenario == "normal" ? "Mac16,13" : "Unknown Mac"
        precondition(model == expected, "Malformed/failed model response was not Unknown Mac")
        let reads = Fixture.modelCalls
        precondition(reads == (["size-failure", "zero-size", "negative-size", "large-size", "huge-size"].contains(Fixture.scenario) ? 1 : 2))
        _ = ListeningDiagnostics.macModel
        precondition(Fixture.modelCalls == reads, "Model lookup was not cached")
        let routes: [(UInt32, DiagnosticRoute)] = [
            (kAudioDeviceTransportTypeBuiltIn, .builtIn), (kAudioDeviceTransportTypeBluetooth, .bluetooth),
            (kAudioDeviceTransportTypeBluetoothLE, .bluetooth), (kAudioDeviceTransportTypeUSB, .usb),
            (kAudioDeviceTransportTypeHDMI, .display), (kAudioDeviceTransportTypeDisplayPort, .display),
            (kAudioDeviceTransportTypeAirPlay, .airPlay), (kAudioDeviceTransportTypeVirtual, .virtual),
            (kAudioDeviceTransportTypeAggregate, .virtual), (0, .unknown)]
        for (transport, expected) in routes {
            Fixture.transport = transport
            precondition(ListeningDiagnostics.outputRoute() == expected)
        }
        Fixture.failDevice = true; Fixture.properties.removeAll()
        precondition(ListeningDiagnostics.outputRoute() == .unknown && Fixture.properties.count == 1)
        Fixture.failDevice = false; Fixture.failTransport = true
        precondition(ListeningDiagnostics.outputRoute() == .unknown)
        print("PASS: diagnostic model \(Fixture.scenario), caching, transport categories and read failures; no names or actual hardware queried.")
    }
}
