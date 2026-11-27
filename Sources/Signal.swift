import Accelerate
import Foundation

struct Tone {
    let hertz: Double
    let weight: Double
}

enum Profile: String, CaseIterable, Identifiable, Codable {
    case balanced = "Balanced"
    case detail = "Detail"
    case pulse = "Pulse"

    var id: Self { self }
    var description: String {
        switch self {
        case .balanced: return "Keeps a natural balance of vocal harmonics."
        case .detail: return "Brings upper vocal harmonics forward."
        case .pulse: return "Adds weight to lower vocal harmonics."
        }
    }
    var icon: String {
        switch self {
        case .balanced: return "waveform"
        case .detail: return "waveform.path"
        case .pulse: return "bolt"
        }
    }
}

struct SignalFrame {
    let tones: [Tone]
    let level: Double
    let bands: [Double]
    let inputRMS: Double
    let hasAudio: Bool
    var beatStrength: Double = 0
    var beatFrequency: Double = 125
    var bassLevel: Double = 0

    static let empty = SignalFrame(tones: [], level: 0, bands: Array(repeating: 0, count: 44), inputRMS: 0, hasAudio: false)
}

// Audio callbacks and the motor timer have different cadences. Bridge only
// short capture gaps, without repeating an onset or holding through suppression.
struct AssistTail {
    private var previous = SignalFrame.empty
    private var capturedAt = -Double.infinity

    mutating func resolve(_ signal: SignalFrame, advanced: Bool, enabled: Bool, at now: Double) -> SignalFrame {
        guard enabled else { self = AssistTail(); return signal }
        if advanced {
            previous = signal
            capturedAt = now
            return signal
        }
        let age = now - capturedAt
        guard age >= 0, age <= 0.030, previous.hasAudio else {
            self = AssistTail()
            return .empty
        }
        let level = previous.level * exp(-age / 0.045)
        return SignalFrame(tones: level > 0.08 ? previous.tones : [], level: level,
                           bands: previous.bands, inputRMS: previous.inputRMS,
                           hasAudio: true, beatStrength: 0, beatFrequency: previous.beatFrequency,
                           bassLevel: previous.bassLevel * exp(-age / 0.035))
    }
}

final class Spectrum {
    private let size = 2048
    private let window: [Float]
    private let onsetWindow: [Float]
    private let fft: FFTSetup
    private var samples: [Float]
    private var real: [Float]
    private var imaginary: [Float]
    private var magnitudes: [Float]
    private var previousMagnitudes: [Float]
    private var cursor = 0
    private var filled = 0
    private var power: Double = 0
    private var previousLevel: Double = 0
    private var previousRMS = 0.0
    private var reference: Double = 0.075
    private let sampleRate: Double
    private var previousTones: [Tone] = []
    private var filters: [Biquad] = []
    private var equalizer: EQ?
    private var beatTail = 0.0
    private var lastBeatFrame = 0.0
    private var wetMix = 1.0
    private var wetTarget = 1.0
    private let mixStep: Double
    private var dcEstimate = 0.0
    private var totalSamples = 0.0
    private var rhythm = RhythmDetector()
    private var lastAnalysisSize = 0
    private var tactilePitch = 125.0
    private var vocalFocus = VocalFocus()
    private var bassEnvelope: BassEnvelope

    init(sampleRate: Double) throws {
        guard sampleRate.isFinite, sampleRate >= 1 else {
            throw GlassError("The audio source has an invalid sample rate.")
        }
        self.sampleRate = sampleRate
        bassEnvelope = BassEnvelope(rate: sampleRate)
        mixStep = 1 / (sampleRate * 0.14)
        guard let setup = vDSP_create_fftsetup(11, FFTRadix(kFFTRadix2)) else {
            throw GlassError("The spectrum analyzer could not start.")
        }
        fft = setup
        let size = 2048
        window = (0..<size).map { 0.5 - 0.5 * cos(2 * .pi * Float($0) / Float(size - 1)) }
        onsetWindow = (0..<1024).map { 0.5 - 0.5 * cos(2 * .pi * Float($0) / 1023) }
        samples = Array(repeating: 0, count: size)
        real = samples
        imaginary = samples
        magnitudes = Array(repeating: 0, count: size / 2)
        previousMagnitudes = magnitudes
    }

