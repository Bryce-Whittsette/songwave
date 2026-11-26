import Foundation

@main
struct RhythmRegression {
    static func main() throws {
        let hits = [0.55, 1.02, 1.64, 1.91, 2.48, 3.15, 3.50, 4.22]
        var checks = 0
        for rate in [8000.0, 16000, 22050, 24000, 44100, 48000] {
            for voiceAmplitude in [0.025, 0.30] {
                for mode in OutputMode.allCases {
                    let events = try analyze(rate: rate, mode: mode) { time in
                        let voice = voiceAmplitude * sin(2 * .pi * 224 * time)
                        let local = time - (hits.last(where: { $0 <= time }) ?? -10)
                        let kick = 0.08 * exp(-local * 23) *
                            sin(2 * .pi * (70 * local + 1.5 * (1 - exp(-local * 30))))
                        return Float(voice + kick)
                    }
                    let matched = hits.filter { hit in
                        events.contains { (0...0.15).contains($0 - hit) }
                    }
                    precondition(matched.count == hits.count && events.count == hits.count,
                                 "A foreground tone hid a kick or caused a false beat. Rate \(rate), voice \(voiceAmplitude), mode \(mode), events \(events)")
                    checks += 1
                }
            }
        }

        // Short voiced syllables have strong onsets and gaps. They must not be
        // mistaken for drum hits simply because the fundamental is in the bass.
        for fundamental in [95.0, 125, 175, 225] {
            let events = try analyze(rate: 24000, mode: .assist) { time in
                let local = time.truncatingRemainder(dividingBy: 0.37)
                let envelope = local < 0.22 ?
                    min(1, local / 0.025) * min(1, (0.22 - local) / 0.05) : 0
                var voice = 0.0
                for harmonic in 1...12 {
                    voice += sin(2 * .pi * fundamental * Double(harmonic) * time) / Double(harmonic)
                }
                return Float(voice * envelope * 0.07)
            }
            precondition(events.isEmpty, "A low voiced syllable triggered a beat.")
            checks += 1
        }

        try quietDetails()
        try timing()
        captureGaps()

        var pulse = KeyboardPulse()
        precondition(pulse.level(beatStrength: 0.9, at: 1) > 0.90)
        precondition(pulse.level(beatStrength: 0, at: 1.10) < 0.50)
        precondition(pulse.level(beatStrength: 0, at: 1.25) < 0.03)
        precondition(pulse.level(beatStrength: 0, at: 2) < 0.03)
        print("\(checks) rhythm cases passed. Vocal onsets were rejected and each light pulse faded between beats.")
    }

    static func analyze(rate: Double, mode: OutputMode, sample: (Double) -> Float) throws -> [Double] {
        let analyzer = try Spectrum(sampleRate: rate)
        let tuning = mode.defaults
        analyzer.configure(tuning.eq)
        let cadence = mode == .assist ? 0.008 : 0.016
        let blockSize = max(1, Int(rate * cadence))
        let blocks = Int(rate * 5 / Double(blockSize))
        var events: [Double] = []
        for block in 0..<blocks {
            for offset in 0..<blockSize {
                analyzer.append(sample(Double(block * blockSize + offset) / rate))
            }
            let frame = analyzer.frame(tuning: tuning, mode: mode)
            if frame.beatStrength > 0 {
                events.append(Double((block + 1) * blockSize) / rate)
                if mode == .assist {
                    precondition(frame.level > 0.40 && !frame.tones.isEmpty,
                                 "The beat was detected without a corresponding haptic attack.")
                }
            }
        }
        return events
    }
    static func quietDetails() throws {
        let rate = 24000.0
        let kicks = [0.4, 1.4, 2.4]
        let hats = [0.62, 0.73, 1.62, 1.73, 2.62, 2.73]
        let mids = [0.98, 1.98, 2.98]
        let analyzer = try Spectrum(sampleRate: rate)
        var random: UInt64 = 27
        var low250 = 0.0, low1800 = 0.0, low3500 = 0.0
        var found: [(time: Double, strength: Double)] = []
        for block in 0..<450 {
            for index in 0..<192 {
                let time = Double(block * 192 + index) / rate
                random = random &* 6364136223846793005 &+ 1
                let noise = Double(random >> 11) / 9007199254740992 - 0.5
                low250 += (noise - low250) * (1 - exp(-2 * .pi * 250 / rate))
                low1800 += (noise - low1800) * (1 - exp(-2 * .pi * 1800 / rate))
                low3500 += (noise - low3500) * (1 - exp(-2 * .pi * 3500 / rate))
                let kickAge = time - (kicks.last(where: { $0 <= time }) ?? -10)
                let hatAge = time - (hats.last(where: { $0 <= time }) ?? -10)
                let midAge = time - (mids.last(where: { $0 <= time }) ?? -10)
                let kick = 0.3 * exp(-kickAge * 23) *
                    sin(2 * .pi * (70 * kickAge + 1.5 * (1 - exp(-kickAge * 30))))
                let hat = 0.004 * exp(-hatAge * 70) * (noise - low3500)
                let mid = 0.004 * exp(-midAge * 45) * (low1800 - low250)
                let voice = 0.07 * sin(2 * .pi * 224 * time) + 0.03 * sin(2 * .pi * 448 * time)
                analyzer.append(Float(kick + hat + mid + voice))
            }
            let frame = analyzer.frame(tuning: OutputMode.assist.defaults, mode: .assist)
            if frame.beatStrength > 0 {
                found.append((Double((block + 1) * 192) / rate, frame.beatStrength))
            }
        }
        for hit in kicks + hats + mids {
            precondition(found.contains { (0...0.05).contains($0.time - hit) },
                         "A quiet midrange or treble attack was lost.")
        }
        precondition(found.count == kicks.count + hats.count + mids.count,
                     "Extra percussion events were invented.")
        for hit in hats + mids {
            precondition(found.first { (0...0.05).contains($0.time - hit) }!.strength < 0.5,
                         "Quiet details should remain softer than kick accents.")
        }
        print("Quiet percussion, rapid consecutive hits, and loud kicks kept their timing and relative strength.")
    }

