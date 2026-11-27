import AVFoundation
import Combine
import MediaAccessibility
import MediaPlayer
import ImageIO
import MusicKit
import SwiftUI

@MainActor
final class MobilePlayer: ObservableObject {
    enum Source: String, CaseIterable { case files = "Files", appleMusic = "Apple Music" }
    @Published var source: Source = .files {
        didSet {
            guard source != oldValue, playbackSource != source else { return }
            stop(); playbackSource = source; selectedSong = nil
            title = "Choose your music"; artist = "Open an audio file or connect Apple Music."
            artwork = nil; fileArtwork = nil; duration = 0
        }
    }
    @Published var focus = HapticFocus(rawValue: UserDefaults.standard.string(forKey: "mobileFocus") ?? "") ?? .beat { didSet { UserDefaults.standard.set(focus.rawValue, forKey: "mobileFocus"); configureLocal() } }
    @Published var intensity = UserDefaults.standard.object(forKey: "mobileIntensity").map { _ in let value = UserDefaults.standard.double(forKey: "mobileIntensity"); return value.isFinite ? min(1, max(0, value)) : 0.4 } ?? 0.4 { didSet { UserDefaults.standard.set(intensity, forKey: "mobileIntensity"); configureLocal() } }
    @Published var audible = UserDefaults.standard.object(forKey: "mobileAudible").map { _ in UserDefaults.standard.bool(forKey: "mobileAudible") } ?? true { didSet { UserDefaults.standard.set(audible, forKey: "mobileAudible"); configureLocal() } }
    @Published private(set) var title = "Choose your music"
    @Published private(set) var artist = "Open an audio file or connect Apple Music."
    @Published private(set) var artwork: URL?
    @Published private(set) var fileArtwork: UIImage?
    @Published private(set) var position = 0.0
    @Published private(set) var duration = 0.0
    @Published private(set) var isPlaying = false
    @Published private(set) var ready = false
    @Published private(set) var connected = MusicAuthorization.currentStatus == .authorized
    @Published private(set) var songs: [Song] = []
    @Published private(set) var searching = false
    @Published private(set) var busy = false
    @Published private(set) var starting = false
    @Published private(set) var message: String?
    @Published private(set) var hapticStatus = "Custom haptics require a supported physical iPhone."
    private var local = LocalAudioEngine()
    private let music = ApplicationMusicPlayer.shared
    private var playbackSource: Source = .files
    private var selectedSong: Song?
    private var operation = UUID()
    private var transportID = UUID()
    private var progress: Task<Void, Never>?
    private var foreground = true
    private var observation: (any NSCopying)?
    private var notifications: [NSObjectProtocol] = []
    private var currentImport: URL?
    private var remoteTargets: [(MPRemoteCommand, Any)] = []

    init() {
        let stale = FileManager.default.temporaryDirectory.appendingPathComponent("SongWaveImports", isDirectory: true)
        for url in (try? FileManager.default.contentsOfDirectory(at: stale, includingPropertiesForKeys: nil)) ?? [] { try? FileManager.default.removeItem(at: url) }
        hapticStatus = local.supportsHaptics ? "Voice and Beat use on-device analysis. No audio is uploaded." : "This device cannot produce custom Core Haptics feedback."
        bindLocalCallbacks()
        observation = MAMusicHapticsManager.shared.addStatusObserver { [weak self] code, playing in
            Task { @MainActor in
                guard self?.playbackSource == .appleMusic, self?.selectedSong?.isrc == code else { return }
                self?.hapticStatus = playing && self?.isPlaying == true ? "Apple Music haptic track is playing." : "Apple Music haptic track is not playing."
            }
        }
        notifications.append(NotificationCenter.default.addObserver(forName: AVAudioSession.interruptionNotification, object: nil, queue: .main) { [weak self] notification in
            guard let raw = notification.userInfo?[AVAudioSessionInterruptionTypeKey] as? UInt,
                  AVAudioSession.InterruptionType(rawValue: raw) == .began else { return }
            Task { @MainActor in self?.pause() }
        })
        notifications.append(NotificationCenter.default.addObserver(forName: AVAudioSession.routeChangeNotification, object: nil, queue: .main) { [weak self] notification in
            guard let value = notification.userInfo?[AVAudioSessionRouteChangeReasonKey] as? UInt,
                  AVAudioSession.RouteChangeReason(rawValue: value) == .oldDeviceUnavailable else { return }
            Task { @MainActor in self?.pause() }
        })
        notifications.append(NotificationCenter.default.addObserver(forName: AVAudioSession.mediaServicesWereResetNotification, object: nil, queue: .main) { [weak self] _ in
            Task { @MainActor in
                guard let self else { return }
                self.stop()
                // Audio objects are orphaned by a media-services reset.
                self.local = LocalAudioEngine()
                self.bindLocalCallbacks()
                self.message = "Audio services restarted. Choose your music again."
            }
        })
        notifications.append(NotificationCenter.default.addObserver(forName: MAMusicHapticsManager.activeStatusDidChangeNotification, object: nil, queue: .main) { [weak self] _ in
            Task { @MainActor in await self?.updateAppleHaptics() }
        })
    }