    deinit { vDSP_destroy_fftsetup(fft) }

    func configure(_ eq: EQ) {
        guard eq != equalizer else { return }
        wetTarget = eq.enabled ? 1 : 0
        if equalizer == nil { wetMix = wetTarget }
        if Band.allCases.contains(where: { equalizer?[$0] != eq[$0] }) {
            filters = Band.allCases.compactMap { band in
                let settings = eq[band]
                return abs(settings.gain) > 0.001 ? Biquad(band: settings, rate: sampleRate) : nil
            }
        }
        equalizer = eq
    }

    func append(_ sample: Float) {
        totalSamples += 1
        var filtered = sample.isFinite ? Double(sample) : 0
        dcEstimate += (filtered - dcEstimate) * 0.002
        filtered -= dcEstimate
        let dry = filtered
        for index in filters.indices { filtered = filters[index].process(filtered) }
        wetMix += min(mixStep, max(-mixStep, wetTarget - wetMix))
        let clean = Float(max(-4, min(4, dry + (filtered - dry) * wetMix)))
        bassEnvelope.append(clean)
        samples[cursor] = clean
        cursor = (cursor + 1) % size
        filled = min(size, filled + 1)
        power += (Double(clean * clean) - power) * 0.003
    }

    func frame(tuning: Tuning, mode: OutputMode) -> SignalFrame {
        let profile = tuning.profile
        let analysisSize = mode == .assist && sampleRate <= 32000 ? 1024 : size
        if analysisSize != lastAnalysisSize {
            lastAnalysisSize = analysisSize
            previousMagnitudes = Array(repeating: 0, count: size / 2)
            rhythm = RhythmDetector()
            vocalFocus = VocalFocus()
        }
        let rms = sqrt(max(0, power))
        let releasing = rms < previousRMS * 0.85
        previousRMS = rms
        // Low-level percussion can remain audible after vocals drop out.
        // Keep the vocal floor unchanged; transient/flux checks still qualify beats.
        let silenceFloor = mode == .assist ? 0.00005 : 0.00025
        guard filled >= analysisSize, rms > silenceFloor else {
            previousTones.removeAll(keepingCapacity: true)
            previousLevel = 0
            vocalFocus = VocalFocus()
            bassEnvelope.resetEvidence()
            beatTail = 0
            previousMagnitudes = Array(repeating: 0, count: size / 2)
            if filled >= analysisSize {
                _ = rhythm.detect(bass: 0, treble: 0, percussive: false, at: totalSamples / sampleRate)
            }
            return .empty
        }

        reference = max(0.04, max(rms, reference * 0.992))
        let normalized = min(1, rms / reference)
        let transient = max(0, normalized - previousLevel)
        previousLevel = normalized
        let binWidth = sampleRate / Double(size)
        let firstBin = max(2, Int(45 / binWidth))
        let lastBin = min(size / 2 - 2, Int(4000 / binWidth))
        guard firstBin < lastBin else { return .empty }

        for index in 0..<size {
            if index < analysisSize {
                let source = (cursor - analysisSize + index + size) % size
                let taper = analysisSize == 1024 ? onsetWindow[index] : window[index]
                real[index] = samples[source] * taper
            } else { real[index] = 0 }
            imaginary[index] = 0
        }
        real.withUnsafeMutableBufferPointer { re in
            imaginary.withUnsafeMutableBufferPointer { im in
                var split = DSPSplitComplex(realp: re.baseAddress!, imagp: im.baseAddress!)
                vDSP_fft_zip(fft, &split, 1, 11, FFTDirection(FFT_FORWARD))
            }
        }
        let rhythmLastBin = min(size / 2 - 2, Int(8000 / binWidth))
        for index in 1...(rhythmLastBin + 1) {
            magnitudes[index] = hypot(real[index], imaginary[index])
        }

        let bands = (0..<44).map { index -> Double in
            let lower = max(firstBin, Int(65 * pow(4000 / 65.0, Double(index) / 44) / binWidth))
            guard lower <= lastBin else { return 0 }
            let upper = max(lower, min(lastBin, Int(65 * pow(4000 / 65.0, Double(index + 1) / 44) / binWidth)))
            let peak = magnitudes[lower...upper].max() ?? 0
            return min(1, log1p(Double(peak)) / 4.8)
        }
        // Lighting needs note attacks, independently of the sustained haptic level.
        let bassEnd = min(lastBin, max(1, Int(160 / binWidth)))
        let bassStart = min(bassEnd, max(1, Int(38 / binWidth)))
        let bassEnergy = sqrt(magnitudes[bassStart...bassEnd].reduce(0.0) { $0 + Double($1) * Double($1) }) / Double(analysisSize)
        let trebleEnd = min(rhythmLastBin + 1, Int(8000 / binWidth) + 1)
        let trebleStart = min(trebleEnd, Int(2000 / binWidth))
        let highs = magnitudes[trebleStart..<trebleEnd]
        let trebleEnergy = sqrt(highs.reduce(0.0) { $0 + Double($1) * Double($1) }) / Double(analysisSize)
        var fluxSum = 0.0, fluxPeak = 0.0, fluxPower = 0.0
        for bin in trebleStart..<trebleEnd {
            let rise = Double(max(0, magnitudes[bin] - previousMagnitudes[bin]))
            fluxSum += rise
            fluxPeak = max(fluxPeak, rise)
            fluxPower += rise * rise
        }
        let noiseSpread = fluxSum / max(0.001, fluxPeak * Double(highs.count))
        let harmonicSearchEnd = min(lastBin, max(bassEnd, Int(260 / binWidth)))
        let bassBin = (bassStart...harmonicSearchEnd).max {
            max(0, magnitudes[$0] - previousMagnitudes[$0]) < max(0, magnitudes[$1] - previousMagnitudes[$1])
        } ?? bassStart
        let bassRise = Double(max(0, magnitudes[bassBin] - previousMagnitudes[bassBin]))
        func risingHarmonic(_ multiple: Int) -> Double {
            let center = bassBin * multiple
            guard center < lastBin else { return 0 }
            let lower = max(1, center - 1), upper = min(lastBin, center + 1)
            let peak = (lower...upper).map { Double(max(0, magnitudes[$0] - previousMagnitudes[$0])) }.max() ?? 0
            var surrounding = 0.0, count = 0
            let distance = analysisSize == 1024 ? 5 : 4
            let shoulder = analysisSize == 1024 ? 4 : 2
            for bin in max(1, center - distance)...min(lastBin, center + distance) where abs(bin - center) >= shoulder {
                surrounding += Double(max(0, magnitudes[bin] - previousMagnitudes[bin]))
                count += 1
            }
            let contrast = analysisSize == 1024 ? 1.7 : 3.0
            return peak > surrounding / Double(max(1, count)) * contrast ? peak : 0
        }
        let rawPeak = (bassStart...harmonicSearchEnd).max { magnitudes[$0] < magnitudes[$1] } ?? bassStart
        let left = log(max(1e-7, Double(magnitudes[max(1, rawPeak - 1)])))
        let center = log(max(1e-7, Double(magnitudes[rawPeak])))
        let right = log(max(1e-7, Double(magnitudes[min(lastBin, rawPeak + 1)])))
        let curvature = left - 2 * center + right
        let adjustment = abs(curvature) > 1e-7 ? 0.5 * (left - right) / curvature : 0
        let fundamental = Double(rawPeak) + max(-0.5, min(0.5, adjustment))
        func harmonicLevel(_ multiple: Int) -> Double {
            let bin = Int((fundamental * Double(multiple)).rounded())
            guard bin < rhythmLastBin else { return 0 }
            return Double(magnitudes[max(1, bin - 1)...min(rhythmLastBin, bin + 1)].max() ?? 0)
        }
        var harmonicFlux = 0.0, totalFlux = 0.0
        for bin in bassStart...rhythmLastBin {
            let rise = Double(max(0, magnitudes[bin] - previousMagnitudes[bin]))
            let harmonic = max(1, (Double(bin) / fundamental).rounded())
            totalFlux += rise
            if abs(Double(bin) - harmonic * fundamental) <= 1.1 { harmonicFlux += rise }
        }
        let harmonicOnset = harmonicLevel(2) > Double(magnitudes[rawPeak]) * 0.12 &&
            harmonicLevel(3) > Double(magnitudes[rawPeak]) * 0.08 &&
            harmonicFlux > totalFlux * 0.50
        let voicedAttack = harmonicOnset || (bassRise > Double(analysisSize) * 0.0005 && risingHarmonic(2) > bassRise * 0.20 &&
            risingHarmonic(3) > bassRise * 0.12)
        let midEnd = min(lastBin + 1, Int(2000 / binWidth) + 1)
        let midStart = min(midEnd, Int(250 / binWidth))
        let midEnergy = sqrt(magnitudes[midStart..<midEnd].reduce(0.0) { $0 + Double($1) * Double($1) }) / Double(analysisSize)
        var midFlux = 0.0, midPeak = 0.0, midFluxPower = 0.0
        for bin in midStart..<midEnd {
            let rise = Double(max(0, magnitudes[bin] - previousMagnitudes[bin]))
            midFlux += rise
            midPeak = max(midPeak, rise)
            midFluxPower += rise * rise
        }
        let midSpread = midFlux / max(0.001, midPeak * Double(midEnd - midStart))
        let beat = rhythm.detect(bass: bassEnergy, treble: trebleEnergy, percussive: noiseSpread > 0.12,
                                 voicedAttack: voicedAttack, releasing: releasing, mid: midEnergy,
                                 midPercussive: midSpread > 0.16,
                                 midFlux: sqrt(midFluxPower) / Double(analysisSize),
                                 trebleFlux: sqrt(fluxPower) / Double(analysisSize), at: totalSamples / sampleRate)
        if beat > 0 { tactilePitch = rhythm.frequency }
        previousMagnitudes = magnitudes
        if mode == .assist {
            previousTones.removeAll(keepingCapacity: true)
            let time = totalSamples / sampleRate
            let elapsed = max(0, time - lastBeatFrame)
            lastBeatFrame = time
            beatTail = max(beatTail * exp(-elapsed / 0.045), beat)
            // Each tactile pitch completes whole cycles in an 8 ms packet.
            let lowEnd = min(lastBin - 1, max(bassStart, Int(125 / binWidth)))
            let lowPeak = (bassStart...lowEnd).max { magnitudes[$0] < magnitudes[$1] } ?? bassStart
            let a = log(max(1e-7, Double(magnitudes[max(1, lowPeak - 1)])))
            let b = log(max(1e-7, Double(magnitudes[lowPeak])))
            let c = log(max(1e-7, Double(magnitudes[lowPeak + 1])))
            let curve = a - 2 * b + c
            let delta = abs(curve) > 1e-7 ? max(-0.5, min(0.5, 0.5 * (a - c) / curve)) : 0
            let lowPitch = (Double(lowPeak) + delta) * binWidth
            let sustain = bassEnvelope.level(pitch: lowPitch,
                magnitude: Double(magnitudes[lowPeak]) / Double(analysisSize), at: time) * tuning.bassSustain
            let pitch = tactilePitch
            return SignalFrame(tones: beatTail > 0.08 ? [Tone(hertz: pitch, weight: 1)] : [],
                               level: max(sustain, beatTail * (0.80 + tuning.impact * 0.20)), bands: bands,
                               inputRMS: rms, hasAudio: true, beatStrength: beat, beatFrequency: tactilePitch, bassLevel: sustain)
        }

        if tuning.vocalQuality == .light {
            let vocal = vocalFocus.frame(magnitudes: magnitudes, binWidth: binWidth,
                                         analysisSize: analysisSize, at: totalSamples / sampleRate, tuning: tuning)
            let vocalBands = (0..<44).map { index -> Double in
                let lower = 65 * pow(4000 / 65.0, Double(index) / 44)
                let upper = 65 * pow(4000 / 65.0, Double(index + 1) / 44)
                let peak = vocal.tones.filter { $0.hertz >= lower && $0.hertz < upper }.map(\.weight).max() ?? 0
                return min(1, log1p(peak * Double(analysisSize)) / 4.8)
            }
            return SignalFrame(tones: vocal.tones, level: vocal.level, bands: vocalBands,
                               inputRMS: rms, hasAudio: true, beatStrength: beat, beatFrequency: tactilePitch)
        }

        var bins: [(frequency: Double, weight: Double)] = []
        for index in firstBin...lastBin {
            let center = Double(magnitudes[index])
            guard center > Double(magnitudes[index - 1]), center >= Double(magnitudes[index + 1]),
                  center > 0.12 else { continue }
            let left = log(max(0.00001, Double(magnitudes[index - 1])))
            let right = log(max(0.00001, Double(magnitudes[index + 1])))
            let denominator = left - 2 * log(center) + right
            let adjustment = abs(denominator) > 0.00001 ? 0.5 * (left - right) / denominator : 0
            let frequency = (Double(index) + adjustment) * binWidth
            let emphasis: Double
            switch profile {
            case .balanced: emphasis = frequency < 150 ? 0.9 : 1
            case .detail: emphasis = min(1.45, max(0.45, pow(frequency / 500, 0.32)))
            case .pulse: emphasis = frequency < 360 ? 1.45 : 0.45
            }
            let color = pow(frequency / 440, tuning.tone * 0.7)
            bins.append((frequency, center * emphasis * color))
        }
        bins.sort { $0.weight > $1.weight }
        let floor = (bins.first?.weight ?? 0) * 0.12
        var tones: [Tone] = []
        for item in bins where item.weight >= floor {
            var frequency = item.frequency
            while frequency < 100 { frequency *= 2 }
            guard frequency <= 4000,
                  !tones.contains(where: { abs($0.hertz - frequency) < 24 }) else { continue }
            tones.append(Tone(hertz: frequency, weight: pow(item.weight, 0.8)))
            if tones.count >= tuning.partials { break }
        }
        if tuning.smoothing > 0 {
            let blend = min(1, 1 - exp(-16 / tuning.smoothing) + transient * 0.8)
            tones = tones.map { tone in
                guard let previous = previousTones.min(by: {
                    abs($0.hertz - tone.hertz) < abs($1.hertz - tone.hertz)
                }), abs(previous.hertz - tone.hertz) < max(12, tone.hertz * 0.027) else { return tone }
                return Tone(hertz: previous.hertz + (tone.hertz - previous.hertz) * blend,
                            weight: previous.weight + (tone.weight - previous.weight) * blend)
            }
        }
        previousTones = tones


        return SignalFrame(tones: tones, level: min(1, pow(normalized, 0.75) * (0.95 - tuning.impact * 0.24) + transient * tuning.impact * 0.8),
                           bands: bands, inputRMS: rms, hasAudio: true, beatStrength: beat, beatFrequency: tactilePitch)
    }
}

