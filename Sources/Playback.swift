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

final class Playback {
    private let queue = DispatchQueue(label: "songwave.playback", qos: .userInteractive)
    private var session: Session?
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
               startAt: Double, partyDeadline: Double = 0, update: @escaping (PlaybackUpdate) -> Void) {
        queue.async {
            if source == .ultraBeat && partyDeadline <= ProcessInfo.processInfo.systemUptime { return }
            self.session?.stop()
            self.session = nil
            do {
                let run = try Session(source: source, playerPath: playerPath, tuning: tuning, mode: mode,
                                      startAt: startAt, update: update)
                run.patternPlayer = self.pattern.map(HapticPattern.Player.init)
                run.followVolume = self.followVolume
                run.lighting = self.keyboard
                run.partyLighting = self.partyKeyboard
                run.partyEnd = partyDeadline
                if source == .ultraBeat && partyDeadline <= ProcessInfo.processInfo.systemUptime { return }
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
    var renderMilliseconds: Int { mode == .assist ? 8 : 16 }
    private var sleeping = false
    private var motorEnvelope = MotorEnvelope()
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
    private var wantsIsolation: Bool { mode == .trackpad && tuning.vocalQuality == .isolated }
    let update: (PlaybackUpdate) -> Void

    init(source: PlaybackSource, playerPath: String?, tuning: Tuning, mode: OutputMode,
         startAt: Double, update: @escaping (PlaybackUpdate) -> Void) throws {
        self.source = source
        self.playerPath = playerPath
        self.tuning = tuning
        self.mode = mode
        self.update = update
        switch source {
        case .demo, .ultraBeat:
            let length = source == .ultraBeat ? PartyBurst.length : 12
            duration = length
            try setupSpectrum(rate: 24_000)
            if mode == .assist { speaker = try AVAudioPlayer(data: Self.demoWave(length: length)) }
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
    }

    func setupSpectrum(rate: Double) throws {
        assistTail = AssistTail()
        automaticHaptics = AutomaticHaptics()
        motorEnvelope = MotorEnvelope()
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
        let interval = min(0.08, max(0.001, now - lastTick))
        lastTick = now
        guard let motor else { return }
        do {
            if wantsIsolation != isolationActive { try setupSpectrum(rate: sourceRate) }
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
            case .demo, .ultraBeat:
                guard let duration else { throw GlassError("The built-in beat has no duration.") }
                let end = min(position + Int64(count), Int64(duration * sourceRate))
                advanced = end > position
                for index in position..<end { append(Self.demoSample(at: Double(index) / sourceRate, length: duration)) }
                position = end
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
                if now >= nextScan, let playerPath {
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
                advanced = readTap()
            }

            let sourceAdvanced = advanced
            if sourceAdvanced { lastSourceInput = now }
            let sourceEnded = duration.map { Double(position) / sourceRate >= $0 || (file.map { $0.framePosition >= $0.length } ?? false) } ?? false
            if isolationActive {
                if macMusic?.suppressOutput == true {
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
            let captured = advanced && macMusic?.suppressOutput != true ? (spectrum?.frame(tuning: tuning, mode: mode) ?? .empty) : .empty
            let signal = assistTail.resolve(captured, advanced: advanced,
                enabled: (source.isLive || isolationActive) && macMusic?.suppressOutput != true, at: now)
            if signal.hasAudio { lastAudio = now }
            if mode == .assist && now >= nextTiming {
                reportedDelay = tuning.automaticTiming ? OutputTiming.reportedDelay() : 0
                nextTiming = now + 1
            }
            let delay = tuning.automaticTiming ?
                OutputTiming.additionalDelay(reported: reportedDelay, analysisRate: sourceRate / Double(divisor), offsetMS: tuning.delay) :
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
                    output = SignalFrame(tones: [Tone(hertz: frequency, weight: 1)], level: beatLevel,
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
            if source == .ultraBeat && partyEnd > 0 && outputTime >= partyEnd {
                stop()
                publish(PlaybackUpdate(elapsed: duration ?? PartyBurst.length, duration: duration,
                                       device: motor.name, finished: true))
                return
            }
            if partyEnd > outputTime && !PartyBurst.allowed(thermal: ProcessInfo.processInfo.thermalState) {
                partyEnd = 0
                keyboard = nil
                if source == .ultraBeat { stop() }
                publish(PlaybackUpdate(partyOverheated: true))
                return
            }
            let automatic = automaticHaptics.frame(haptics, mode: mode,
                blocked: macMusic?.suppressOutput == true || !hapticsEnabled, impact: tuning.impact, at: outputTime)
            let rendered: SignalFrame
            if mode == .assist, case .file = source, patternPlayer != nil,
               hapticsEnabled, macMusic?.suppressOutput != true {
                let offset = (tuning.automaticTiming ? reportedDelay : 0) + tuning.delay / 1000
                rendered = patternPlayer!.frame(at: max(0, speaker?.currentTime ?? 0) - offset)
            } else { rendered = automatic }
            let party = partyEnd > outputTime
            let accent = mode == .assist || (party && PartyBurst.accent(elapsed: PartyBurst.length - (partyEnd - outputTime)))
            let strength = party ? (accent ? 0.83 : 0) : tuning.gain
            let target = rendered.level * strength * (followVolume ? volume : 1)
            let motorLevel = motorEnvelope.level(target: target,
                transient: mode == .assist && rendered.beatStrength > 0, at: outputTime)
            if hapticsEnabled && (!party || accent) && target > 0.001 {
                try motor.play(rendered.tones, for: Double(renderMilliseconds), level: motorLevel)
            }
            let useLighting = party ? partyLighting : lighting
            if useLighting && hapticsEnabled {
                if signal.hasAudio && keyboard == nil && !lightUnavailable {
                    keyboard = KeyboardLight()
                    lightUnavailable = keyboard == nil
                }
                keyboard?.update(beatStrength: rendered.beatStrength, now: outputTime)
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
            updateCounter += 1
            if updateCounter % (mode == .assist ? 4 : 2) == 0 || finished {
                publish(PlaybackUpdate(signal: signal, elapsed: min(elapsed, duration ?? elapsed), duration: duration,
                                       device: motor.name, waiting: waiting, video: macMusic?.video, appBundle: macMusic?.activeBundle,
                                       detection: isolationActive && macMusic?.suppressOutput != true ? (isolator?.status ?? "Waiting for vocals") : macMusic?.status,
                                       processingDelay: isolator?.latency ?? 0, finished: finished))
            }
            if finished { stop() }
        } catch {
            stop()
            publish(PlaybackUpdate(error: error.localizedDescription))
        }
    }

    // An in-memory PCM WAV keeps the speaker demo and the actuator source identical.
    private static func demoWave(length: Double) -> Data {
        let rate = 24_000
        let count = Int(length * Double(rate))
        var data = Data()
        data.reserveCapacity(44 + count * 2)
        func append<T: FixedWidthInteger>(_ value: T) {
            var little = value.littleEndian
            withUnsafeBytes(of: &little) { data.append(contentsOf: $0) }
        }
        data.append(contentsOf: "RIFF".utf8)
        append(UInt32(36 + count * 2))
        data.append(contentsOf: "WAVEfmt ".utf8)
        append(UInt32(16))
        append(UInt16(1))
        append(UInt16(1))
        append(UInt32(rate))
        append(UInt32(rate * 2))
        append(UInt16(2))
        append(UInt16(16))
        data.append(contentsOf: "data".utf8)
        append(UInt32(count * 2))
        for index in 0..<count {
            append(Int16(demoSample(at: Double(index) / Double(rate), length: length) * Float(Int16.max)))
        }
        return data
    }

    private static func demoSample(at time: Double, length: Double) -> Float {
        let beat = 60.0 / 120.0
        let step = Int(time / (beat / 2))
        let local = time.truncatingRemainder(dividingBy: beat / 2)
        let kickTime = time.truncatingRemainder(dividingBy: beat)
        let bar = Int(time / (beat * 4))
        let melody: [Double] = [329.63, 493.88, 392.0, 587.33, 440.0, 659.25, 523.25, 392.0,
                                293.66, 440.0, 349.23, 523.25, 392.0, 587.33, 493.88, 329.63]
        let roots: [Double] = [110.0, 130.81, 98.0, 146.83, 110.0, 130.81]
        let pitch = melody[step % melody.count]
        let root = roots[bar % roots.count]
        let attack = min(1, local / 0.012)
        let envelope = attack * exp(-local * 7.5)
        let note = (sin(2 * .pi * pitch * local) + 0.38 * sin(4 * .pi * pitch * local)) * envelope * 0.19
        let bass = sin(2 * .pi * root * time) * (0.07 + 0.10 * envelope)
        let kick = sin(2 * .pi * (123 * kickTime + 3.3 * (1 - exp(-24 * kickTime)))) * exp(-kickTime * 22) * 0.25
        let top = sin(2 * .pi * 1947 * local) * sin(2 * .pi * 367 * local) * exp(-local * 116) * 0.067
        return Float((note + bass + kick + top) * min(1, max(0, (length - time) * 3.5)))
    }
}
