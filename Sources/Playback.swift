import AVFoundation
import CoreAudio
import Foundation

struct PlaybackUpdate {
    var signal = SignalFrame.empty
    var elapsed: Double = 0
    var duration: Double?
    var device: String?
    var waiting = false
    var video: YouTubeState?
    var appBundle: String?
    var detection: String?
    var processingDelay: Double = 0
    var partyOverheated = false
    var finished = false
    var error: String?
}

// Manual bypass is a short gain ramp. Capture and beat analysis keep advancing
// during it; call/error suppression is a separate immediate stop at the output.
struct UserHapticsGain {
    private var value = 1.0
    private var origin = 1.0
    private var target = 1.0
    private var startedAt = 0.0
    private var previousTime: Double?

    mutating func level(enabled: Bool, at now: Double) -> Double {
        let next = enabled ? 1.0 : 0.0
        guard now.isFinite else { self = UserHapticsGain(); return next }
        if previousTime == nil || previousTime.map({ now < $0 || now - $0 > 0.2 }) == true {
            value = next; origin = next; target = next; startedAt = now
        } else {
            let progress = min(1, max(0, (now - startedAt) / 0.14))
            value = origin + (target - origin) * progress * progress * (3 - 2 * progress)
            if next != target { origin = value; target = next; startedAt = now }
        }
        previousTime = now
        return value
    }
}

final class Playback {
    private let queue = DispatchQueue(label: "songwave.playback", qos: .userInteractive)
    private var session: Session?
    private var checkID = UUID()
    private var checkTimer: DispatchSourceTimer?
    private var checkMotor: Trackpad?
    private func cancelCheck() { checkID = UUID(); checkTimer?.cancel(); checkTimer = nil; checkMotor = nil }

    // Invoked only by the explicit Test trackpad action. No audio player exists.
    func testTrackpad(_ result: @escaping (String?) -> Void) {
        queue.async { [self] in
            cancelCheck(); session?.stop(); session = nil
            do {
                guard !CallAudioPolicy.active(in: AudioHardware.processList().compactMap(AudioClient.init)) else {
                    throw GlassError("End the call before testing the trackpad.")
                }
                checkMotor = try Trackpad()
                let token = checkID
                let started = ProcessInfo.processInfo.systemUptime
                var sequence = TrackpadCheckSequence()
                var played = 0
                let timer = DispatchSource.makeTimerSource(queue: queue)
                timer.schedule(deadline: .now(), repeating: .milliseconds(20), leeway: .milliseconds(1))
                timer.setEventHandler { [weak self] in
                    guard let self, self.checkID == token, let motor = self.checkMotor else { return }
                    let elapsed = ProcessInfo.processInfo.systemUptime - started
                    do {
                        if elapsed >= TrackpadCheckSequence.duration {
                            self.cancelCheck()
                            let failure = played == 3 ? nil : "The test was interrupted. Retry when the Mac is less busy."
                            DispatchQueue.main.async { result(failure) }; return
                        }
                        if sequence.pulse(at: elapsed) {
                            guard !CallAudioPolicy.active(in: AudioHardware.processList().compactMap(AudioClient.init)) else {
                                throw GlassError("End the call before testing the trackpad.")
                            }
                            try motor.play([Tone(hertz: 125, weight: 1)], for: 16, level: 0.35)
                            played += 1
                        }
                    } catch {
                        self.cancelCheck()
                        let message = error.localizedDescription
                        DispatchQueue.main.async { result(message) }
                    }
                }
                checkTimer = timer; timer.resume()
            } catch {
                cancelCheck()
                let message = error.localizedDescription
                DispatchQueue.main.async { result(message) }
            }
        }
    }
    private var followVolume = false
    private var keyboard = false
    private var partyKeyboard = false
    private var pattern: HapticPattern?
    func setPattern(_ pattern: HapticPattern?) {
        queue.async { self.pattern = pattern; self.session?.patternPlayer = pattern.map(HapticPattern.Player.init) }
    }
    func setEffects(followVolume: Bool, keyboard: Bool, partyKeyboard: Bool = false) {
        queue.async {
            self.followVolume = followVolume
            self.keyboard = keyboard
            self.partyKeyboard = partyKeyboard
            self.session?.followVolume = followVolume
            self.session?.lighting = keyboard
            self.session?.partyLighting = partyKeyboard
        }
    }
    func party(until deadline: Double) { queue.async { self.session?.partyEnd = deadline } }
    func confirmPlayer(_ bundle: String?) { queue.async { self.session?.macMusic?.confirmedPlayer = bundle } }
    func shutDown(_ completion: @escaping () -> Void) {
        queue.async {
            self.cancelCheck()
            self.session?.stop()
            self.session = nil
            DispatchQueue.main.async(execute: completion)
        }
    }

