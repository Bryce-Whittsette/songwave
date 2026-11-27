import AppKit
import SwiftUI
import UniformTypeIdentifiers

@MainActor
final class Studio: ObservableObject {
    @Published var showPlaybackAccess = false
    @Published private(set) var firstSuccess = FirstSuccessCheck()
    @Published private(set) var firstSuccessPending = UserDefaults.standard.bool(forKey: "firstSuccessPending")
    @Published private(set) var captureHealth = CaptureHealth.unchecked
    @Published private(set) var trackpadFailure: String?
    @Published private(set) var testingTrackpad = false
    @Published private(set) var selectedAppLabel = "Automatic Mac audio"
    private var selectedDiagnosticApp = DiagnosticApp.macAudio
    private var supportOperation = UUID()
    @Published var requestedSettingsPage: String?

    var verifyingSetup: Bool { firstSuccess.phase != .idle && firstSuccess.phase != .confirmed }
    var healthSnapshot: ListeningHealthSnapshot {
        let local: Bool = { if case .file = source { return true }; return false }()
        let capture: CaptureHealth = local ? .localFile : audioAccessHealth.failure != nil ? .failed :
            requestingAudioAccess ? .checking : !audioAccessReady ? .notConfigured : captureHealth
        let bundle: String? = { if case .player(let link) = source { return link.provider.bundle }; return detectedApp }()
        return ListeningHealthSnapshot(trackpadAvailable: device != nil, capture: capture,
            app: local ? .file : bundle == nil ? selectedDiagnosticApp : ListeningHealthSnapshot.app(bundle: bundle, localFile: false),
            pause: ListeningHealthSnapshot.pause(active: active, bypassed: localBypass, verifying: verifyingSetup,
                failure: error != nil || (capture == .failed && !local), detection: detection),
            error: trackpadFailure != nil ? .trackpad : capture == .failed ? .capture : error != nil ? .playback : .none)
    }
    var diagnosticsReport: String {
        let info = Bundle.main.infoDictionary ?? [:]
        let report = SafeDiagnostics(version: info["CFBundleShortVersionString"] as? String ?? "",
            build: info["CFBundleVersion"] as? String ?? "", model: ListeningDiagnostics.macModel,
            os: ProcessInfo.processInfo.operatingSystemVersion, route: ListeningDiagnostics.outputRoute(), health: healthSnapshot)
        return report.text
    }
    func copyDiagnostics() {
        NSPasteboard.general.clearContents()
        NSPasteboard.general.setString(diagnosticsReport, forType: .string)
    }
    func markFirstSuccessPending() {
        firstSuccessPending = true
        UserDefaults.standard.set(true, forKey: "firstSuccessPending")
    }
    func beginFirstSuccess() {
        guard !requestingAudioAccess, !testingTrackpad else { return }
        if checkPrior == nil {
            checkPrior = PriorPlayback(source: source ?? .macAudio, wasPlaying: active, elapsed: elapsed,
                duration: duration, info: metadata, bypass: localBypass)
            checkPriorPattern = (loadedPattern, patternName, patternNote)
        }
        stop(); firstSuccess.begin(); markFirstSuccessPending(); showPlaybackAccess = true
        guard audioAccessReady, !audioAccessHealth.requiresRecovery else { firstSuccess.recover(); return }
        start(.macAudio, verification: true)
    }
    func testTrackpad() {
        guard !testingTrackpad, let token = firstSuccess.beginTest() else { return }
        stop(); testingTrackpad = true
        engine.testTrackpad { [weak self] failure in
            guard let self, self.firstSuccess.phase == .testing(token) else { return }
            self.testingTrackpad = false
            self.trackpadFailure = failure
            self.firstSuccess.finishTest(token, succeeded: failure == nil)
            // Continue detection with speakers unmuted and automatic haptics off.
            if failure == nil { self.start(.macAudio, verification: true) }
        }
    }
    func firstSuccessRecovery() {
        if testingTrackpad { stop(); testingTrackpad = false }
        firstSuccess.recover()
    }
    func confirmFirstSuccess() {
        guard firstSuccess.confirm() else { return }
        UserDefaults.standard.set(true, forKey: "firstSuccessConfirmed")
        completeFirstSuccess()
    }
    func completeFirstSuccess() {
        supportOperation = UUID()
        // Continuing without a tactile confirmation remains explicitly unverified.
        let confirmed = firstSuccess.phase == .confirmed
        stop(); testingTrackpad = false; firstSuccess.cancel(); firstSuccessPending = false
        UserDefaults.standard.set(false, forKey: "firstSuccessPending")
        if !confirmed { UserDefaults.standard.set(false, forKey: "firstSuccessConfirmed") }
        afterAudioAccess = nil; showPlaybackAccess = false
        if !restoreCheckContext(resume: true) && launchListen && audioAccessHealth.permitsAutomaticListening(setupSaved: audioAccessReady) {
            autoStarted = true; start(.macAudio)
        }
    }
    func retryListening() {
        guard !testingTrackpad else { return }
        if verifyingSetup || firstSuccessPending {
            if firstSuccess.phase == .recovery && audioAccessHealth.permitsAutomaticListening(setupSaved: audioAccessReady) {
                // Recheck the connection in place. Only Run setup check starts
                // another sensation-confirmation flow; retries never actuate.
                start(.macAudio, verification: true)
            } else { beginFirstSuccess() }
            return
        }
        if let pending = afterAudioAccess {
            afterAudioAccess = nil; autoStarted = true; pending(); return
        }
        let target = source ?? .macAudio
        start(target, from: target.isLive ? 0 : elapsed, initialBypass: localBypass)
    }
    var retrySourceTitle: String {
        switch source {
        case .file: return "Retry local file"
        case .player(let link): return "Reconnect " + link.provider.appName
        case .macAudio, .none: return "Rescan music apps"
        }
    }
    func retryCapture() async {
        if case .file = source { return }
        let request = supportOperation
        guard await prepareAudioAccess() == nil, request == supportOperation else { return }
        if firstSuccess.phase == .recovery || (!firstSuccessPending && !verifyingSetup) { retryListening() }
    }
    func openRecovery() { showPlaybackAccess = true }
    func automationSettings() {
        if let url = URL(string: "x-apple.systempreferences:com.apple.preference.security?Privacy_Automation") { NSWorkspace.shared.open(url) }
    }
    func trackpadSettings() {
        if let url = URL(string: "x-apple.systempreferences:com.apple.Trackpad-Settings.extension") { NSWorkspace.shared.open(url) }
    }

