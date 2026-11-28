import AVFoundation
import CoreAudio
import SoundAnalysis

// A new gate starts closed. Multiple overlapping music windows are required to open it.
// Dominant speech pauses output. Strong music evidence keeps sung passages open.
final class MusicGate: NSObject, SNResultsObserving {
    private let analyzer: SNAudioStreamAnalyzer
    private let format: AVAudioFormat
    private let queue = DispatchQueue(label: "songwave.music-recognition", qos: .userInitiated)
    private let capacity = DispatchSemaphore(value: 2)
    private let lock = NSLock()
    private var pending: [Float] = []
    private var framePosition: Int64 = 0
    private var consecutiveMusic = 0
    private var speechUntil = 0.0
    private var lastResult = 0.0
    private var probability = 0.0
    private var lastSpeech = false

    init(rate: Double) throws {
        guard let format = AVAudioFormat(standardFormatWithSampleRate: rate, channels: 1) else {
            throw GlassError("Music recognition could not read this audio format.")
        }
        self.format = format
        analyzer = SNAudioStreamAnalyzer(format: format)
        super.init()
        let request = try SNClassifySoundRequest(classifierIdentifier: .version1)
        request.windowDuration = CMTime(seconds: 1, preferredTimescale: 48_000)
        request.overlapFactor = 0.5
        try analyzer.add(request, withObserver: self)
    }

    func finish() { queue.async { [analyzer] in analyzer.removeAllRequests() } }

    func push(_ samples: [Float]) {
        pending.append(contentsOf: samples)
        guard pending.count >= Int(format.sampleRate / 4) else { return }
        let position = framePosition
        framePosition += Int64(pending.count)
        defer { pending.removeAll(keepingCapacity: true) }
        guard capacity.wait(timeout: .now()) == .success else { return }
        guard let buffer = AVAudioPCMBuffer(pcmFormat: format, frameCapacity: AVAudioFrameCount(pending.count)),
              let channel = buffer.floatChannelData?[0] else {
            capacity.signal()
            return
        }
        buffer.frameLength = buffer.frameCapacity
        pending.withUnsafeBufferPointer { channel.update(from: $0.baseAddress!, count: $0.count) }
        queue.async { [analyzer, capacity] in
            analyzer.analyze(buffer, atAudioFramePosition: position)
            capacity.signal()
        }
    }

    var decision: (confidence: Double, speech: Bool) {
        lock.lock()
        defer { lock.unlock() }
        let now = ProcessInfo.processInfo.systemUptime
        guard now - lastResult < 1.5 else { return (0, false) }
        return (consecutiveMusic >= 2 && now >= speechUntil ? probability : 0, lastSpeech || now < speechUntil)
    }

    func request(_ request: SNRequest, didProduce result: SNResult) {
        guard let classification = result as? SNClassificationResult else { return }
        let music = ["music", "singing", "choir_singing", "piano", "acoustic_guitar", "electric_guitar",
                     "keyboard_musical", "bowed_string_instrument", "drum_kit"]
        var musical = 0.0
        var speech = 0.0
        for item in classification.classifications {
            if item.identifier == "speech" || item.identifier == "conversation" { speech = max(speech, item.confidence) }
            if music.contains(item.identifier) { musical = max(musical, item.confidence) }
        }
        lock.lock()
        defer { lock.unlock() }
        lastResult = ProcessInfo.processInfo.systemUptime
        lastSpeech = speech >= 0.30 && speech > musical * 1.15
        if lastSpeech { speechUntil = lastResult + 6 }
        consecutiveMusic = musical >= 0.55 && !lastSpeech ? min(2, consecutiveMusic + 1) : 0
        if consecutiveMusic >= 2 && musical >= 0.75 && speech < 0.18 { speechUntil = 0 }
        probability = musical
    }

    func request(_ request: SNRequest, didFailWithError error: Error) {
        lock.lock()
        probability = 0
        consecutiveMusic = 0
        lock.unlock()
    }
}

struct AudioClient {
    let id: AudioObjectID
    let bundle: String
    let isCall: Bool
    let isDictationService: Bool
    let dictationInputActive: Bool

