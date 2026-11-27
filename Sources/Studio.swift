import AppKit
import SwiftUI
import UniformTypeIdentifiers

@MainActor
final class SignalDisplay: ObservableObject {
    private var origin = SignalFrame.empty.bands
    private var timestamp = ProcessInfo.processInfo.systemUptime
    @Published private(set) var settling = false
    private var releaseTask: Task<Void, Never>?
    @Published var frame = SignalFrame.empty {
        willSet {
            let now = ProcessInfo.processInfo.systemUptime
            origin = bands(at: now)
            timestamp = now
            if frame.hasAudio && !newValue.hasAudio {
                settling = true
                releaseTask?.cancel()
                releaseTask = Task { [weak self] in
                    try? await Task.sleep(for: .milliseconds(750))
                    if !Task.isCancelled { self?.settling = false }
                }
            } else if newValue.hasAudio && settling { releaseTask?.cancel(); settling = false }
        }
    }

    func bands(at now: Double) -> [Double] {
        let elapsed = max(0, now - timestamp)
        return zip(origin, frame.bands).map { start, target in
            let duration = target > start ? 0.065 : 0.18
            return target + (start - target) * exp(-elapsed / duration)
        }
    }
}

@MainActor
final class Studio: ObservableObject {
    @Published var showPlaybackAccess = false
    private var afterAudioAccess: (() -> Void)?
    @Published private(set) var requestingAudioAccess = false
    // This records completion of SongWave's setup, not macOS authorization.
    // Core Audio still checks permission when a tap is opened. A preview rebuild
    // must not make people repeat our own connection screen.
    @Published private(set) var audioAccessReady = Studio.configuredAudioAccess()
    @Published private(set) var audioAccessHealth = AudioAccessHealth()

    private static func configuredAudioAccess() -> Bool {
        let defaults = UserDefaults.standard
        if defaults.object(forKey: "audioAccessConfigured") != nil {
            return defaults.bool(forKey: "audioAccessConfigured")
        }
        let configured = !(defaults.string(forKey: "audioAccessIdentity") ?? "").isEmpty
        if configured { defaults.set(true, forKey: "audioAccessConfigured") }
        return configured
    }

    func prepareAudioAccess() async -> String? {
        guard !requestingAudioAccess, audioAccessHealth.beginCheck() else { return nil }
        requestingAudioAccess = true
        defer { requestingAudioAccess = false }
        do {
            try await PlaybackAccess.requestAudio()
            UserDefaults.standard.set(true, forKey: "audioAccessConfigured")
            audioAccessReady = true
            audioAccessHealth.finishCheck(failure: nil)
            return nil
        } catch {
            let message = error.localizedDescription
            audioAccessHealth.finishCheck(failure: message)
            return message
        }
    }

    func finishPlaybackAccess() {
        let pending = afterAudioAccess
        afterAudioAccess = nil
        guard audioAccessHealth.permitsAutomaticListening(setupSaved: audioAccessReady) else { return }
        if let pending {
            autoStarted = true
            pending()
        } else { autoListen() }
    }

    @Published var partyEnd = 0.0
    @Published var followVolume = UserDefaults.standard.bool(forKey: "followVolume") {
        didSet { UserDefaults.standard.set(followVolume, forKey: "followVolume"); updateEffects() }
    }
    @Published var keyboard = UserDefaults.standard.bool(forKey: "keyboardSync") {
        didSet { UserDefaults.standard.set(keyboard, forKey: "keyboardSync"); updateEffects() }
    }
    @Published var launchListen = UserDefaults.standard.object(forKey: "launchListen") == nil || UserDefaults.standard.bool(forKey: "launchListen") {
        didSet { UserDefaults.standard.set(launchListen, forKey: "launchListen") }
    }
    @Published var genre = ListeningGenre(rawValue: UserDefaults.standard.string(forKey: "genre") ?? "") ?? .mixed
    var focus = ListeningFocus(rawValue: UserDefaults.standard.string(forKey: "focus") ?? "") ?? .natural
    private var partyLights = false
    private var restoreLocalBypass = false
    private struct PriorPlayback {
        let source: PlaybackSource
        let wasPlaying: Bool
        let elapsed: Double
        let duration: Double?
        let info: TrackInfo?
        let bypass: Bool
    }
    private var priorPlayback: PriorPlayback?
    private var partyID: UUID?
    private var partyTimer: Task<Void, Never>?
    private var playerTrack: PlayerTrack?
    private var notifications: [NSObjectProtocol] = []
    private var autoStarted = false
    private var resumeMacAfterWake = false