    private func labelSource(_ source: PlaybackSource) {
        switch source {
        case .player(let link):
            selectedAppLabel = link.provider.appName
            selectedDiagnosticApp = ListeningHealthSnapshot.app(bundle: link.provider.bundle, localFile: false)
        case .file: selectedAppLabel = "Local audio file"; selectedDiagnosticApp = .file
        case .macAudio: selectedAppLabel = "Automatic Mac audio"; selectedDiagnosticApp = .macAudio
        }
    }

    private var checkPrior: PriorPlayback?
    private var checkPriorPattern: (HapticPattern?, String?, String?)?
    private func restoreCheckContext(resume: Bool) -> Bool {
        guard let prior = checkPrior else { return false }
        checkPrior = nil
        artworkTask?.cancel(); artworkTask = nil
        source = prior.source; labelSource(prior.source); elapsed = prior.elapsed; duration = prior.duration; metadata = prior.info
        if let pattern = checkPriorPattern {
            loadedPattern = pattern.0; patternName = pattern.1; patternNote = pattern.2
            engine.setPattern(pattern.0)
        }
        checkPriorPattern = nil
        let shouldResume = prior.wasPlaying || (prior.source == .macAudio && launchListen)
        let permitted = !prior.source.isLive || audioAccessHealth.permitsAutomaticListening(setupSaved: audioAccessReady)
        if resume && shouldResume && permitted {
            autoStarted = true
            start(prior.source, from: prior.source.isLive ? 0 : prior.elapsed, initialBypass: prior.bypass)
        }
        return true
    }

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
        guard !requestingAudioAccess, audioAccessHealth.beginCheck() else { return "Audio access is already being checked." }
        requestingAudioAccess = true
        let request = supportOperation
        defer { requestingAudioAccess = false }
        do {
            try await PlaybackAccess.requestAudio()
            UserDefaults.standard.set(true, forKey: "audioAccessConfigured")
            audioAccessReady = true
            audioAccessHealth.finishCheck(failure: nil)
            captureHealth = .ready
            // Defer until requestingAudioAccess has settled; never actuate here.
            if request == supportOperation && firstSuccessPending && firstSuccess.phase != .recovery { Task { [weak self] in
                guard let self, self.supportOperation == request, self.firstSuccessPending, self.firstSuccess.phase != .recovery else { return }
                self.beginFirstSuccess()
            } }
            return nil
        } catch {
            let message = error.localizedDescription
            captureHealth = .failed
            audioAccessHealth.finishCheck(failure: message)
            return message
        }
    }

    func finishPlaybackAccess() {
        supportOperation = UUID()
        if verifyingSetup || firstSuccessPending {
            stop(); testingTrackpad = false; firstSuccess.cancel()
            _ = restoreCheckContext(resume: false)
            return
        }
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
        if firstSuccessPending {
            showPlaybackAccess = true
            if audioAccessReady && !verifyingSetup { beginFirstSuccess() }
        } else { autoListen() }
    }

    func autoListen() {
        guard !autoStarted, launchListen, !firstSuccessPending, !verifyingSetup,
              audioAccessHealth.permitsAutomaticListening(setupSaved: audioAccessReady) else { return }
        autoStarted = true
        if !active { start(.macAudio) }
    }

    func suspendForSleep() {
        if verifyingSetup { firstSuccess.cancel(); testingTrackpad = false }
        let resume = active && source == .macAudio
        stop()
        resumeMacAfterWake = resume
    }

    func resumeAfterWake() {
        let resume = resumeMacAfterWake
        resumeMacAfterWake = false
        guard resume, !active, !firstSuccessPending, !verifyingSetup,
              audioAccessHealth.permitsAutomaticListening(setupSaved: audioAccessReady) else { return }
        start(.macAudio)
    }

    var cooldown: Double {
        max(0, UserDefaults.standard.double(forKey: "nextBurst") - Date().timeIntervalSince1970)
    }
    func startParty(lights: Bool) {
        guard !verifyingSetup else { return }
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

    private var loadedPattern: HapticPattern?
    private var patternRequest = UUID()
    @Published private(set) var patternName: String?
    @Published private(set) var patternNote: String?
    func clearPattern() {
        patternRequest = UUID()
        loadedPattern = nil; patternName = nil; patternNote = nil; engine.setPattern(nil)
    }
    func choosePattern() {
        guard case .file = source else { error = "Open a local audio file first, then attach its haptic pattern."; return }
        let panel = NSOpenPanel()
        panel.allowedContentTypes = [UTType(filenameExtension: "ahap") ?? .json, .json]
        panel.allowsMultipleSelection = false
        panel.message = "Choose a haptic pattern for this audio file. Embedded audio is skipped."
        guard panel.runModal() == .OK, let url = panel.url else { return }
        let expectedSource = source
        Task { await attachPattern(url, expectedSource: expectedSource) }
    }
    func attachPattern(_ url: URL, expectedSource: PlaybackSource? = nil) async {
        guard case .file = source else { return }
        if let expectedSource, expectedSource != source { return }
        let attachedSource = source
        let request = UUID()
        patternRequest = request
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
            loadedPattern = pattern
            engine.setPattern(pattern)
        } catch {
            guard source == attachedSource, patternRequest == request else { return }
            self.error = error.localizedDescription
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
            if verifyingSetup { return }
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
    var assistEnabled: Bool { active && mode == .assist && !localBypass && !verifyingSetup }
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

    func probe(force: Bool = false) {
        guard force || !probed else { return }
        probed = true
        engine.probe { [weak self] device, error in
            self?.device = device
            self?.trackpadFailure = error
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
        guard !verifyingSetup else { return }
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

    func start(_ source: PlaybackSource, openPlayer: Bool = false, from position: Double = 0, preserveParty: Bool = false, verification: Bool = false, initialBypass: Bool = false) {
        guard verification || !verifyingSetup else { return }
        resumeMacAfterWake = false
        if source.isLive && (!audioAccessReady || audioAccessHealth.requiresRecovery) {
            afterAudioAccess = { [weak self] in self?.start(source, openPlayer: openPlayer, from: position) }
            showPlaybackAccess = true
            return
        }
        if !preserveParty { endParty() }
        if source.isLive { captureHealth = .waiting }
        let token = UUID()
        operation = token
        localBypass = initialBypass
        detectedApp = nil
        playerTrack = nil
        detection = "Listening for music"
        labelSource(source)
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
        display.submit(.empty)
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
        var runTuning = tuning
        if verification { runTuning.hapticFocus = .beat; runTuning.vocalQuality = .light }
        engine.start(source, tuning: runTuning, mode: verification ? .assist : mode, playerPath: playerPath,
                     startAt: position, partyDeadline: preserveParty ? partyEnd : 0, hapticsEnabled: !verification && !initialBypass) { [weak self] update in
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
                self.captureHealth = .failed
                if verification { self.firstSuccess.recover() }
                self.captureHelp = source.isLive
                return
            }
            if verification && self.firstSuccess.audioPresent != update.signal.hasAudio { self.firstSuccess.observeAudio(update.signal.hasAudio) }
            let capture: CaptureHealth = update.detection == "Cannot capture audio · check recording permission" ? .failed :
                update.signal.hasAudio || ["Speech · haptics paused", "YouTube video · haptics paused"].contains(update.detection ?? "") ? .receiving : .waiting
            if self.captureHealth != capture { self.captureHealth = capture }
            if verification && capture == .failed { self.firstSuccess.recover() }
            self.display.submit(update.signal)
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
            selectedDiagnosticApp = ListeningHealthSnapshot.app(bundle: bundle, localFile: false)
            selectedAppLabel = bundle.flatMap { NSRunningApplication.runningApplications(withBundleIdentifier: $0).first?.localizedName } ?? selectedDiagnosticApp.rawValue
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
        supportOperation = UUID()
        if firstSuccess.audioPresent { firstSuccess.observeAudio(false) }
        if testingTrackpad { testingTrackpad = false; firstSuccess.recover() }
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
        captureHealth = audioAccessHealth.failure != nil ? .failed : audioAccessReady ? .unchecked : .notConfigured
        captureHelp = false
        display.submit(.empty)
        engine.stop()
    }

    func permissions() {
        guard let url = URL(string: "x-apple.systempreferences:com.apple.preference.security?Privacy_ScreenCapture") else { return }
        NSWorkspace.shared.open(url)
    }
}
