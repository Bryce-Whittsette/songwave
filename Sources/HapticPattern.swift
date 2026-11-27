import Foundation
import CoreFoundation

// A bounded haptic-only AHAP adapter. Audio remains owned by the existing player;
// waveform paths in imported documents are never opened or executed.
struct HapticPattern {
    struct Event { let time: Double; let duration: Double; let intensity: Double; let sharpness: Double; let transient: Bool }
    struct Curve { let time: Double; let sharpness: Bool; let points: [(Double, Double)]
        func value(at position: Double) -> Double {
            let t = position - time
            guard let first = points.first else { return sharpness ? 0 : 1 }
            if t <= first.0 { return first.1 }
            for pair in zip(points, points.dropFirst()) where t <= pair.1.0 {
                let mix = (t - pair.0.0) / (pair.1.0 - pair.0.0)
                return pair.0.1 + (pair.1.1 - pair.0.1) * mix
            }
            return points.last!.1
        }
    }
    let events: [Event]
    let curves: [Curve]
    let skippedAudio: Int

    init(data: Data) throws {
        func bad() -> GlassError { GlassError("Use an AHAP 1.0 file with haptic events and intensity or sharpness curves.") }
        func number(_ object: [String: Any], _ key: String) throws -> Double {
            // JSON booleans bridge to NSNumber too; true must not become a
            // version, timestamp, duration or full-strength intensity of 1.
            guard let value = object[key] as? NSNumber,
                  CFGetTypeID(value) != CFBooleanGetTypeID(), value.doubleValue.isFinite else { throw bad() }
            return value.doubleValue
        }
        guard data.count <= 1_048_576,
              let root = try JSONSerialization.jsonObject(with: data) as? [String: Any],
              try number(root, "Version") == 1,
              let pattern = root["Pattern"] as? [[String: Any]], pattern.count <= 4096 else { throw bad() }
        var events: [Event] = [], curves: [Curve] = [], audio = 0
        for item in pattern {
            if let event = item["Event"] as? [String: Any] {
                let type = event["EventType"] as? String ?? ""
                if type == "AudioCustom" || type == "AudioContinuous" { audio += 1; continue }
                guard type == "HapticTransient" || type == "HapticContinuous" else { throw bad() }
                let time = try number(event, "Time")
                let duration = type == "HapticTransient" ? 0.024 : try number(event, "EventDuration")
                guard time >= 0, time <= 3600, duration > 0, duration <= 30 else { throw bad() }
                var intensity = 1.0, sharpness = 0.5
                for parameter in event["EventParameters"] as? [[String: Any]] ?? [] {
                    let value = min(1, max(0, try number(parameter, "ParameterValue")))
                    switch parameter["ParameterID"] as? String {
                    case "HapticIntensity": intensity = value
                    case "HapticSharpness": sharpness = value
                    default: throw bad()
                    }
                }
                events.append(Event(time: time, duration: duration, intensity: intensity, sharpness: sharpness, transient: type == "HapticTransient"))
            } else if let curve = item["ParameterCurve"] as? [String: Any] {
                let id = curve["ParameterID"] as? String
                guard id == "HapticIntensityControl" || id == "HapticSharpnessControl",
                      let raw = curve["ParameterCurveControlPoints"] as? [[String: Any]], !raw.isEmpty, raw.count <= 256 else { throw bad() }
                let start = try number(curve, "Time")
                guard start >= 0, start <= 3600 else { throw bad() }
                var points: [(Double, Double)] = []
                for point in raw {
                    let t = try number(point, "Time"), v = try number(point, "ParameterValue")
                    guard t >= 0, t <= 3600, points.last.map({ t > $0.0 }) ?? true else { throw bad() }
                    points.append((t, min(1, max(id == "HapticSharpnessControl" ? -1 : 0, v))))
                }
                curves.append(Curve(time: start, sharpness: id == "HapticSharpnessControl", points: points))
            } else { throw bad() }
        }
        guard !events.isEmpty, curves.count <= 256 else { throw bad() }
        var edges: [(Double, Int)] = []
        for event in events { edges.append((event.time, 1)); edges.append((event.time + event.duration, -1)) }
        edges.sort { left, right in left.0 == right.0 ? left.1 < right.1 : left.0 < right.0 }
        var simultaneous = 0
        for edge in edges {
            simultaneous += edge.1
            guard simultaneous <= 32 else { throw GlassError("Use a pattern with no more than 32 overlapping haptic events.") }
        }
        self.events = events.sorted { $0.time < $1.time }
        self.curves = curves.sorted { $0.time < $1.time }
        skippedAudio = audio
    }