    func setGenre(_ value: ListeningGenre) {
        genre = value
        UserDefaults.standard.set(value.rawValue, forKey: "genre")
        for output in OutputMode.allCases {
            var next = tunings[output] ?? output.defaults
            focus.apply(genre: value, to: &next)
            if output == mode { tuning = next }
            else {
                tunings[output] = next
                if let data = try? JSONEncoder().encode(next) { UserDefaults.standard.set(data, forKey: preferenceKey(output)) }
            }
        }
    }

    func finishSetup(auto: Bool, genre: ListeningGenre, focus: ListeningFocus, gain: Double) {
        launchListen = auto
        self.focus = focus
        UserDefaults.standard.set(focus.rawValue, forKey: "focus")
        setGenre(genre)
        tuning.gain = gain

    }

    func launchIfConfigured() {
        guard UserDefaults.standard.bool(forKey: "setupComplete") else { return }
        autoListen()
    }

    func autoListen() {
        guard !autoStarted, launchListen,
              audioAccessHealth.permitsAutomaticListening(setupSaved: audioAccessReady) else { return }
        autoStarted = true
        if !active { start(.macAudio) }
    }

    func suspendForSleep() {
        let resume = active && source == .macAudio
        stop()
        resumeMacAfterWake = resume
    }

    func resumeAfterWake() {
        let resume = resumeMacAfterWake
        resumeMacAfterWake = false
        guard resume, !active,
              audioAccessHealth.permitsAutomaticListening(setupSaved: audioAccessReady) else { return }
        start(.macAudio)
    }

    var cooldown: Double {
        max(0, UserDefaults.standard.double(forKey: "nextBurst") - Date().timeIntervalSince1970)
    }
    func startParty(lights: Bool) {
        guard partyID == nil, cooldown == 0, PartyBurst.allowed(thermal: ProcessInfo.processInfo.thermalState) else {
            error = "Let the Mac cool down before starting another burst."
            return
        }
        if !active && (!audioAccessReady || audioAccessHealth.requiresRecovery) {
            afterAudioAccess = { [weak self] in self?.startParty(lights: lights) }
            showPlaybackAccess = true
            return
        }
        if !active {
            priorPlayback = PriorPlayback(source: source ?? .macAudio, wasPlaying: active, elapsed: elapsed,
                                          duration: duration, info: metadata, bypass: localBypass)
        }
        restoreLocalBypass = localBypass
        let id = UUID()
        partyID = id
        partyLights = lights
        partyEnd = ProcessInfo.processInfo.systemUptime + PartyBurst.length
        UserDefaults.standard.set(Date().timeIntervalSince1970 + PartyBurst.length + PartyBurst.recovery, forKey: "nextBurst")
        updateEffects()
        if !active {
            // Starting Ultra never creates an audio player.
            start(.macAudio, preserveParty: true)
        }
        if localBypass { localBypass = false; engine.setHaptics(true) }
        engine.party(until: partyEnd)
        let remaining = max(0, partyEnd - ProcessInfo.processInfo.systemUptime)
        // Core Audio can block while macOS waits for recording permission.
        // Keep the visible countdown and cooldown independent of that queue.
        partyTimer = Task { [weak self] in
            try? await Task.sleep(for: .seconds(remaining))
            guard !Task.isCancelled, self?.partyID == id else { return }
            self?.cancelParty()
        }
    }

