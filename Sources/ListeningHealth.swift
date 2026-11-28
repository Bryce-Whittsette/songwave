import Foundation

// Only explicit sensation confirmation is persisted as tactile success.
struct FirstSuccessCheck {
    enum Phase: Equatable { case idle, listening, testing(UUID), awaitingConfirmation, confirmed, recovery }
    private(set) var phase: Phase = .idle
    private(set) var audioDetected = false
    private(set) var audioPresent = false
    mutating func begin() { phase = .listening; audioDetected = false; audioPresent = false }
    mutating func observeAudio(_ detected: Bool) { audioPresent = detected; audioDetected = audioDetected || detected }
    var audioStatus: String {
        audioPresent ? "Audio detected" : audioDetected ? "Audio detected earlier; waiting for music" : "Waiting for music on your Mac"
    }
    mutating func beginTest() -> UUID? {
        guard phase == .listening || phase == .awaitingConfirmation || phase == .recovery else { return nil }
        let token = UUID(); phase = .testing(token); return token
    }
    mutating func finishTest(_ token: UUID, succeeded: Bool) {
        guard phase == .testing(token) else { return }
        phase = succeeded ? .awaitingConfirmation : .recovery
    }
    mutating func confirm() -> Bool {
        guard phase == .awaitingConfirmation else { return false }
        phase = .confirmed; return true
    }
    mutating func recover() { phase = .recovery }
    mutating func cancel() { phase = .idle }
    var testing: Bool { if case .testing = phase { return true }; return false }
    var canConfirm: Bool { phase == .awaitingConfirmation }
}

// A stalled timer skips missed taps instead of replaying a catch-up burst.
struct TrackpadCheckSequence {
    static let duration = 0.65
    private var next = 0
    mutating func pulse(at elapsed: Double) -> Bool {
        guard elapsed.isFinite, elapsed >= 0 else { return false }
        var play = false
        for index in next..<3 {
            let time = Double(index) * 0.18
            guard elapsed >= time else { break }
            next = index + 1
            if elapsed - time <= 0.055 { play = true }
        }
        return play
    }
}

enum CaptureHealth: String { case notConfigured = "Not set up", unchecked = "Not checked this session", checking = "Checking access", ready = "Access checked; waiting for audio", receiving = "Audio received", waiting = "Waiting for audio", interrupted = "Audio signal interrupted; check recording access", failed = "Capture needs attention", localFile = "Local file; no recording permission needed" }
enum ListeningPause: String { case none = "Listening", stopped = "Stopped", bypassed = "Haptics off", call = "Call audio; haptics paused", speech = "Speech; haptics paused", video = "Non-music video; haptics paused", waiting = "Waiting for music", check = "Setup check; normal haptics paused", failure = "Playback needs attention" }
enum DiagnosticApp: String { case macAudio = "Automatic Mac audio", spotify = "Spotify", music = "Apple Music", browser = "Browser", other = "Other app", file = "Local file" }
enum DiagnosticRoute: String { case builtIn = "Built-in audio", bluetooth = "Bluetooth", usb = "USB", display = "Display audio", airPlay = "AirPlay", virtual = "Virtual audio", unknown = "Unknown" }
enum DiagnosticError: String { case none, capture, trackpad, playback, thermal }

struct ListeningHealthSnapshot {
    var trackpadAvailable: Bool
    var capture: CaptureHealth
    var app: DiagnosticApp
    var pause: ListeningPause
    var error: DiagnosticError

    static func pause(active: Bool, bypassed: Bool, verifying: Bool, failure: Bool, detection: String) -> ListeningPause {
        // Exact engine-owned states; never override a call/filter on Retry.
        switch active ? detection : "" {
        case "Paused for call audio": return .call
        case "Speech · haptics paused": return .speech
        case "YouTube video · haptics paused": return .video
        default: break
        }
        if verifying { return .check }
        if failure { return .failure }
        if !active { return .stopped }
        if bypassed { return .bypassed }
        return ["Waiting for Mac audio", "Listening for music", "Waiting for vocals", "Audio signal interrupted · check recording access"].contains(detection) ? .waiting : .none
    }
    static func app(bundle: String?, localFile: Bool) -> DiagnosticApp {
        if localFile { return .file }
        guard let bundle else { return .macAudio }
        if bundle == "com.spotify.client" { return .spotify }
        if bundle == "com.apple.Music" { return .music }
        if ["com.apple.Safari", "com.google.Chrome", "org.mozilla.firefox", "com.microsoft.edgemac"].contains(bundle) || bundle.hasPrefix("com.apple.WebKit.") { return .browser }
        return .other
    }
}

// Constructed from categories and numeric system facts, never free-form errors,
// filenames, device names, bundle IDs, catalog metadata or environment variables.
struct SafeDiagnostics {
    var version: String
    var build: String
    var model: String
    var os: OperatingSystemVersion
    var route: DiagnosticRoute
    var health: ListeningHealthSnapshot
    private func numeric(_ value: String) -> String {
        value.count <= 32 && !value.isEmpty && value.allSatisfy { $0.isASCII && ($0.isNumber || $0 == ".") } ? value : "unknown"
    }
    var text: String {
        let model = self.model.range(of: #"^(?:Mac(?:Book(?:Air|Pro)?|mini|Pro|Studio)?|iMac(?:Pro)?)[0-9]+,[0-9]+$"#, options: .regularExpression) == self.model.startIndex..<self.model.endIndex ? self.model : "Unknown Mac"
        return """
        SongWave diagnostics
        App: \(numeric(version)) (\(numeric(build)))
        Mac: \(model)
        macOS: \(max(0, os.majorVersion)).\(max(0, os.minorVersion)).\(max(0, os.patchVersion))
        Output route: \(route.rawValue)
        Trackpad: \(health.trackpadAvailable ? "Available" : "Unavailable")
        Capture: \(health.capture.rawValue)
        Selected app: \(health.app.rawValue)
        Pause: \(health.pause.rawValue)
        Error state: \(health.error.rawValue)
        """
    }
}