// Detect a rise in low-frequency energy or a broadband percussion attack.
// Analysis time follows the audio samples, so changing render cadence cannot invent beats.
struct RhythmDetector {
    private var previousBass = 0.0
    private var previousTreble = 0.0
    private var previousMid = 0.0
    private var bassFloor = 0.0
    private var midFluxFloor = 0.0
    private var trebleFluxFloor = 0.0
    private var lastTime: Double?
    private var lastKick = -Double.infinity
    private var lastDetail = -Double.infinity
    private(set) var frequency = 125.0
    private var pendingDetail: (time: Double, strength: Double, frequency: Double)?

    mutating func detect(bass: Double, treble: Double, percussive: Bool, voicedAttack: Bool = false, releasing: Bool = false,
                         mid: Double = 0, midPercussive: Bool = false,
                         midFlux: Double = 0, trebleFlux: Double = 0, at time: Double) -> Double {
        guard let previousTime = lastTime else {
            lastTime = time
            previousBass = bass
            previousTreble = treble
            previousMid = mid
            bassFloor = bass
            return 0
        }
        let interval = max(0, time - previousTime)
        guard interval > 0 else { return 0 }
        lastTime = time
        let bassRise = max(0, bass - previousBass)
        let midRise = max(0, mid - previousMid)
        let trebleRise = max(0, treble - previousTreble)
        let kick = !voicedAttack && !releasing && time - lastKick >= 0.14 &&
            bassRise > midRise * 1.25 && bass > 0.0015 &&
            bassRise > max(0.0007, bassFloor * 0.15) && bass > bassFloor * 1.35
        let highHit = !voicedAttack && percussive && trebleRise > max(0.00001, treble * 0.003) && trebleFlux > max(0.00002, trebleFluxFloor * 2.0)
        let midHit = !voicedAttack && midPercussive && midRise > max(0.00001, mid * 0.003) && midFlux > max(0.00002, midFluxFloor * 2.0)
        let bassStrength = bassRise / max(0.004, bassFloor)
        let detailStrength = max(trebleFlux / max(0.001, trebleFluxFloor * 4), midFlux / max(0.001, midFluxFloor * 4))
        let follow = 1 - exp(-interval / 0.18)
        bassFloor += (bass - bassFloor) * follow
        midFluxFloor += (midFlux - midFluxFloor) * follow
        trebleFluxFloor += (trebleFlux - trebleFluxFloor) * follow
        previousBass = bass
        previousTreble = treble
        previousMid = mid
        if kick {
            lastKick = time
            lastDetail = time
            pendingDetail = nil
            frequency = 125
            return min(1, 0.55 + 0.45 * bassStrength)
        }
        if voicedAttack { pendingDetail = nil }
        if let pending = pendingDetail {
            guard time - pending.time >= 0.012 else { return 0 }
            pendingDetail = nil
            guard time - pending.time <= 0.06 else { return 0 }
            lastDetail = time
            frequency = pending.frequency
            return pending.strength
        }
        guard time - lastDetail >= 0.065, highHit || midHit else { return 0 }
        // A very short voiced syllable initially looks like broadband percussion.
        // Confirm it once its harmonic structure becomes visible in the next slice.
        pendingDetail = (time, min(0.48, 0.28 + 0.20 * detailStrength),
                         highHit && (!midHit || trebleFlux >= midFlux) ? 375 : 250)
        return 0
    }
}