    func cancelParty() {
        let previous = priorPlayback
        endParty()
        guard let previous else { return }
        stop()
        if previous.wasPlaying {
            start(previous.source, from: previous.source.isLive ? 0 : previous.elapsed)
            if previous.bypass {
                localBypass = true
                engine.setHaptics(false)
            }
        } else {
            source = previous.source
            elapsed = previous.elapsed
            duration = previous.duration
            metadata = previous.info
        }
    }

    func endParty() {
        guard partyID != nil else { return }
        partyID = nil
        priorPlayback = nil
        partyTimer?.cancel()
        partyTimer = nil
        partyEnd = 0
        partyLights = false
        if restoreLocalBypass {
            localBypass = true
            engine.setHaptics(false)
        }
        restoreLocalBypass = false
        UserDefaults.standard.set(Date().timeIntervalSince1970 + PartyBurst.recovery, forKey: "nextBurst")
        engine.party(until: 0)
        updateEffects()
    }
    private func updateEffects() { engine.setEffects(followVolume: followVolume, keyboard: keyboard, partyKeyboard: partyLights) }
    func terminate(_ completion: @escaping () -> Void) { engine.shutDown(completion) }

    private var patternRequest = UUID()
    @Published private(set) var patternName: String?
    @Published private(set) var patternNote: String?
    func clearPattern() {
        patternRequest = UUID()
        patternName = nil; patternNote = nil; engine.setPattern(nil)
    }
    func choosePattern() {
        guard case .file = source else { error = "Open a local audio file first, then attach its haptic pattern."; return }
        let panel = NSOpenPanel()
        panel.allowedContentTypes = [UTType(filenameExtension: "ahap") ?? .json, .json]
        panel.allowsMultipleSelection = false
        panel.message = "Choose a haptic pattern for this audio file. Embedded audio is skipped."
        guard panel.runModal() == .OK, let url = panel.url else { return }
        let attachedSource = source
        let request = UUID()
        patternRequest = request
        Task {
            do {
                let pattern = try await Task.detached {
                    guard (try url.resourceValues(forKeys: [.fileSizeKey]).fileSize ?? 0) <= 1_048_576 else {
                        throw GlassError("Choose an AHAP file smaller than 1 MB.")
                    }
                    return try HapticPattern(data: Data(contentsOf: url))
                }.value
                guard source == attachedSource, patternRequest == request else { return }
                patternName = url.deletingPathExtension().lastPathComponent
                patternNote = pattern.skippedAudio > 0 ? "Haptics only · embedded audio skipped" : "Haptics follow this file’s playback clock"
                engine.setPattern(pattern)
            } catch { self.error = error.localizedDescription }
        }
    }

    @Published var link = ""
    @Published var source: PlaybackSource? = .macAudio
    @Published var mode: OutputMode = OutputMode(rawValue: UserDefaults.standard.string(forKey: "outputMode") ?? "") ?? .assist {
        didSet {
            guard mode != oldValue else { return }
            UserDefaults.standard.set(mode.rawValue, forKey: "outputMode")
            let selectedFocus = tuning.focus(for: oldValue)
            var next = tunings[mode] ?? mode.defaults
            next.hapticFocus = selectedFocus
            tuning = next
            if active && source == .macAudio { engine.setMacMode(mode) }
            else if active, let source { start(source, from: source.isLive ? 0 : elapsed, preserveParty: true) }
        }
    }
    @Published var tuning = OutputMode.assist.defaults {
        didSet {
            tunings[mode] = tuning
            if let data = try? JSONEncoder().encode(tuning) {
                UserDefaults.standard.set(data, forKey: preferenceKey(mode))
            }
            engine.set(tuning: tuning)
        }
    }
    var hapticFocus: HapticFocus {
        get { tuning.focus(for: mode) }
        set { tuning.hapticFocus = newValue }
    }
    @Published var detection = "Listening for music"
    @Published var localBypass = false
    @Published var detectedApp: String?
    var assistEnabled: Bool { active && mode == .assist && !localBypass }
    @Published var metadata: TrackInfo?
    let display = SignalDisplay()
    @Published var device: String?
    @Published var error: String?
    @Published var active = false
    @Published var waiting = false
    @Published var elapsed = 0.0
    @Published var duration: Double?
    @Published var processingDelay = 0.0
    @Published var captureHelp = false