    func probe(_ result: @escaping (String?, String?) -> Void) {
        queue.async {
            do {
                let device = try Trackpad().name
                DispatchQueue.main.async { result(device, nil) }
            } catch {
                let message = error.localizedDescription
                DispatchQueue.main.async { result(nil, message) }
            }
        }
    }

    func start(_ source: PlaybackSource, tuning: Tuning, mode: OutputMode, playerPath: String?,
               startAt: Double, partyDeadline: Double = 0, hapticsEnabled: Bool = true, update: @escaping (PlaybackUpdate) -> Void) {
        queue.async {
            self.cancelCheck()
            self.session?.stop()
            self.session = nil
            do {
                let run = try Session(source: source, playerPath: playerPath, tuning: tuning, mode: mode,
                                      startAt: startAt, update: update)
                run.hapticsEnabled = hapticsEnabled
                run.patternPlayer = self.pattern.map(HapticPattern.Player.init)
                run.followVolume = self.followVolume
                run.lighting = self.keyboard
                run.partyLighting = self.partyKeyboard
                run.partyEnd = partyDeadline
                self.session = run
                run.start(on: self.queue)
            } catch {
                let message = error.localizedDescription
                DispatchQueue.main.async { update(PlaybackUpdate(error: message)) }
            }
        }
    }

    func stop() {
        queue.async {
            self.cancelCheck()
            self.session?.stop()
            self.session = nil
        }
    }

    func setMacMode(_ mode: OutputMode) {
        queue.async {
            guard let session = self.session, session.source == .macAudio else { return }
            session.mode = mode
            let idle = session.macMusic?.idle == true
            session.timer?.schedule(deadline: .now(), repeating: .milliseconds(idle ? 350 : session.renderMilliseconds), leeway: .milliseconds(idle ? 40 : 1))
            session.delayedFrames.removeAll(keepingCapacity: true)
            session.resetHapticState()
        }
    }
    func setHaptics(_ enabled: Bool) {
        queue.async { self.session?.hapticsEnabled = enabled }
    }

    func set(tuning: Tuning) {
        queue.async { self.session?.tuning = tuning }
    }
}

private final class Session {
    let source: PlaybackSource
    let playerPath: String?
    var tuning: Tuning
    var mode: OutputMode
    var timer: DispatchSourceTimer?
    var followVolume = false
    var lighting = false
    var partyLighting = false
    var partyEnd = 0.0
    private var keyboard: KeyboardLight?
    private var lightUnavailable = false
    private var volume = 1.0
    private var nextVolume = 0.0
    private var nextTiming = 0.0
    private var reportedDelay = 0.0
    var renderMilliseconds: Int { analysisMode == .assist ? 8 : 16 }
    private var analysisMode: OutputMode { tuning.focus(for: mode).analysisMode }
    private var analyzedMode: OutputMode?
    private var analyzedFocus: HapticFocus?
    private var sleeping = false
    private var motorEnvelope = MotorEnvelope()
    private var userHapticsGain = UserHapticsGain()
    private var playerCallActive = false
    private var nextCallScan = 0.0
    private var outputSuppressed: Bool { playerCallActive || macMusic?.suppressOutput == true }
    var motor: Trackpad?
    var tap: AudioTap?
    var macMusic: MacMusicInput?
    var hapticsEnabled = true
    var spectrum: Spectrum?
    var file: AVAudioFile?
    var buffer: AVAudioPCMBuffer?
    var speaker: AVAudioPlayer?
    var scratch: [Float] = []
    var sourceRate: Double = 24_000
    var divisor = 1
    var decimationCount = 0
    var decimationSum: Float = 0
    var position: Int64 = 0
    var duration: Double?
    var lastTick = ProcessInfo.processInfo.systemUptime
    var nextScan: Double = 0
    var lastAudio: Double?
    var endedAt: Double?
    var connectedProcesses: [AudioObjectID] = []
    var updateCounter = 0
    private var visualBeat = 0.0
    private var visualBeatFrequency = 125.0
    var delayedFrames: [(time: Double, signal: SignalFrame)] = []
    var assistTail = AssistTail()
    var patternPlayer: HapticPattern.Player?
    private var automaticHaptics = AutomaticHaptics()
    private var isolator: IsolatedVocals?
    private var isolationActive = false
    private var rawSamples: [Float] = []
    private var vocalSamplesPlayed = 0.0
    private var vocalReadRemainder = 0.0
    private var vocalStartPosition = 0.0
    private var isolationFinished = false
    private var lastSourceInput = 0.0
    private var wantsIsolation: Bool { tuning.usesVocalIsolation(for: mode) }
    let update: (PlaybackUpdate) -> Void