    init?(id: AudioObjectID) {
        var output: UInt32 = 0
        var input: UInt32 = 0
        var pid: pid_t = 0
        _ = AudioHardware.read(id, kAudioProcessPropertyIsRunningOutput, into: &output)
        _ = AudioHardware.read(id, kAudioProcessPropertyIsRunningInput, into: &input)
        guard output != 0 || input != 0,
              AudioHardware.read(id, kAudioProcessPropertyPID, into: &pid) == noErr,
              pid != getpid(), pid > 0 else { return nil }
        var identifier: Unmanaged<CFString>?
        var bundle = ""
        if AudioHardware.read(id, kAudioProcessPropertyBundleID, into: &identifier) == noErr {
            bundle = (identifier?.takeRetainedValue() as String?) ?? ""
        }
        var path = [CChar](repeating: 0, count: Int(MAXPATHLEN) * 4)
        _ = proc_pidpath(pid, &path, UInt32(path.count))
        let executable = String(cString: path)
        let identity = (bundle + " " + executable).lowercased()
        let callIDs = ["facetime", "avconferenced", "avconference", "callservicesd", "zoom.us", "us.zoom",
                       "microsoft.teams", "com.hnc.discord", "discord.app", "com.apple.telephony"]
        if ["coreaudiod", "studio.songwave", "eqmac", "backgroundmusic", "loopback",
            "soundsource"].contains(where: identity.contains) { return nil }
        let browser = ["safari", "webkit", "chrome", "firefox", "mozilla", "msedge", "brave"].contains(where: identity.contains)
        let call = (input != 0 && browser) || callIDs.contains(where: identity.contains)
        // CoreSpeech is macOS Dictation, not a music source. Read its activity
        // only; never create a tap for its microphone or speech-service output.
        let dictation = bundle.caseInsensitiveCompare("com.apple.CoreSpeech") == .orderedSame
        guard output != 0 || call || (dictation && input != 0) else { return nil }
        isDictationService = dictation
        dictationInputActive = dictation && input != 0
        self.id = id
        if identity.contains("com.spotify.client") || identity.contains("/spotify.app/") { self.bundle = "com.spotify.client" }
        else if identity.contains("com.apple.music ") || identity.contains("/music.app/") { self.bundle = "com.apple.Music" }
        else { self.bundle = bundle.isEmpty ? executable : bundle }
        isCall = call
    }
}

// Both automatic discovery and an explicitly selected player use the same call
// rule. AudioClient excludes inactive processes before assigning isCall, so an
// open but idle FaceTime window does not suppress music.
enum CallAudioPolicy {
    static func active(in clients: [AudioClient]) -> Bool {
        clients.contains(where: \.isCall)
    }
}

private final class MusicFeed {
    let tap: AudioTap
    let bundle: String
    var gate: MusicGate?
    var samples: [Float] = []
    var peak: Float = 0
    private var lastSound = 0.0

    init(tap: AudioTap, bundle: String) {
        self.bundle = bundle
        self.tap = tap
    }

    deinit { gate?.finish() }

    func read(now: Double, allowClassification: Bool) throws {
        guard !tap.needsReconnect else { throw CaptureFault.routeChanged }
        tap.ring.takeNewest(maximum: Int(tap.rate * 0.08), into: &samples)
        peak = samples.reduce(0) { max($0, abs($1)) }
        if peak > 0.00015 { lastSound = now }
        let analyze = allowClassification && now - lastSound < 1.5
        if analyze, gate == nil { gate = try MusicGate(rate: tap.rate) }
        if analyze { gate?.push(samples) }
        else if let gate { gate.finish(); self.gate = nil }
    }
}

final class MacMusicInput {
    private var feeds: [AudioObjectID: MusicFeed] = [:]
    private var pending: [AudioObjectID: (bundle: String, started: Double, request: CaptureRequest)] = [:]
    private let requestTap: (CATapDescription, Bool) -> CaptureRequest?

    init(requestTap: @escaping (CATapDescription, Bool) -> CaptureRequest? = { CaptureRequest(description: $0, mute: $1) }) {
        self.requestTap = requestTap
    }
    deinit { for value in pending.values { value.request.cancel() } }
    var confirmedPlayer: String?
    var idle: Bool {
        if pending.values.contains(where: { lastRead - $0.started < 1 }) { return false }
        return feeds.isEmpty || lastRead - lastInput > 2
    }
    private var retryAfter: [AudioObjectID: Double] = [:]
    private var scanAfter = 0.0
    private var callActive = false
    private(set) var dictationActive = false
    private var dictationUntil = -Double.infinity
    private(set) var status = "Listening for music"
    private(set) var captureFailed = false
    private(set) var activeBundle: String?
    private var selected: AudioObjectID?
    private var lastMusic = 0.0
    private var lastInput = 0.0
    private var lastRead = 0.0
    private var tabs: [YouTubeState] = []
    private(set) var video: YouTubeState?
    private(set) var suppressOutput = false

