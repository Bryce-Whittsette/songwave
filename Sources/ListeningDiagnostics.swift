import AppKit
import CoreAudio

// Device names can contain a person's name. Export only the transport category.
enum ListeningDiagnostics {
    static let macModel: String = {
        var size = 0
        guard sysctlbyname("hw.model", nil, &size, nil, 0) == 0, size > 0, size < 128 else { return "Unknown Mac" }
        var buffer = [CChar](repeating: 0, count: size)
        guard sysctlbyname("hw.model", &buffer, &size, nil, 0) == 0 else { return "Unknown Mac" }
        return String(cString: buffer)
    }()
    static func outputRoute() -> DiagnosticRoute {
        var device = AudioObjectID(kAudioObjectUnknown)
        guard AudioHardware.read(AudioHardware.system, kAudioHardwarePropertyDefaultOutputDevice, into: &device) == noErr else { return .unknown }
        var transport: UInt32 = 0
        guard AudioHardware.read(device, kAudioDevicePropertyTransportType, into: &transport) == noErr else { return .unknown }
        switch transport {
        case kAudioDeviceTransportTypeBuiltIn: return .builtIn
        case kAudioDeviceTransportTypeBluetooth, kAudioDeviceTransportTypeBluetoothLE: return .bluetooth
        case kAudioDeviceTransportTypeUSB: return .usb
        case kAudioDeviceTransportTypeHDMI, kAudioDeviceTransportTypeDisplayPort: return .display
        case kAudioDeviceTransportTypeAirPlay: return .airPlay
        case kAudioDeviceTransportTypeVirtual, kAudioDeviceTransportTypeAggregate: return .virtual
        default: return .unknown
        }
    }
}