enum OutputMode: String, CaseIterable, Identifiable {
    case trackpad = "Trackpad only"
    case assist = "Speakers + haptics"

    var id: Self { self }
    var description: String {
        switch self {
        case .trackpad: return "Feel your selected focus through the trackpad, with captured audio muted."
        case .assist: return "Hear the full song and feel your selected focus through the trackpad."
        }
    }

    var defaults: Tuning {
        switch self {
        case .trackpad: return Tuning(profile: .balanced, gain: 0.60, tone: 0, impact: 0.35, partials: 6, smoothing: 28)
        case .assist: return Tuning(profile: .balanced, gain: 0.40, tone: -0.12, impact: 0.65, partials: 4, smoothing: 18)
        }
    }
}

// Haptic content and audible output are separate choices. Optional storage
// below preserves the historical defaults in existing saved presets.
enum HapticFocus: String, CaseIterable, Identifiable, Codable {
    case beat = "Beat"
    case voice = "Voice"
    var id: Self { self }
    var analysisMode: OutputMode { self == .beat ? .assist : .trackpad }
    var description: String {
        self == .beat ? "Feel bass and percussion. Dense mixes can still let vocals through."
                      : "Follow vocal pitch and texture. Instrumental passages can be quiet."
    }
}

enum VocalQuality: String, CaseIterable, Identifiable, Codable {
    case light = "Light"
    case isolated = "Isolated"