    private func bindLocalCallbacks() {
        local.onFinish = { [weak self] in self?.finished() }
        local.onHapticError = { [weak self] _ in
            guard self?.playbackSource == .files else { return }
            self?.hapticStatus = "Haptics paused. Pause and play again to retry."
        }
    }

    func open(_ url: URL) async {
        stop()
        let token = UUID(); operation = token
        busy = true
        defer { if operation == token { busy = false } }
        let scope = url.startAccessingSecurityScopedResource()
        defer { if scope { url.stopAccessingSecurityScopedResource() } }
        do {
            let copy = try await Task.detached(priority: .userInitiated) {
                let directory = FileManager.default.temporaryDirectory.appendingPathComponent("SongWaveImports", isDirectory: true)
                try FileManager.default.createDirectory(at: directory, withIntermediateDirectories: true)
                let target = directory.appendingPathComponent(UUID().uuidString).appendingPathExtension(url.pathExtension)
                try FileManager.default.copyItem(at: url, to: target)
                return target
            }.value
            guard token == operation else { try? FileManager.default.removeItem(at: copy); return }
            do { try local.load(copy) } catch { try? FileManager.default.removeItem(at: copy); throw error }
            if let old = currentImport { try? FileManager.default.removeItem(at: old) }
            currentImport = copy
            playbackSource = .files; source = .files
            selectedSong = nil; artwork = nil; fileArtwork = nil
            title = url.deletingPathExtension().lastPathComponent
            artist = "Local audio · processed on this iPhone"
            duration = local.duration; position = 0; ready = false; message = nil
            hapticStatus = local.supportsHaptics ? "Custom haptics work while SongWave is on screen." : "This device cannot produce custom Core Haptics feedback."
            configureLocal()
            let metadata = try? await AVURLAsset(url: copy).load(.commonMetadata)
            guard token == operation else { return }
            for item in metadata ?? [] {
                guard token == operation else { return }
                if item.commonKey == .commonKeyTitle, let value = try? await item.load(.stringValue), !value.isEmpty { guard token == operation else { return }; title = value }
                if item.commonKey == .commonKeyArtist, let value = try? await item.load(.stringValue) { guard token == operation else { return }; artist = value }
                if item.commonKey == .commonKeyArtwork, let data = try? await item.load(.dataValue), data.count <= 2_097_152 { guard token == operation else { return }; fileArtwork = thumbnail(data) }
            }
            guard token == operation else { return }
            ready = true
            bindLocalRemoteControls()
            updateNowPlaying()
        } catch {
            guard token == operation else { return }
            local.stop(); ready = false
            message = "This audio file couldn’t be opened. Try a mono or stereo audio file."
        }
    }

    func connect() async {
        let permission = await MusicAuthorization.request()
        connected = permission == .authorized
        if !connected { message = "Apple Music access wasn’t granted. You can still open an audio file." }
    }

