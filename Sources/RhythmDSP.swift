import Foundation

// Causal low-bass envelope. This is an energy estimate, not a separated stem.
// Pitch evidence from the existing FFT gates the output so vocal fundamentals
// above the low-bass range do not turn into sustained motor vibration.
struct BassEnvelope {
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
        highPass = 1 - exp(-2 * .pi * 25 / rate)
        lowPass = 1 - exp(-2 * .pi * 100 / rate)
        attack = 1 - exp(-1 / (rate * 0.008))
        release = 1 - exp(-1 / (rate * 0.035))
    }

    mutating func resetEvidence() {
        candidateSince = nil
        previousTime = nil
    }

    mutating func append(_ input: Float) {
        let sample = input.isFinite ? Double(input) : 0
        dc += (sample - dc) * highPass
        low1 += (sample - dc - low1) * lowPass
        low2 += (low1 - low2) * lowPass
        let next = low2 * low2
        power += (next - power) * (next > power ? attack : release)
    }

    mutating func level(pitch: Double, magnitude: Double, at time: Double) -> Double {
        let dt = max(0, time - (previousTime ?? time))
        previousTime = time
        guard pitch.isFinite, magnitude.isFinite, time.isFinite,
              (38...85).contains(pitch), magnitude > 0.0007 else {
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
