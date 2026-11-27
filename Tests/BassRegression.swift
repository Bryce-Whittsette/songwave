import Foundation

@main struct BassRegression {
    static func main() throws {
        for rate in [16000.0, 24000, 44100, 48000, 96000] {
            for frequency in [25.0, 30, 35, 40, 55, 65, 70, 80] {
                let levels = try analyze(rate: rate) { time in
                    Float(0.12 * sin(2 * .pi * frequency * time))
                }
                precondition(levels.dropFirst(60).filter { $0 > 0.04 }.count > 100,
                             "Sustained low bass was not kept at \(rate), \(frequency)")
                precondition(levels.allSatisfy { $0.isFinite && (0...0.28).contains($0) })
            }
            for fundamental in [95.0, 125, 175, 225] {
                let levels = try analyze(rate: rate) { time in
                    let age = time.truncatingRemainder(dividingBy: 0.37)
                    let envelope = age < 0.22 ? min(1, age / 0.025) * min(1, (0.22 - age) / 0.05) : 0
                    return Float((1...12).reduce(0.0) { $0 + sin(2 * .pi * fundamental * Double($1) * time) / Double($1) } * envelope * 0.07)
                }
                precondition(levels.allSatisfy { $0 < 0.005 },
                             "A voiced syllable became bass sustain at \(rate), \(fundamental): \(levels.max()!)")
            }
        }
        for rate in [16000.0, 24000, 44100, 48000, 96000] {
            for hz in [25.0, 35, 55, 65] {
                let quiet = try analyze(rate: rate) { Float(0.006 * sin(2 * .pi * hz * $0)) }
                precondition(quiet.dropFirst(60).filter { $0 > 0.005 }.count > 150,
                    "Quiet sub-bass should remain continuous at \(rate), \(hz).")
            }
        }
        let dc = try analyze(rate: 48000) { _ in Float(0.12) }
        precondition(dc.dropFirst(100).allSatisfy { $0 < 0.005 }, "DC must not become sustained bass.")
        let levels = try analyze(rate: 24000) { time in
            Float(time >= 0.25 && time < 0.75 ? 0.12 * sin(2 * .pi * 65 * time) : 0)
        }
        precondition(levels.prefix(25).allSatisfy { $0 == 0 })
        precondition(levels.dropFirst(120).allSatisfy { $0 == 0 }, "A stopped bass note left stale rumble.")
        let muted = try analyze(rate: 24000, sustain: 0) { Float(0.12 * sin(2 * .pi * 65 * $0)) }
        precondition(muted.allSatisfy { $0 == 0 })
        var renderer = AutomaticHaptics()
        let bass = SignalFrame(tones: [], level: 0.2, bands: [], inputRMS: 0.05, hasAudio: true, bassLevel: 0.2)
        let output = renderer.frame(bass, mode: .assist, blocked: false, at: 1)
        precondition(output.level > 0 && output.beatStrength == 0 && output.tones.first?.hertz == 125,
                     "Continuous bass must not invent a drum or keyboard-light event.")
        precondition(renderer.frame(bass, mode: .assist, blocked: true, at: 1.008).level == 0)
        var soft = MusicalEnvelope(), sharp = MusicalEnvelope()
        let hit = SignalFrame(tones: [], level: 1, bands: [], inputRMS: 0, hasAudio: true, beatStrength: 1)
        _ = soft.frame(hit, impact: 0, at: 1); _ = sharp.frame(hit, impact: 1, at: 1)
        precondition(soft.frame(.empty, impact: 0, at: 1.05).level > sharp.frame(.empty, impact: 1, at: 1.05).level,
                     "Transient emphasis must change the attack-to-tail contrast.")
        print("Low bass, voiced rejection across five rates, quiet 25–65 Hz notes, sustain bypass, silence and call suppression passed.")
    }
    static func analyze(rate: Double, sustain: Double = 1, sample: (Double) -> Float) throws -> [Double] {
        let spectrum = try Spectrum(sampleRate: rate)
        var tuning = OutputMode.assist.defaults
        tuning.bassSustain = sustain
        let size = Int(rate * 0.008)
        var levels: [Double] = []
        for frame in 0..<250 {
            for offset in 0..<size { spectrum.append(sample(Double(frame * size + offset) / rate)) }
            levels.append(spectrum.frame(tuning: tuning, mode: .assist).bassLevel)
        }
        return levels
    }
}