    var id: Self { self }
    var description: String {
        switch self {
        case .light: return "Fast vocal focus. Low memory use; some instruments can leak through."
        case .isolated: return "Cleaner vocals using an on-device model. About 0.8 s of buffering; higher memory use."
        }
    }
}

struct Tuning: Codable {
    var profile: Profile
    var gain: Double
    var tone: Double
    var impact: Double
    var partials: Int = 5
    var smoothing: Double = 25
    var delay: Double = 0
    var automaticTiming = true
    var hapticFocus: HapticFocus? = nil
    var vocalQuality = VocalQuality.light
    var detailBalance = 0.35
    var bassSustain = 0.6
    var eq = EQ()
}


// Older presets precede EQ, delay and pitch smoothing. Preserve their existing
// choices and use the original defaults for any controls they did not store.
extension Tuning {
    init(from decoder: Decoder) throws {
        let values = try decoder.container(keyedBy: CodingKeys.self)
        profile = try values.decode(Profile.self, forKey: .profile)
        gain = min(1, max(0, try values.decode(Double.self, forKey: .gain)))
        tone = min(1, max(-1, try values.decode(Double.self, forKey: .tone)))
        impact = min(1, max(0, try values.decode(Double.self, forKey: .impact)))
        partials = min(8, max(2, try values.decodeIfPresent(Int.self, forKey: .partials) ?? partials))
        smoothing = min(90, max(0, try values.decodeIfPresent(Double.self, forKey: .smoothing) ?? smoothing))
        delay = min(300, max(-100, try values.decodeIfPresent(Double.self, forKey: .delay) ?? delay))
        // Preserve a legacy nonzero delay as a manual setting, rather than adding
        // automatic compensation on top of an existing calibration.
        automaticTiming = try values.decodeIfPresent(Bool.self, forKey: .automaticTiming) ?? (delay == 0)
        detailBalance = min(1, max(0, try values.decodeIfPresent(Double.self, forKey: .detailBalance) ?? 0.35))
        bassSustain = min(1, max(0, try values.decodeIfPresent(Double.self, forKey: .bassSustain) ?? 0.6))
        hapticFocus = try values.decodeIfPresent(HapticFocus.self, forKey: .hapticFocus)
        vocalQuality = try values.decodeIfPresent(VocalQuality.self, forKey: .vocalQuality) ?? .light
        eq = try values.decodeIfPresent(EQ.self, forKey: .eq) ?? eq
    }
}

