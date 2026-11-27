import Foundation

// Causal low-bass envelope. This is an energy estimate, not a separated stem.
// Pitch evidence from the existing FFT gates the output so vocal fundamentals
// above the low-bass range do not turn into sustained motor vibration.
struct BassEnvelope {
    private let rate: Double
    private var sampleCount = 0.0
    private var previousLow = 0.0
    private var crossingAt: Double?
    private var cyclePitch: Double?
    private var stableCycles = 0
    private let highPass: Double
    private let lowPass: Double
    private let attack: Double
    private let release: Double
    private var dc = 0.0
    private var low1 = 0.0
    private var low2 = 0.0
    private var power = 0.0
    private var reference = 0.025
    private var previousTime: Double?
    private var candidateSince: Double?

    init(rate: Double) {
        self.rate = rate
        highPass = 1 - exp(-2 * .pi * 25 / rate)
        lowPass = 1 - exp(-2 * .pi * 100 / rate)
        attack = 1 - exp(-1 / (rate * 0.008))
        release = 1 - exp(-1 / (rate * 0.035))
    }

    mutating func resetEvidence() {
        candidateSince = nil
        previousTime = nil
        crossingAt = nil; cyclePitch = nil; stableCycles = 0
    }

    mutating func append(_ input: Float) {
        let sample = input.isFinite ? Double(input) : 0
        dc += (sample - dc) * highPass
        low1 += (sample - dc - low1) * lowPass
        low2 += (low1 - low2) * lowPass
        sampleCount += 1
        if previousLow <= 0 && low2 > 0 {
            let crossing = sampleCount - low2 / max(1e-12, low2 - previousLow)
            if let before = crossingAt, crossing > before {
                let pitch = rate / (crossing - before)
                if pitch.isFinite && (10...500).contains(pitch) {
                    stableCycles = cyclePitch.map { abs(pitch - $0) / max(1, $0) < 0.15 } == true ? min(3, stableCycles + 1) : 1
                    cyclePitch = pitch
                } else { stableCycles = 0; cyclePitch = nil }
            }
            crossingAt = crossing
        }
        previousLow = low2
        let next = low2 * low2
        power += (next - power) * (next > power ? attack : release)
    }

    mutating func level(pitch: Double, magnitude: Double, at time: Double) -> Double {
        let dt = max(0, time - (previousTime ?? time))
        previousTime = time
        // A short FFT cannot resolve sub-bass reliably at every output rate.
        // Reuse the causal low-pass signal's stable periods, with FFT fallback
        // during the initial cycles. This adds no lookahead or sample buffer.
        let periodIsFresh = crossingAt.map { sampleCount - $0 < rate * 0.10 } == true
        let resolvedPitch = stableCycles >= 2 && periodIsFresh ? (cyclePitch ?? pitch) : pitch
        let lowEnough = stableCycles >= 2 && periodIsFresh ? (24...85).contains(resolvedPitch) : (38...85).contains(resolvedPitch)
        guard resolvedPitch.isFinite, magnitude.isFinite, time.isFinite,
              lowEnough, (pitch < 90), magnitude > (stableCycles >= 2 && periodIsFresh ? 0.0002 : 0.0007) else {
            candidateSince = nil
            return 0
        }
        if candidateSince == nil { candidateSince = time }
        // A single incomplete voiced onset is weak evidence of a bass note.
        guard time - candidateSince! >= 0.016 else { return 0 }
        let rms = sqrt(max(0, power))
        reference = max(0.012, max(rms, reference * exp(-dt / 1.5)))
        guard rms > 0.001 else { return 0 }
        return min(0.28, 0.28 * pow(rms / reference, 0.8))
    }
}
