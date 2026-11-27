import Foundation

@main struct BothRegression {
    static func main() throws {
        let mixed = SignalFrame(tones: [Tone(hertz: 220, weight: 0.8), Tone(hertz: 440, weight: 0.2)],
            level: 0.8, bands: [], inputRMS: 0.1, hasAudio: true,
            beatStrength: 0.7, beatFrequency: 375, bassLevel: 0.2)
        var renderer = AutomaticHaptics()
        let output = renderer.frame(mixed, mode: .assist, blocked: false, focus: .both, at: 1)
        precondition(output.tones.contains { $0.hertz == 220 && $0.weight > 0 })
        precondition(output.tones.contains { $0.hertz == 375 && $0.weight > 0 })
        precondition(output.tones.contains { $0.hertz == 125 && $0.weight > 0 })
        precondition(output.level <= 1 && output.beatStrength == mixed.beatStrength)
        precondition(abs(output.tones.reduce(0) { $0 + $1.weight } - output.level) < 1e-9)
        let tail = SignalFrame(tones: mixed.tones, level: mixed.level, bands: [], inputRMS: 0.1, hasAudio: true)
        let voice = renderer.frame(tail, mode: .assist, blocked: false, focus: .voice, at: 1.008)
        precondition(voice.tones.allSatisfy { $0.hertz == 220 || $0.hertz == 440 }, "Leaving Both must discard percussion tails.")
        let back = renderer.frame(tail, mode: .assist, blocked: false, focus: .both, at: 1.016)
        precondition(!back.tones.contains { $0.hertz == 375 }, "Returning to Both must not replay an old beat.")
        precondition(renderer.frame(mixed, mode: .assist, blocked: true, focus: .both, at: 1.024).level == 0)
        precondition(renderer.frame(.empty, mode: .assist, blocked: false, focus: .both, at: 1.032).tones.isEmpty)
        for i in 0..<100 {
            let loud = SignalFrame(tones: mixed.tones, level: 1, bands: [], inputRMS: 1, hasAudio: true,
                beatStrength: 1, beatFrequency: 375, bassLevel: 1)
            let frame = renderer.frame(loud, mode: .assist, blocked: false, focus: .both, at: 2 + Double(i) * 0.008)
            precondition(frame.level.isFinite && frame.level <= 1 && frame.tones.count <= 26)
            precondition(frame.tones.allSatisfy { $0.weight.isFinite && $0.weight >= 0 })
        }
        // Exercise the actual one-FFT analyzer on mixed PCM, not a synthesized
        // output frame alone. This is a controlled fixture, not song recall.
        for rate in [16000.0, 24000, 48000] {
            let spectrum = try Spectrum(sampleRate: rate)
            var tuning = OutputMode.assist.defaults
            tuning.hapticFocus = .both
            tuning.vocalQuality = .isolated // Both must stay on the Light DSP path.
            let hits = [0.5, 1.1, 1.7]
            var beats = 0, vocals = 0
            let block = Int(rate * 0.008)
            for n in 0..<Int(rate * 2.4) {
                let t = Double(n) / rate
                var voice = 0.0
                for h in 1...10 { voice += 0.045 / Double(h) * sin(2 * .pi * 225 * Double(h) * t) }
                let age = t - (hits.last { $0 <= t } ?? -10)
                let kick = 0.18 * exp(-age * 35) * sin(2 * .pi * 80 * age)
                spectrum.append(Float(voice + kick))
                if n % block == block - 1 {
                    let frame = spectrum.frame(tuning: tuning, mode: .assist)
                    if frame.level > 0.05 && !frame.tones.isEmpty { vocals += 1 }
                    if frame.beatStrength > 0 { beats += 1 }
                    precondition(frame.level.isFinite && frame.bassLevel.isFinite)
                }
            }
            precondition(vocals > 100 && beats >= 3 && beats <= 5, "Both lost its vocal or rhythmic layer at \(rate): \(vocals), \(beats)")
        }
        print("Both retains voice/bass/attacks, stays bounded, clears tails on focus/suppression, and analyzes mixed PCM through one spectrum at three rates.")
    }
}