    // Transport position is the speaker player's audio clock, never a repeating
    // wall-clock loop. Bounded cursors avoid scanning the song on each tick.
    struct Player {
        let pattern: HapticPattern
        private var next = 0
        private var active: [Event] = []
        private var previous = -Double.infinity
        init(_ pattern: HapticPattern) { self.pattern = pattern }
        mutating func frame(at time: Double) -> SignalFrame {
            guard time.isFinite, time >= 0 else { return .empty }
            if time < previous { next = 0; previous = -Double.infinity; active.removeAll(keepingCapacity: true) }
            let last = previous
            previous = time
            active.removeAll { time >= $0.time + $0.duration }
            var beat = 0.0
            while next < pattern.events.count && pattern.events[next].time <= time {
                let event = pattern.events[next]; next += 1
                if event.time + event.duration > time && active.count < 32 {
                    active.append(event)
                    if event.transient && event.time > last { beat = max(beat, event.intensity) }
                }
            }
            let intensity = pattern.curves.last(where: { !$0.sharpness && $0.time <= time })?.value(at: time) ?? 1
            let sharpness = pattern.curves.last(where: { $0.sharpness && $0.time <= time })?.value(at: time) ?? 0
            var weights = [Double](repeating: 0, count: 3)
            for event in active {
                let age = time - event.time
                let attack = event.transient ? 1 : min(1, age / 0.008)
                let release = min(1, (event.duration - age) / (event.transient ? event.duration : min(0.025, event.duration / 2)))
                let strength = event.intensity * intensity * attack * max(0, release)
                let color = min(1, max(0, event.sharpness + sharpness)) * 2
                let low = min(2, Int(color)), high = min(2, low + 1)
                weights[low] += strength * (1 - (color - Double(low)))
                weights[high] += strength * (color - Double(low))
            }
            let total = weights.reduce(0,+)
            return SignalFrame(tones: weights.enumerated().filter { $0.element > 0.001 }.map { Tone(hertz: 125 * Double($0.offset + 1), weight: $0.element) },
                               level: min(1, total), bands: SignalFrame.empty.bands, inputRMS: 0,
                               hasAudio: total > 0, beatStrength: beat)
        }
    }
}

// Causal transient + continuous release layers for live percussion. State is
// bounded and time-based, so timer jitter cannot stretch a pulse indefinitely.
struct MusicalEnvelope {
    private var accents: [(time: Double, strength: Double, frequency: Double)] = []
    mutating func frame(_ signal: SignalFrame, impact: Double = 0.65, detailBalance: Double = 0, at now: Double) -> SignalFrame {
        accents.removeAll { now - $0.time > 0.16 }
        if signal.beatStrength > 0 {
            if accents.count == 16 { accents.removeFirst() }
            accents.append((now, signal.beatStrength, signal.beatFrequency))
        }
        let detail = detailBalance.isFinite ? min(1, max(0, detailBalance)) : 0
        var detailActivity = 0.0
        var tones: [Tone] = []
        for accent in accents {
            let age = max(0, now - accent.time)
            let sharp = accent.frequency >= 250
            let shape = 1.325 - 0.5 * min(1, max(0, impact.isFinite ? impact : 0.65))
            let decay = (sharp ? 0.022 : 0.045) * shape
            let envelope = exp(-age / decay) * min(1, max(0, (0.16 - age) / 0.025))
            if sharp { detailActivity = max(detailActivity, envelope) }
            let weight = accent.strength * envelope * (sharp ? 1 + 0.7 * detail : 1)
            if weight > 0.005 { tones.append(Tone(hertz: accent.frequency, weight: weight)) }
        }
        if signal.bassLevel.isFinite, signal.bassLevel > 0.005 {
            tones.append(Tone(hertz: 125, weight: min(0.28, signal.bassLevel) * (1 - 0.65 * detail * detailActivity)))
        }
        let total = tones.reduce(0) { $0 + $1.weight }
        return SignalFrame(tones: tones, level: min(1, total), bands: signal.bands,
                           inputRMS: signal.inputRMS, hasAudio: signal.hasAudio,
                           beatStrength: signal.beatStrength, beatFrequency: signal.beatFrequency)
    }
}

// Every source uses this automatic path. It has no dependency on a file,
// catalog identifier or imported AHAP document. Only authored overrides are local.
struct AutomaticHaptics {
    private var percussion = MusicalEnvelope()
    private var previousMode: OutputMode?
    private var previousFocus: HapticFocus?
    private var bothAccentAt = -Double.infinity
    private var bothEdgeFrequency = 375.0
    private var previousTime: Double?