    func search(_ query: String) async {
        guard connected, !searching else { return }
        let term = query.trimmingCharacters(in: .whitespacesAndNewlines)
        guard !term.isEmpty else { return }
        searching = true
        defer { searching = false }
        do {
            var request = MusicCatalogSearchRequest(term: term, types: [Song.self])
            request.limit = 20
            songs = Array(try await request.response().songs)
            message = songs.isEmpty ? "No songs found." : nil
        } catch { message = "Apple Music couldn’t connect. Try again, or open an audio file." }
    }

    func select(_ song: Song) async {
        stop()
        playbackSource = .appleMusic; source = .appleMusic; selectedSong = song
        MPRemoteCommandCenter.shared().changePlaybackPositionCommand.isEnabled = true
        music.queue = ApplicationMusicPlayer.Queue(for: [song])
        title = song.title; artist = song.artistName; artwork = song.artwork?.url(width: 300, height: 300)
        fileArtwork = nil; duration = song.duration ?? 0; position = 0; ready = true
        updateNowPlaying()
        await updateAppleHaptics()
    }

    func toggle() async {
        if isPlaying { pause(); return }
        guard ready, !busy, !starting else { return }
        guard playbackSource != .files || foreground || audible else {
            message = "Open SongWave to start haptics-only playback."; return
        }
        let token = UUID(); transportID = token
        let intendedSource = playbackSource
        starting = true
        defer { if transportID == token { starting = false } }
        do {
            try AVAudioSession.sharedInstance().setCategory(.playback, mode: .default)
            try AVAudioSession.sharedInstance().setActive(true)
            if intendedSource == .files {
                configureLocal(); try local.play(); local.setForeground(foreground); position = local.position
            } else { try await music.play() }
            guard token == transportID, intendedSource == playbackSource else {
                settleCancelledAppleStart(); return
            }
            isPlaying = true; message = nil
            updateNowPlaying(); startProgress()
            if intendedSource == .appleMusic { Task { [weak self] in await self?.updateAppleHaptics() } }
        } catch {
            guard token == transportID else { settleCancelledAppleStart(); return }
            message = "Playback couldn’t start. Apple Music playback may require a subscription and a configured app build."
            try? AVAudioSession.sharedInstance().setActive(false, options: .notifyOthersOnDeactivation)
        }
    }

    private func settleCancelledAppleStart() {
        // Never stop a newer desired Apple Music request; enforce Stop, Pause,
        // or a switch to local files if the older asynchronous start completes.
        if playbackSource != .appleMusic || (!isPlaying && !starting) { music.stop(); updateNowPlaying() }
    }

    func pause() {
        transportID = UUID(); starting = false
        if playbackSource == .files { position = local.position; local.pause() } else { position = music.playbackTime; music.pause() }
        isPlaying = false; progress?.cancel(); progress = nil
        try? AVAudioSession.sharedInstance().setActive(false, options: .notifyOthersOnDeactivation)
        updateNowPlaying()
    }
    func stop() {
        operation = UUID(); transportID = UUID(); starting = false; busy = false
        clearRemoteControls()
        local.stop(); music.stop()
        isPlaying = false; ready = false; position = 0
        progress?.cancel(); progress = nil
        MPNowPlayingInfoCenter.default().nowPlayingInfo = nil
        try? AVAudioSession.sharedInstance().setActive(false, options: .notifyOthersOnDeactivation)
    }
    func stopPlayback() {
        stop()
        do {
            if playbackSource == .files, let currentImport {
                try local.load(currentImport); configureLocal(); ready = true; bindLocalRemoteControls()
            } else if let selectedSong {
                music.queue = ApplicationMusicPlayer.Queue(for: [selectedSong]); ready = true
            }
        } catch { message = "Choose the file again to restart playback." }
        updateNowPlaying()
    }