// Session-local Ultra processing. Never written to Studio or saved preferences.
enum UltraDynamics {
    static func tuning(_ saved: Tuning, active: Bool, output: OutputMode = .assist) -> Tuning {
        guard active else { return saved }
        var value = saved
        value.profile = .balanced
        value.gain = 1
        value.tone = 0
        value.impact = 1
        value.smoothing = 12
        value.bassSustain = 0.85
        value.detailBalance = 0.85
        value.eq = EQ()
        let voice = saved.focus(for: output) == .voice
        value.eq.bass.gain = voice ? 0 : 4
        value.eq.mid.gain = voice ? 3 : 1
        value.eq.treble.gain = voice ? 1 : 2
        return value
    }
    static func level(_ input: Double) -> Double {
        guard input.isFinite, input > 0 else { return 0 }
        // Lift quiet detected accents without raising the existing Ultra ceiling.
        let value = min(1, input)
        return min(0.83, value * 2.4 + sqrt(value) * 0.18)
    }
    static func lightBeat(_ input: Double) -> Double {
        guard input.isFinite, input > 0 else { return 0 }
        return min(1, 0.8 + input * 0.2)
    }
}

extension Tuning {
    func focus(for output: OutputMode) -> HapticFocus {
        hapticFocus ?? (output == .assist ? .beat : .voice)
    }
    func usesVocalIsolation(for output: OutputMode) -> Bool {
        output == .trackpad && focus(for: output) == .voice && vocalQuality == .isolated
    }
}