    private let engine = Playback()
    private var tunings: [OutputMode: Tuning] = [:]
    private var operation = UUID()
    private var playerPath: String?
    private var startedAt: Date?
    private var captureWatchdog: Task<Void, Never>?
    private var lastCaptureUpdate = 0.0
    private var probed = false

    private var artworkTask: Task<Void, Never>?

    init() {
        for mode in OutputMode.allCases {
            if let data = UserDefaults.standard.data(forKey: preferenceKey(mode)),
               let saved = try? JSONDecoder().decode(Tuning.self, from: data) {
                tunings[mode] = saved
            }
        }
        tuning = tunings[mode] ?? mode.defaults
        updateEffects()
        // Startup belongs to the Studio lifetime, including a menu-bar launch
        // whose restored main window never appears.
        Task { [weak self] in self?.launchIfConfigured() }
        for name in ["com.spotify.client.PlaybackStateChanged", "com.apple.Music.playerInfo"] {
            notifications.append(DistributedNotificationCenter.default().addObserver(forName: .init(name), object: nil, queue: .main) { [weak self] _ in
                Task { @MainActor in self?.lastInfoCheck = .distantPast }
            })
        }
    }

    private func preferenceKey(_ mode: OutputMode) -> String {
        mode == .trackpad ? "trackpadTuning" : "assistTuning"
    }

    func probe() {
        guard !probed else { return }
        probed = true
        engine.probe { [weak self] device, error in
            self?.device = device
            if self?.active == false { self?.error = error }
        }
    }

    func playLink() {
        do {
            let link = try MusicLink(self.link)
            guard let app = NSWorkspace.shared.urlForApplication(withBundleIdentifier: link.provider.bundle) else {
                error = "Install the \(link.provider.appName) desktop app to route this link."
                return
            }
            playerPath = app.path
            start(.player(link), openPlayer: true)
        } catch {
            self.error = error.localizedDescription
        }
    }

    func paste() {
        guard let value = NSPasteboard.general.string(forType: .string), !value.isEmpty else {
            error = "Copy a music link before pasting."
            return
        }
        link = value.trimmingCharacters(in: .whitespacesAndNewlines)
        error = nil
    }

    func chooseAudio() {
        let panel = NSOpenPanel()
        panel.allowedContentTypes = [.audio]
        panel.allowsMultipleSelection = false
        panel.message = "Choose an audio file to play through your trackpad."
        if let window = NSApp.keyWindow {
            panel.beginSheetModal(for: window) { [weak self] response in
                if response == .OK, let url = panel.url { self?.start(.file(url)) }
            }
        } else {
            panel.begin { [weak self] response in
                if response == .OK, let url = panel.url { self?.start(.file(url)) }
            }
        }
    }

    func routeMacAudio() {
        if active && source == .macAudio { stop() }
        else { start(.macAudio) }
    }

    func toggleAssist() {
        if active {
            if mode != .assist {
                localBypass = false
                engine.setHaptics(true)
                mode = .assist
            }
            else {
                localBypass.toggle()
                engine.setHaptics(!localBypass)
            }
        } else {
            mode = .assist
            start(.macAudio)
        }
    }