    init(source: PlaybackSource, playerPath: String?, tuning: Tuning, mode: OutputMode,
         startAt: Double, update: @escaping (PlaybackUpdate) -> Void) throws {
        self.source = source
        self.playerPath = playerPath
        self.tuning = tuning
        self.mode = mode
        self.update = update
        switch source {
        case .file(let url):
            let input = try AVAudioFile(forReading: url, commonFormat: .pcmFormatFloat32, interleaved: false)
            guard input.length > 0, input.processingFormat.sampleRate > 0,
                  let buffer = AVAudioPCMBuffer(pcmFormat: input.processingFormat, frameCapacity: 16_384) else {
                throw GlassError("This audio file is empty or has an unsupported format.")
            }
            if mode == .assist { speaker = try AVAudioPlayer(contentsOf: url) }
            file = input
            self.buffer = buffer
            duration = Double(input.length) / input.processingFormat.sampleRate
            try setupSpectrum(rate: input.processingFormat.sampleRate)
        case .macAudio, .player:
            break
        }
        if let duration {
            position = Int64(min(duration, max(0, startAt)) * sourceRate)
            file?.framePosition = position
            speaker?.currentTime = Double(position) / sourceRate
        }
        motor = try Trackpad()
        if source == .macAudio {
            macMusic = MacMusicInput()
        }
        if let speaker, !speaker.prepareToPlay() {
            throw GlassError("The speaker audio could not be prepared.")
        }
        scratch.reserveCapacity(16_384)
        rawSamples.reserveCapacity(16_384)
        vocalStartPosition = startAt
    }

    func resetHapticState() {
        assistTail = AssistTail()
        automaticHaptics = AutomaticHaptics()
        motorEnvelope = MotorEnvelope()
        userHapticsGain = UserHapticsGain()
    }

    func setupSpectrum(rate: Double) throws {
        assistTail = AssistTail()
        automaticHaptics = AutomaticHaptics()
        motorEnvelope = MotorEnvelope()
        userHapticsGain = UserHapticsGain()
        delayedFrames.removeAll(keepingCapacity: true)
        if wantsIsolation {
            if let isolator { isolator.reset() }
            else { isolator = IsolatedVocals() }
        } else {
            isolator?.cancel()
            isolator = nil
        }
        rawSamples.removeAll(keepingCapacity: true)
        vocalSamplesPlayed = 0
        vocalReadRemainder = 0
        vocalStartPosition = Double(position) / max(1, sourceRate)
        isolationFinished = false
        isolationActive = wantsIsolation
        analyzedMode = analysisMode
        analyzedFocus = tuning.focus(for: mode)
        sourceRate = rate
        divisor = max(1, Int(rate / 24_000))
        decimationCount = 0
        decimationSum = 0
        spectrum = try Spectrum(sampleRate: isolationActive ? 24000 : rate / Double(divisor))
        spectrum?.configure(tuning.eq)
    }

    private func connect(_ description: CATapDescription) throws {
        let connection = try AudioTap(description: description, mute: mode == .trackpad)
        try setupSpectrum(rate: connection.rate)
        tap = connection
    }

    private func readTap() -> Bool {
        guard let tap else { return false }
        tap.ring.takeNewest(maximum: Int(sourceRate * 0.08), into: &scratch)
        for sample in scratch { append(sample) }
        return !scratch.isEmpty
    }