    private func finished() {
        guard playbackSource == .files else { return }
        isPlaying = false; ready = true; position = duration
        progress?.cancel(); progress = nil; local.pause()
        try? AVAudioSession.sharedInstance().setActive(false, options: .notifyOthersOnDeactivation)
        updateNowPlaying()
    }
    private func thumbnail(_ data: Data) -> UIImage? {
        guard let source = CGImageSourceCreateWithData(data as CFData, [kCGImageSourceShouldCache: false] as CFDictionary),
              let image = CGImageSourceCreateThumbnailAtIndex(source, 0, [kCGImageSourceCreateThumbnailFromImageAlways: true,
                  kCGImageSourceThumbnailMaxPixelSize: 512, kCGImageSourceCreateThumbnailWithTransform: true] as CFDictionary) else { return nil }
        return UIImage(cgImage: image)
    }

    private func configureLocal() { local.configure(focus: focus, intensity: intensity, audible: audible) }

    func setForeground(_ active: Bool) {
        foreground = active
        if playbackSource == .files {
            local.setForeground(active)
            if !active && !audible && isPlaying { pause() }
        }
        if active && isPlaying { startProgress() }
        else { progress?.cancel(); progress = nil }
    }

    private func startProgress() {
        progress?.cancel()
        guard foreground else { return }
        progress = Task { [weak self] in
            while !Task.isCancelled {
                try? await Task.sleep(for: .milliseconds(250))
                guard !Task.isCancelled, let self, self.isPlaying else { return }
                self.position = self.playbackSource == .files ? self.local.position : self.music.playbackTime
                if self.playbackSource == .appleMusic && self.music.state.playbackStatus != .playing { self.pause() }
            }
        }
    }

    private func clearRemoteControls() {
        for (command, token) in remoteTargets { command.removeTarget(token) }
        remoteTargets.removeAll()
    }

    private func bindLocalRemoteControls() {
        clearRemoteControls()
        let center = MPRemoteCommandCenter.shared()
        center.changePlaybackPositionCommand.isEnabled = false
        for command in [center.playCommand, center.pauseCommand, center.togglePlayPauseCommand, center.stopCommand] { command.isEnabled = true }
        remoteTargets.append((center.playCommand, center.playCommand.addTarget { [weak self] _ in
            Task { @MainActor in guard let self, !self.isPlaying else { return }; await self.toggle() }; return .success
        }))
        remoteTargets.append((center.pauseCommand, center.pauseCommand.addTarget { [weak self] _ in
            Task { @MainActor in self?.pause() }; return .success
        }))
        remoteTargets.append((center.togglePlayPauseCommand, center.togglePlayPauseCommand.addTarget { [weak self] _ in
            Task { @MainActor in await self?.toggle() }; return .success
        }))
        remoteTargets.append((center.stopCommand, center.stopCommand.addTarget { [weak self] _ in
            Task { @MainActor in self?.stopPlayback() }; return .success
        }))
    }

    private func updateNowPlaying() {
        var info: [String: Any] = [MPMediaItemPropertyTitle: title, MPMediaItemPropertyArtist: artist,
            MPMediaItemPropertyPlaybackDuration: duration, MPNowPlayingInfoPropertyElapsedPlaybackTime: position,
            MPNowPlayingInfoPropertyPlaybackRate: isPlaying ? 1.0 : 0.0]
        if playbackSource == .appleMusic, let isrc = selectedSong?.isrc {
            info[MPNowPlayingInfoPropertyInternationalStandardRecordingCode] = isrc
        }
        MPNowPlayingInfoCenter.default().nowPlayingInfo = info
    }

    private func updateAppleHaptics() async {
        guard playbackSource == .appleMusic, let song = selectedSong else { return }
        guard MAMusicHapticsManager.shared.isActive else {
            hapticStatus = "Turn on Music Haptics in Settings → Accessibility → Music Haptics."
            return
        }
        guard let code = song.isrc else { hapticStatus = "This song has no haptic-track identifier."; return }
        let available = await withCheckedContinuation { continuation in
            MAMusicHapticsManager.shared.checkHapticTrackAvailabilityForMedia(matchingCode: code) { continuation.resume(returning: $0) }
        }
        guard selectedSong?.id == song.id else { return }
        guard MAMusicHapticsManager.shared.isActive else { hapticStatus = "Music Haptics is off in Settings."; return }
        hapticStatus = available ? "Apple Music haptic track available. Apple controls its mix and intensity." : "No Apple Music haptic track is available for this song."
    }
}