    func start(_ source: PlaybackSource, openPlayer: Bool = false, from position: Double = 0, preserveParty: Bool = false) {
        resumeMacAfterWake = false
        if source.isLive && (!audioAccessReady || audioAccessHealth.requiresRecovery) {
            afterAudioAccess = { [weak self] in self?.start(source, openPlayer: openPlayer, from: position) }
            showPlaybackAccess = true
            return
        }
        if !preserveParty { endParty() }
        let token = UUID()
        operation = token
        localBypass = false
        detectedApp = nil
        playerTrack = nil
        detection = "Listening for music"
        lastInfoCheck = .distantPast
        liveInfoTask?.cancel()
        liveInfoTask = nil
        let changedSource = source != self.source
        if changedSource { clearPattern() }
        if changedSource { self.source = source }
        if changedSource || (openPlayer && metadata == nil) {
            metadata = nil
            artworkTask?.cancel()
            artworkTask = Task { [weak self] in
                let info = await TrackCatalog.metadata(for: source)
                guard !Task.isCancelled else { return }
                if self?.playerTrack == nil { self?.metadata = info }
            }
        }
        elapsed = position
        duration = nil
        processingDelay = 0
        display.frame = .empty
        active = true
        waiting = source.isLive
        captureHelp = false
        error = nil
        startedAt = Date()
        captureWatchdog?.cancel()
        captureWatchdog = nil
        if source.isLive {
            lastCaptureUpdate = ProcessInfo.processInfo.systemUptime
            captureWatchdog = Task { [weak self] in
                while !Task.isCancelled {
                    try? await Task.sleep(for: .seconds(8))
                    guard !Task.isCancelled, let self, self.operation == token else { return }
                    if ProcessInfo.processInfo.systemUptime - self.lastCaptureUpdate >= 8 {
                        self.captureHelp = true
                    }
                }
            }
        }
        if openPlayer, case .player(let link) = source, let playerPath {
            let configuration = NSWorkspace.OpenConfiguration()
            configuration.activates = true
            NSWorkspace.shared.open([link.playerURL], withApplicationAt: URL(fileURLWithPath: playerPath),
                                    configuration: configuration) { [weak self] _, error in
                if let error {
                    DispatchQueue.main.async {
                        guard let self, self.operation == token else { return }
                        self.stop()
                        self.error = "Couldn’t open \(link.provider.appName). \(error.localizedDescription)"
                    }
                }
            }
        }
        engine.start(source, tuning: tuning, mode: mode, playerPath: playerPath,
                     startAt: position, partyDeadline: preserveParty ? partyEnd : 0) { [weak self] update in
            guard let self, self.operation == token else { return }
            self.lastCaptureUpdate = ProcessInfo.processInfo.systemUptime
            if update.partyOverheated {
                self.cancelParty()
                self.error = "Ultra stopped because your Mac is getting warm."
                return
            }
            if let error = update.error {
                if self.priorPlayback != nil { self.cancelParty() } else { self.stop() }
                self.error = error
                self.captureHelp = source.isLive
                return
            }
            if update.signal.hasAudio || self.display.frame.hasAudio { self.display.frame = update.signal }
            if let reason = update.detection, reason != self.detection { self.detection = reason }
            if source.isLive { self.refreshLiveInfo(update, source: source, token: token) }
            if self.waiting != update.waiting { self.waiting = update.waiting }
            if self.processingDelay != update.processingDelay { self.processingDelay = update.processingDelay }
            let livePosition = self.playerTrack.map { min($0.duration, $0.position + max(0, ProcessInfo.processInfo.systemUptime - $0.observed)) } ?? update.video?.position
            let position = livePosition.map { max(0, $0 - update.processingDelay) } ?? update.elapsed
            let duration = self.playerTrack?.duration ?? update.video?.duration ?? update.duration
            if (!source.isLive || duration != nil) && (abs(self.elapsed - position) >= 0.18 || update.finished) { self.elapsed = position }
            if self.duration != duration { self.duration = duration }
            if self.device != update.device { self.device = update.device }
            let help = (source != .macAudio || update.detection == "Waiting for Mac audio") && update.waiting && (self.startedAt.map { Date().timeIntervalSince($0) > 8 } ?? false)
            if self.captureHelp != help { self.captureHelp = help }
            if update.finished { self.stop() }
        }
    }