    static func captureGaps() {
        var tail = AssistTail()
        let hit = SignalFrame(tones: [Tone(hertz: 375, weight: 1)], level: 0.35,
                              bands: [], inputRMS: 0.02, hasAudio: true,
                              beatStrength: 0.35, beatFrequency: 375)
        let attack = tail.resolve(hit, advanced: true, enabled: true, at: 1)
        let gap = tail.resolve(.empty, advanced: false, enabled: true, at: 1.008)
        precondition(attack.beatStrength == 0.35 && gap.beatStrength == 0 &&
                     gap.level > 0.25 && gap.level < attack.level && !gap.tones.isEmpty,
                     "A capture gap must preserve a fading quiet tail without another beat.")
        precondition(!tail.resolve(.empty, advanced: false, enabled: true, at: 1.04).hasAudio,
                     "A stalled capture must not retain stale haptics.")
        _ = tail.resolve(hit, advanced: true, enabled: true, at: 2)
        precondition(!tail.resolve(.empty, advanced: false, enabled: false, at: 2.008).hasAudio)
        precondition(!tail.resolve(.empty, advanced: false, enabled: true, at: 2.016).hasAudio,
                     "Suppression must clear the retained tail immediately.")
        _ = tail.resolve(hit, advanced: true, enabled: true, at: 3)
        _ = tail.resolve(.empty, advanced: true, enabled: true, at: 3.008)
        precondition(!tail.resolve(.empty, advanced: false, enabled: true, at: 3.016).hasAudio,
                     "A captured silent frame must not resurrect the previous hit.")
    }

    static func timing() throws {
        let base = OutputTiming.additionalDelay(reported: 0.2, analysisRate: 24000, offsetMS: 0)
        let earlier = OutputTiming.additionalDelay(reported: 0.2, analysisRate: 24000, offsetMS: -50)
        let later = OutputTiming.additionalDelay(reported: 0.2, analysisRate: 24000, offsetMS: 50)
        precondition(abs(base - earlier - 0.05) < 1e-9 && abs(later - base - 0.05) < 1e-9)
        precondition(OutputTiming.additionalDelay(reported: 0, analysisRate: 24000, offsetMS: -100) == 0)
        precondition(abs(OutputTiming.additionalDelay(reported: 0, analysisRate: 24000, offsetMS: 100) - 0.1) < 1e-9)

        func decode(_ extras: String) throws -> Tuning {
            let json = #"{"profile":"Balanced","gain":0.4,"tone":0,"impact":0.65,"# + extras + "}"
            return try JSONDecoder().decode(Tuning.self, from: Data(json.utf8))
        }
        let legacy = try decode(#""delay":80"#)
        precondition(!legacy.automaticTiming && legacy.delay == 80,
                     "An existing manual calibration must not gain automatic delay.")
        let zero = try decode(#""delay":0"#)
        let explicit = try decode(#""delay":80,"automaticTiming":true"#)
        precondition(zero.automaticTiming && explicit.automaticTiming)

    }

}