    func start(on queue: DispatchQueue) {
        if let speaker, !speaker.play() {
            stop()
            publish(PlaybackUpdate(error: "The speaker audio could not start."))
            return
        }
        let timer = DispatchSource.makeTimerSource(queue: queue)
        timer.schedule(deadline: .now(), repeating: .milliseconds(renderMilliseconds), leeway: .milliseconds(1))
        timer.setEventHandler { [weak self] in self?.tick() }
        self.timer = timer
        lastTick = ProcessInfo.processInfo.systemUptime - 0.016
        timer.resume()
    }

    func stop() {
        timer?.cancel()
        timer = nil
        keyboard = nil
        partyEnd = 0
        tap = nil
        macMusic = nil
        speaker?.stop()
        isolator?.cancel()
        isolator = nil
        rawSamples.removeAll(keepingCapacity: true)
        motor = nil
    }

    func publish(_ value: PlaybackUpdate) {
        DispatchQueue.main.async { [update] in update(value) }
    }

    func append(_ sample: Float) {
        if isolationActive { rawSamples.append(sample); return }
        decimationSum += sample
        decimationCount += 1
        if decimationCount == divisor {
            spectrum?.append(decimationSum / Float(divisor))
            decimationCount = 0
            decimationSum = 0
        }
    }