    func read(now: Double, mute: Bool, receive: ([Float], Double, Bool) throws -> Void) throws {
        lastRead = now
        if now >= scanAfter {
            scanAfter = now + 0.35
            tabs = YouTubeState.playing()
            let clients = AudioHardware.processList().compactMap(AudioClient.init)
            callActive = CallAudioPolicy.active(in: clients)
            if clients.contains(where: \.dictationInputActive) { dictationUntil = now + 2 }
            dictationActive = now < dictationUntil
            let sources = clients.filter { !$0.isDictationService }
            let eligible = callActive ? [] : sources.map(\.id)
            let allowed = Set(eligible)
            let identities = Dictionary(uniqueKeysWithValues: sources.map { ($0.id, $0.bundle) })
            feeds = feeds.filter { allowed.contains($0.key) && identities[$0.key] == $0.value.bundle }
            pending = pending.filter {
                let keep = allowed.contains($0.key) && identities[$0.key] == $0.value.bundle
                if !keep { $0.value.request.cancel() }
                return keep
            }
            if let selected, feeds[selected] == nil { self.selected = nil }
            retryAfter = retryAfter.filter { allowed.contains($0.key) }
            if !callActive {
                for client in sources where feeds[client.id] == nil && pending[client.id] == nil && now >= retryAfter[client.id, default: 0] {
                    if let request = requestTap(CATapDescription(stereoMixdownOfProcesses: [client.id]), false) {
                        pending[client.id] = (client.bundle, now, request)
                    } else { retryAfter[client.id] = now + 3 }
                }
            }
        }
        for (id, value) in pending {
            if let result = value.request.takeResult() {
                pending.removeValue(forKey: id)
                switch result {
                case .success(let tap): feeds[id] = MusicFeed(tap: tap, bundle: value.bundle)
                case .failure(let error): retryAfter[id] = now + 3; status = error.localizedDescription
                }
            } else if now - value.started >= 8 {
                value.request.cancel()
                pending.removeValue(forKey: id)
                retryAfter[id] = now + 3
            }
        }
        captureFailed = feeds.isEmpty && pending.isEmpty && !retryAfter.isEmpty && !callActive
        var best: AudioObjectID?
        var score = 0.0
        var speech = false
        var excludedVideo = false
        var selectedVideo: YouTubeState?
        var candidatePlayer: String?
        var eligibleMute = Set<AudioObjectID>()
        for (id, feed) in feeds {
            let player = feed.bundle == "com.spotify.client" || feed.bundle == "com.apple.Music"
            let confirmed = player && feed.bundle == confirmedPlayer
            let family = YouTubeState.family(for: feed.bundle)
            let videos = tabs.filter { $0.browser == family }
            do {
                try feed.read(now: now, allowClassification: !confirmed && videos.isEmpty)
            } catch {
                // A failed recognizer or disappearing client must not stop other players.
                feeds.removeValue(forKey: id)
                if selected == id { selected = nil }
                retryAfter[id] = now + (error is CaptureFault ? 0 : 3)
                continue
            }
            if feed.peak > 0.00015 { lastInput = now }
            if player && feed.peak > 0.0001 { candidatePlayer = feed.bundle }
            let decision = feed.gate?.decision ?? (confidence: 0.0, speech: false)
            speech = speech || decision.speech

            if videos.contains(where: { $0.category != "music" }) {
                excludedVideo = true
                continue
            }
            let confidence = confirmed ? 1.1 : videos.isEmpty ? decision.confidence : 1
            if confidence > 0 { eligibleMute.insert(id) }
            guard feed.peak > 0.00015 else { continue }
            let weight = confidence * (id == selected ? 1.12 : 1)
            if weight > score {
                score = weight
                best = id
                selectedVideo = videos.first
            }
        }
        for (id, feed) in feeds {
            let shouldMute = mute && eligibleMute.contains(id) && (id == best || (best == nil && id == selected && now - lastMusic < 1.5))
            do {
                try feed.tap.setMuted(shouldMute)
            } catch {
                feeds.removeValue(forKey: id)
                retryAfter[id] = now + (feed.tap.needsReconnect ? 0 : 3)
                if selected == id { selected = nil }
            }
        }
        let lostRoute = best.map { feeds[$0] == nil } ?? false
        if lostRoute { best = nil }
        suppressOutput = callActive || lostRoute || (best == nil && (speech || excludedVideo || selected == nil))
        if let best, let feed = feeds[best] {
            try receive(feed.samples, feed.tap.rate, selected != best)
            video = selectedVideo
            activeBundle = feed.bundle
            lastMusic = now
            selected = best
            status = "Music detected"
        } else {
            if callActive || excludedVideo || now - lastMusic > 1.5 {
                activeBundle = candidatePlayer
                video = nil
                selected = nil
            } else if let video, !tabs.contains(where: { $0.browser == video.browser && $0.videoID == video.videoID }) {
                self.video = nil
            }
            if feeds.isEmpty, !pending.isEmpty, !callActive { status = "Connecting to Mac audio…"; return }
            if captureFailed { status = "Audio capture unavailable · open Listening help"; return }
            if callActive { status = "Paused for call audio" }
            else if excludedVideo { status = "YouTube video · haptics paused" }
            else if speech { status = "Speech · haptics paused" }
            else { status = now - lastInput > 2 ? "Waiting for Mac audio" : "Listening for music" }
        }
    }
}
