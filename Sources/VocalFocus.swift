import Foundation

// A small, causal harmonic tracker for the Light vocal setting. It follows a
// coherent voice-shaped harmonic stack instead of reproducing every loud bin.
// This is a vocal focus filter, not a source-separation model: harmonically
// rich instruments can still resemble a singer in a mixed recording.
struct VocalFocus {
    struct Result {
        var tones: [Tone] = []
        var level = 0.0
        var confidence = 0.0
        var fundamental: Double?
        static var empty: Result { Result() }
    }

    private struct Peak {
        let frequency: Double
        let amplitude: Double
    }
    private struct Candidate {
        let frequency: Double
        let score: Double
        let confidence: Double
        let amplitude: Double
        let harmonics: [Peak]
    }
    private var lastPitch: Double?
    private var pendingPitch: Double?
    private var pendingAt = 0.0
    private var lastVoicedAt = -Double.infinity
    private var lastTime: Double?
    private var reference = 0.025
    private var previous = Result.empty

    mutating func frame(magnitudes: [Float], binWidth: Double, analysisSize: Int,
                        at time: Double, tuning: Tuning) -> Result {
        guard binWidth.isFinite, binWidth > 0, time.isFinite, analysisSize > 0,
              magnitudes.count >= 8 else { self = VocalFocus(); return .empty }
        let elapsed = min(0.1, max(0, time - (lastTime ?? time)))
        lastTime = time
        let scale = Double(analysisSize)
        let upper = min(magnitudes.count - 4, Int(4500 / binWidth))
        let lower = max(2, Int(85 / binWidth))
        guard lower < upper else { return release(at: time, elapsed: elapsed) }

        var logSum = 0.0, linearSum = 0.0
        let flatnessLower = max(lower, Int(250 / binWidth))
        guard flatnessLower <= upper else { return release(at: time, elapsed: elapsed) }
        for bin in flatnessLower...upper {
            let magnitude = max(1e-12, Double(magnitudes[bin]))
            guard magnitude.isFinite else { self = VocalFocus(); return .empty }
            logSum += log(magnitude)
            linearSum += magnitude
        }
        let bins = Double(upper - flatnessLower + 1)
        let flatness = exp(logSum / bins) / max(1e-12, linearSum / bins)
        guard flatness < 0.60 else { return release(at: time, elapsed: elapsed) }

        // The strongest bounded set of resolved peaks supplies candidate F0s.
        // Every candidate is tested against the complete harmonic family below.
        var peaks: [Peak] = []
        peaks.reserveCapacity(48)
        for bin in lower...upper {
            let value = Double(magnitudes[bin])
            guard value.isFinite, value > 0.00003 * scale,
                  value > Double(magnitudes[bin - 1]), value >= Double(magnitudes[bin + 1]) else { continue }
            let left = log(max(1e-9, Double(magnitudes[bin - 1])))
            let center = log(max(1e-9, value))
            let right = log(max(1e-9, Double(magnitudes[bin + 1])))
            let curve = left - 2 * center + right
            let offset = abs(curve) > 1e-9 ? max(-0.5, min(0.5, 0.5 * (left - right) / curve)) : 0
            peaks.append(Peak(frequency: (Double(bin) + offset) * binWidth, amplitude: value / scale))
        }
        peaks.sort { $0.amplitude > $1.amplitude }
        if peaks.count > 48 { peaks.removeSubrange(48...) }
        guard !peaks.isEmpty else { return release(at: time, elapsed: elapsed) }

        func amplitude(near frequency: Double) -> Double {
            let center = Int((frequency / binWidth).rounded())
            guard center >= 3, center <= upper else { return 0 }
            let peakBin = ((center - 1)...(center + 1)).max { magnitudes[$0] < magnitudes[$1] } ?? center
            let peak = Double(magnitudes[peakBin])
            guard peakBin >= 1, peakBin + 1 < magnitudes.count else { return 0 }
            let left = log(max(1e-9, Double(magnitudes[peakBin - 1])))
            let middle = log(max(1e-9, peak))
            let right = log(max(1e-9, Double(magnitudes[peakBin + 1])))
            let curve = left - 2 * middle + right
            let offset = abs(curve) > 1e-9 ? max(-0.5, min(0.5, 0.5 * (left - right) / curve)) : 0
            let resolved = (Double(peakBin) + offset) * binWidth
            guard abs(resolved - frequency) <= max(binWidth * 0.55, frequency * 0.01) else { return 0 }
            // Hann-windowed tones are concentrated around a peak; broadband
            // percussion has similar energy in the neighboring shoulders.
            let shoulder = (Double(magnitudes[center - 3]) + Double(magnitudes[center + 3])) * 0.5
            guard peak.isFinite, shoulder.isFinite, peak > shoulder * 1.8 else { return 0 }
            return max(0, peak - shoulder * 1.3) / scale
        }
        var best: Candidate?
        for peak in peaks {
            for divisor in 1...8 {
                let pitch = peak.frequency / Double(divisor)
                guard (85...1000).contains(pitch) else { continue }
                let count = min(16, Int(4500 / pitch))
                guard count >= 3 else { continue }
                var harmonics: [Peak] = []
                harmonics.reserveCapacity(count)
                var weighted = 0.0, weights = 0.0, high = 0.0, total = 0.0
                var first = false, second = false, odd = false
                for harmonic in 1...count {
                    let frequency = pitch * Double(harmonic)
                    let value = amplitude(near: frequency)
                    let weight = 1 / sqrt(Double(harmonic))
                    weights += weight
                    guard value >= max(0.00003, peak.amplitude * 0.025) else { continue }
                    if harmonic == 1 { first = true }
                    if harmonic == 2 { second = true }
                    if harmonic >= 3 && harmonic % 2 == 1 { odd = true }
                    total += value
                    if frequency >= 650 { high += value }
                    // Formant-region evidence helps avoid following a bass note.
                    let formant = frequency >= 450 && frequency <= 3500 ? 1.0 : 0.55
                    weighted += value * weight * formant
                    harmonics.append(Peak(frequency: frequency, amplitude: value))
                }
                guard harmonics.count >= 3, first || second, odd,
                      high > total * 0.18, total > 0.00025 else { continue }
                let coverage = Double(harmonics.count) / Double(count)
                // Sparse subharmonic explanations lose to a family whose
                // actual fundamental and odd harmonics are present.
                let coherence = 0.45 + 0.55 * sqrt(coverage)
                var score = weighted / max(1, sqrt(weights)) * coherence
                if first { score *= 1.12 }
                if let lastPitch {
                    let cents = abs(1200 * log2(pitch / lastPitch))
                    score *= cents < 120 ? 1.22 : cents < 400 ? 1.05 : 0.95
                }
                if score > (best?.score ?? 0) {
                    best = Candidate(frequency: pitch, score: score,
                                     confidence: min(1, coverage * 1.4),
                                     amplitude: sqrt(harmonics.reduce(0) { $0 + $1.amplitude * $1.amplitude }),
                                     harmonics: harmonics)
                }
            }
        }
        guard let best else { return release(at: time, elapsed: elapsed) }

        // Confirm a new family over two frames. Noise spikes tend not to keep a
        // stable fundamental, while vibrato and ordinary note movement do.
        let wasTracking = lastPitch.map { abs(1200 * log2(best.frequency / $0)) < 160 && time - lastVoicedAt < 0.06 } ?? false
        let confirmed = pendingPitch.map { abs(1200 * log2(best.frequency / $0)) < 75 && time - pendingAt <= 0.06 } ?? false
        pendingPitch = best.frequency
        pendingAt = time
        guard wasTracking || confirmed else { return release(at: time, elapsed: elapsed) }
        let smoothing = max(0, tuning.smoothing) / 1000
        let blend = smoothing > 0 ? 1 - exp(-max(0.001, elapsed) / smoothing) : 1
        let pitch = wasTracking ? (lastPitch ?? best.frequency) + (best.frequency - (lastPitch ?? best.frequency)) * blend : best.frequency
        lastPitch = pitch
        lastVoicedAt = time
        reference = max(0.012, max(best.amplitude, reference * exp(-elapsed / 2.0)))
        let target = min(1, pow(best.amplitude / reference, 0.75))
        let attack = 1 - exp(-max(0.001, elapsed) / 0.012)
        let release = 1 - exp(-max(0.001, elapsed) / 0.035)
        let level = previous.level + (target - previous.level) * (target >= previous.level ? attack : release)
        let ratio = pitch / best.frequency
        var tones: [Tone] = []
        let shaped = best.harmonics.map { harmonic -> Peak in
            let emphasis: Double
            switch tuning.profile {
            case .balanced: emphasis = 1
            case .detail: emphasis = min(1.4, max(0.7, pow(harmonic.frequency / 600, 0.22)))
            case .pulse: emphasis = harmonic.frequency <= best.frequency * 3.1 ? 1.25 : 0.55
            }
            let color = pow(harmonic.frequency / 440, tuning.tone * 0.5)
            return Peak(frequency: harmonic.frequency, amplitude: harmonic.amplitude * emphasis * color)
        }
        for harmonic in shaped.sorted(by: { $0.amplitude > $1.amplitude }) {
            var frequency = harmonic.frequency * ratio
            while frequency < 100 { frequency *= 2 }
            guard frequency <= 4000 else { continue }
            tones.append(Tone(hertz: frequency, weight: harmonic.amplitude))
            if tones.count >= min(8, max(2, tuning.partials)) { break }
        }
        previous = Result(tones: tones, level: level, confidence: best.confidence, fundamental: pitch)
        return previous
    }

    private mutating func release(at time: Double, elapsed: Double) -> Result {
        guard time - lastVoicedAt <= 0.045 else {
            previous = .empty
            lastPitch = nil
            return .empty
        }
        previous.level *= exp(-elapsed / 0.025)
        previous.confidence *= exp(-elapsed / 0.025)
        if previous.level < 0.025 { previous = .empty }
        return previous
    }
}