    func tick() {
        let now = ProcessInfo.processInfo.systemUptime
        var tuning = UltraDynamics.tuning(self.tuning, active: partyEnd > now, output: mode)
        // Do not send mixed PCM down the already-isolated spectrum branch.
        if !wantsIsolation { tuning.vocalQuality = .light }
        let interval = min(0.08, max(0.001, now - lastTick))
        lastTick = now
        guard let motor else { return }
        do {
            if wantsIsolation != isolationActive || analyzedMode != analysisMode || analyzedFocus != tuning.focus(for: mode) {
                try setupSpectrum(rate: sourceRate)
                timer?.schedule(deadline: .now(), repeating: .milliseconds(renderMilliseconds), leeway: .milliseconds(1))
            }
            spectrum?.configure(tuning.eq)
            let count: Int
            if isolationActive && !source.isLive && isolator?.isReady == false {
                count = 0
            } else if let speaker {
                let target = speaker.isPlaying ? speaker.currentTime : (duration ?? 0)
                count = Int(max(0, min(sourceRate * 0.08, target * sourceRate - Double(position))))
            } else {
                count = Int((interval * sourceRate).rounded())
            }
            var advanced = count > 0
            switch source {
            case .file:
                if count > 0, let file, let buffer, file.framePosition < file.length {
                    try file.read(into: buffer, frameCount: AVAudioFrameCount(min(Int(buffer.frameCapacity), count)))
                    advanced = buffer.frameLength > 0
                    guard let channels = buffer.floatChannelData else { throw GlassError("Couldn’t read audio samples.") }
                    let stereo = buffer.format.channelCount > 1
                    for index in 0..<Int(buffer.frameLength) {
                        append(stereo ? fold(channels[0][index], channels[1][index]) : channels[0][index])
                    }
                    position = file.framePosition
                } else { advanced = false }
            case .macAudio:
                advanced = false
                try macMusic?.read(now: now, mute: mode == .trackpad) { samples, rate, changed in
                    if changed || rate != sourceRate || spectrum == nil { try setupSpectrum(rate: rate) }
                    for sample in samples { append(sample) }
                    advanced = !samples.isEmpty
                }
                if macMusic?.suppressOutput == true { delayedFrames.removeAll(keepingCapacity: true) }
            case .player(let link):
                if now >= nextCallScan {
                    nextCallScan = now + 0.35
                    let active = CallAudioPolicy.active(in: AudioHardware.processList().compactMap(AudioClient.init))
                    if active != playerCallActive {
                        playerCallActive = active
                        // Release trackpad-only muting, old PCM and delayed hits
                        // while a call owns audio. Reconnect after the call ends.
                        tap = nil
                        connectedProcesses.removeAll(keepingCapacity: true)
                        lastAudio = nil
                        delayedFrames.removeAll(keepingCapacity: true)
                        resetHapticState()
                        if !active { nextScan = 0 }
                    }
                }
                if !playerCallActive, now >= nextScan, let playerPath {
                    nextScan = now + 1.0
                    let processes = AudioHardware.processIDs(for: link.provider.bundle, appPath: playerPath).sorted()
                    if processes != connectedProcesses {
                        tap = nil
                        lastAudio = nil
                        connectedProcesses = processes
                        if !processes.isEmpty {
                            try connect(CATapDescription(stereoMixdownOfProcesses: processes))
                        }
                    }
                }
                advanced = !playerCallActive && readTap()
            }

            let sourceAdvanced = advanced
            if sourceAdvanced { lastSourceInput = now }
            let sourceEnded = duration.map { Double(position) / sourceRate >= $0 || (file.map { $0.framePosition >= $0.length } ?? false) } ?? false
            if isolationActive {
                if outputSuppressed {
                    // A call or blocked video must silence already-separated output too.
                    if isolator != nil {
                        isolator?.cancel()
                        isolator = nil
                        spectrum = try Spectrum(sampleRate: 24000)
                        spectrum?.configure(tuning.eq)
                    }
                    rawSamples.removeAll(keepingCapacity: true)
                    isolationFinished = false
                    advanced = false
                } else {
                    if !rawSamples.isEmpty {
                        if isolator == nil { isolator = IsolatedVocals() }
                        if isolationFinished { isolator?.reset(); isolationFinished = false }
                        isolator?.push(rawSamples, rate: sourceRate, at: now)
                        rawSamples.removeAll(keepingCapacity: true)
                    }
                    if (sourceEnded || (source.isLive && now - lastSourceInput > 0.15)) && !isolationFinished {
                        isolationFinished = true
                        isolator?.finish()
                    }
                    if let failure = isolator?.failure { throw GlassError(failure) }
                    let budget = interval * 24000 + vocalReadRemainder
                    let frames = Int(budget)
                    vocalReadRemainder = budget - Double(frames)
                    let vocals = isolator?.read(maximum: max(1, frames), at: now) ?? []
                    for sample in vocals { spectrum?.append(sample) }
                    vocalSamplesPlayed += Double(vocals.count)
                    advanced = !vocals.isEmpty
                }
            }
            let captured = advanced && !outputSuppressed ? (spectrum?.frame(tuning: tuning, mode: analysisMode) ?? .empty) : .empty
            let signal = assistTail.resolve(captured, advanced: advanced,
                enabled: (source.isLive || isolationActive) && !outputSuppressed, at: now)
            if signal.hasAudio { lastAudio = now }
            if mode == .assist && now >= nextTiming {
                reportedDelay = tuning.automaticTiming ? OutputTiming.reportedDelay() : 0
                nextTiming = now + 1
            }
            let delay = tuning.automaticTiming ?
                OutputTiming.additionalDelay(reported: reportedDelay, analysisRate: sourceRate / Double(divisor), offsetMS: tuning.delay, focus: tuning.focus(for: mode)) :
                max(0, tuning.delay / 1000)
            let haptics: SignalFrame
            if mode == .assist, delay > 0 {
                delayedFrames.append((now, signal))
                var output = SignalFrame.empty
                var beat = 0.0
                var beatLevel = 0.0
                var frequency = 125.0
                let target = now - delay
                while let first = delayedFrames.first, first.time <= target {
                    output = delayedFrames.removeFirst().signal
                    if output.beatStrength > beat { frequency = output.beatFrequency }
                    beat = max(beat, output.beatStrength)
                    beatLevel = max(beatLevel, output.level)
                }
                if beat > 0 {
                    // A delayed or late render can drain multiple frames. Keep the
                    // attack even when the last frame in the batch is its quiet tail.
                    output = SignalFrame(tones: tuning.focus(for: mode) == .both ? output.tones : [Tone(hertz: frequency, weight: 1)],
                                         level: tuning.focus(for: mode) == .both ? output.level : beatLevel,
                                         bands: output.bands, inputRMS: output.inputRMS,
                                         hasAudio: true, beatStrength: beat, beatFrequency: frequency, bassLevel: output.bassLevel)
                }
                haptics = output
            } else {
                delayedFrames.removeAll(keepingCapacity: true)
                haptics = signal
            }
            if followVolume && now >= nextVolume { volume = OutputVolume.read(); nextVolume = now + 0.4 }
            let outputTime = ProcessInfo.processInfo.systemUptime
            if partyEnd > outputTime && !PartyBurst.allowed(thermal: ProcessInfo.processInfo.thermalState) {
                partyEnd = 0
                keyboard = nil
                publish(PlaybackUpdate(partyOverheated: true))
                return
            }
            let userGain = userHapticsGain.level(enabled: hapticsEnabled, at: outputTime)
            let automatic = automaticHaptics.frame(haptics, mode: analysisMode,
                blocked: outputSuppressed || userGain == 0, focus: tuning.focus(for: mode), impact: tuning.impact, detailBalance: tuning.detailBalance, at: outputTime)
            let rendered: SignalFrame
            if mode == .assist, case .file = source, patternPlayer != nil,
               userGain > 0, !outputSuppressed {
                let offset = (tuning.automaticTiming ? reportedDelay : 0) + tuning.delay / 1000
                rendered = patternPlayer!.frame(at: max(0, speaker?.currentTime ?? 0) - offset)
            } else { rendered = automatic }
            let party = partyEnd > outputTime
            let accent = analysisMode == .assist || (party && PartyBurst.accent(elapsed: PartyBurst.length - (partyEnd - outputTime)))
            let response = party ? (accent ? UltraDynamics.level(rendered.level) : 0) : rendered.level * self.tuning.gain
            // Muted speaker volume must not silently disable trackpad-only output.
            let target = response * (followVolume && mode == .assist ? volume : 1) * userGain
            let motorLevel = motorEnvelope.level(target: target,
                transient: analysisMode == .assist && rendered.beatStrength > 0, at: outputTime)
            if !outputSuppressed && (!party || accent) && target > 0.001 {
                try motor.play(rendered.tones, for: Double(renderMilliseconds), level: motorLevel)
            }
            let useLighting = party ? partyLighting : lighting
            if useLighting && hapticsEnabled && !outputSuppressed {
                if signal.hasAudio && keyboard == nil && !lightUnavailable {
                    keyboard = KeyboardLight()
                    lightUnavailable = keyboard == nil
                }
                keyboard?.update(beatStrength: party ? UltraDynamics.lightBeat(rendered.beatStrength) : rendered.beatStrength, now: outputTime)
                if !signal.hasAudio && now - (lastAudio ?? 0) > 0.35 { keyboard = nil }
            } else { keyboard = nil }
            let idle = macMusic?.idle == true && (isolator?.hasPendingAudio != true)
            if idle != sleeping {
                sleeping = idle
                timer?.schedule(deadline: .now() + .milliseconds(idle ? 350 : renderMilliseconds),
                                repeating: .milliseconds(idle ? 350 : renderMilliseconds), leeway: .milliseconds(idle ? 40 : 1))
            }
            let waiting = source.isLive && (isolationActive ? now - lastSourceInput > 1.5 : (lastAudio.map { now - $0 > 1.5 } ?? true))
            if source.isLive, sourceAdvanced { position += Int64(interval * sourceRate) }
            let elapsed = isolationActive ? vocalStartPosition + vocalSamplesPlayed / 24000 : Double(position) / sourceRate
            if sourceEnded, endedAt == nil { endedAt = now }
            let tail = mode == .assist ? delay + (patternPlayer == nil ? 0.16 : 0) : 0
            let finished = endedAt.map { now - $0 >= tail && (!isolationActive || (isolationFinished && (isolator?.isDrained ?? true))) } ?? false
            if outputSuppressed { visualBeat = 0 }
            else if signal.beatStrength > visualBeat { visualBeat = signal.beatStrength; visualBeatFrequency = signal.beatFrequency }
            updateCounter += 1
            if updateCounter % (mode == .assist ? 4 : 2) == 0 || finished {
                let visual = SignalFrame(tones: signal.tones, level: signal.level, bands: signal.bands,
                    inputRMS: signal.inputRMS, hasAudio: signal.hasAudio || visualBeat > 0,
                    beatStrength: visualBeat, beatFrequency: visualBeatFrequency, bassLevel: signal.bassLevel)
                visualBeat = 0
                publish(PlaybackUpdate(signal: visual, elapsed: min(elapsed, duration ?? elapsed), duration: duration,
                                       device: motor.name, waiting: waiting, video: macMusic?.video, appBundle: macMusic?.activeBundle,
                                       detection: playerCallActive ? "Paused for call audio" : isolationActive && !outputSuppressed ? (isolator?.status ?? "Waiting for vocals") : macMusic?.status,
                                       processingDelay: isolator?.latency ?? 0, finished: finished))
            }
            if finished { stop() }
        } catch {
            stop()
            publish(PlaybackUpdate(error: error.localizedDescription))
        }
    }

}