    private var liveInfoTask: Task<Void, Never>?
    private var lastInfoCheck = Date.distantPast
    private var liveVideoIdentity: String?

    private func refreshLiveInfo(_ update: PlaybackUpdate, source: PlaybackSource, token: UUID) {
        let bundle: String?
        if case .player(let link) = source { bundle = link.provider.bundle } else { bundle = update.appBundle }
        if detectedApp != bundle {
            detectedApp = bundle
            if playerTrack != nil || source == .macAudio { metadata = nil }
            liveVideoIdentity = nil
            playerTrack = nil
            engine.confirmPlayer(nil)
            liveInfoTask?.cancel()
            liveInfoTask = nil
            lastInfoCheck = .distantPast
        }
        if let video = update.video, !video.title.isEmpty {
            let title = video.title
            let identity = video.videoID.map { "id:" + $0 } ?? "title:" + title
            if liveVideoIdentity != identity {
                liveVideoIdentity = identity
                artworkTask?.cancel()
                metadata = TrackInfo(title: title, artist: "YouTube")
                artworkTask = Task { [weak self] in
                    let cover = await TrackCatalog.videoCover(video.videoID)
                    guard !Task.isCancelled, let self, self.operation == token,
                          self.liveVideoIdentity == identity else { return }
                    self.metadata?.cover = cover
                }
            } else if metadata?.title != title {
                metadata?.title = title
            }
            return
        }
        if liveVideoIdentity != nil {
            liveVideoIdentity = nil
            artworkTask?.cancel()
            metadata = nil
        }
        guard let app = detectedApp, liveInfoTask == nil,
              Date().timeIntervalSince(lastInfoCheck) >= 3,
              let provider = Provider.allCases.first(where: { app == $0.bundle || app.hasPrefix($0.bundle + ".") }) else { return }
        lastInfoCheck = Date()
        liveInfoTask = Task { [weak self] in
            let track = await TrackCatalog.playing(provider)
            guard !Task.isCancelled, let self, self.operation == token, self.detectedApp == app else { return }
            self.liveInfoTask = nil
            let previous = self.playerTrack
            self.playerTrack = track
            let confirmed = track.map { provider == .apple || $0.id.contains(":track:") || $0.id.contains("/track/") } ?? false
            self.engine.confirmPlayer(confirmed ? app : nil)
            guard let track else {
                if previous != nil {
                    self.artworkTask?.cancel()
                    self.metadata = nil
                }
                return
            }
            guard previous?.id != track.id || previous?.info != track.info else { return }
            self.metadata = track.info
            self.artworkTask?.cancel()
            self.artworkTask = Task { [weak self] in
                let image = await TrackCatalog.cover(for: track, provider: provider)
                guard !Task.isCancelled, let self, self.operation == token, self.playerTrack?.id == track.id else { return }
                self.metadata?.cover = image
            }
        }
    }

    func toggle() {
        if active { stop() }
        else if let source { start(source, from: source.isLive || elapsed >= (duration ?? 0) ? 0 : elapsed) }
        else { routeMacAudio() }
    }

    func stop() {
        resumeMacAfterWake = false
        if afterAudioAccess != nil {
            afterAudioAccess = nil
            autoStarted = true
        }
        if partyEnd > 0 { endParty() }
        captureWatchdog?.cancel()
        captureWatchdog = nil
        playerTrack = nil
        if source?.isLive == true { duration = nil; elapsed = 0 }
        operation = UUID()
        localBypass = false
        liveInfoTask?.cancel()
        liveInfoTask = nil
        if source == .macAudio { metadata = nil; detectedApp = nil }
        active = false
        waiting = false
        captureHelp = false
        display.frame = .empty
        engine.stop()
    }

    func permissions() {
        guard let url = URL(string: "x-apple.systempreferences:com.apple.preference.security?Privacy_ScreenCapture") else { return }
        NSWorkspace.shared.open(url)
    }
}