    mutating func frame(_ signal: SignalFrame, mode: OutputMode, blocked: Bool, focus: HapticFocus? = nil, impact: Double = 0.65, detailBalance: Double = 0, at now: Double) -> SignalFrame {
        guard now.isFinite else { self = AutomaticHaptics(); return .empty }
        let focus = focus ?? (mode == .assist ? .beat : .voice)
        if previousMode != mode || previousFocus != focus || previousTime.map({ now < $0 || now - $0 > 0.2 }) == true {
            percussion = MusicalEnvelope()
            bothAccentAt = -Double.infinity
        }
        previousMode = mode
        previousFocus = focus
        previousTime = now
        guard !blocked else { percussion = MusicalEnvelope(); bothAccentAt = -Double.infinity; return .empty }
        // Vocal harmonic/pitch shaping is performed on the live or isolated PCM.
        // Keep its frequencies intact; rhythm mode builds transient/release layers.
        guard focus.includesBeat else { return signal }
        let beat = percussion.frame(signal, impact: impact, detailBalance: detailBalance, at: now)
        guard focus == .both else { return beat }
        // Reserve room for each layer. A stronger voice cannot erase the beat,
        // and enabling Both never raises the existing output ceiling.
        func layer(_ frame: SignalFrame, mix: Double) -> [Tone] {
            let valid = frame.tones.filter { $0.hertz.isFinite && $0.hertz > 0 && $0.weight.isFinite && $0.weight > 0 }
            let total = valid.reduce(0) { $0 + $1.weight }
            guard total > 0 else { return [] }
            let level = frame.level.isFinite ? min(1, max(0, frame.level)) : 0
            return valid.map { Tone(hertz: $0.hertz, weight: $0.weight / total * level * mix) }
        }
        if signal.beatStrength.isFinite && signal.beatStrength > 0 {
            bothAccentAt = now
            bothEdgeFrequency = signal.beatFrequency >= 250 ? 125 : 375
        }
        // A real onset briefly moves the vocal bed behind the percussion, then
        // recovers in about 100 ms. No onset means no duck and no extra event.
        let duck = 0.88 * exp(-max(0, now - bothAccentAt) / 0.032)
        let voice = layer(signal, mix: 0.55)
        let voiceLevel = voice.reduce(0) { $0 + $1.weight }
        let percussion = layer(beat, mix: 0.8)
        let edgeShare = 0.22 * exp(-max(0, now - bothAccentAt) / 0.010)
        let edgeWeight = percussion.reduce(0) { $0 + $1.weight } * edgeShare
        var tones = voice.map { Tone(hertz: $0.hertz, weight: $0.weight * (1 - duck)) }
        tones += percussion.map { Tone(hertz: $0.hertz, weight: $0.weight * (1 - edgeShare)) }
        // A brief complementary texture keeps a hit legible even when its main
        // carrier matches a vocal. Redistribute weight; never add output gain.
        if edgeWeight > 0.0001 { tones.append(Tone(hertz: bothEdgeFrequency, weight: edgeWeight)) }
        let total = tones.reduce(0) { $0 + $1.weight }
        // Preserve the bed's level rather than making a quiet hit feel like a
        // dropout. This is never louder than the previous un-ducked blend.
        let level = min(1, max(total, voiceLevel))
        let scale = total > 0 ? level / total : 0
        return SignalFrame(tones: tones.map { Tone(hertz: $0.hertz, weight: $0.weight * scale) },
            level: level, bands: signal.bands, inputRMS: signal.inputRMS,
            hasAudio: signal.hasAudio || beat.hasAudio, beatStrength: signal.beatStrength,
            beatFrequency: signal.beatFrequency)
    }
}

// Continuous vocal and percussion levels share a host-time envelope. This avoids
// changing attack/release speed when capture callbacks or the render timer jitter.
struct MotorEnvelope {
    private var value = 0.0
    private var previousTime: Double?

    mutating func level(target: Double, transient: Bool, at now: Double) -> Double {
        guard now.isFinite, target.isFinite else { self = MotorEnvelope(); return 0 }
        let elapsed = max(0, min(0.08, now - (previousTime ?? (now - 0.008))))
        if previousTime.map({ now < $0 || now - $0 > 0.2 }) == true { value = 0 }
        previousTime = now
        let clean = min(1, max(0, target))
        let duration = clean > value ? (transient ? 0.0035 : 0.010) : 0.010
        value += (clean - value) * (1 - exp(-elapsed / duration))
        if clean == 0 && value < 0.0001 { value = 0 }
        return value
    }
}
