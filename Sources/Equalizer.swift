import Foundation

enum Band: String, CaseIterable, Identifiable, Codable {
    case bass = "Bass"
    case mid = "Mid"
    case treble = "Treble"

    var id: Self { self }

    var range: ClosedRange<Double> {
        switch self {
        case .bass: return 65...320
        case .mid: return 250...1800
        case .treble: return 1300...4000
        }
    }

    var center: Double {
        switch self {
        case .bass: return 140
        case .mid: return 720
        case .treble: return 2600
        }
    }
}

struct EQBand: Codable, Equatable {
    var frequency: Double
    var gain = 0.0
    var q = 0.75
}

struct EQ: Codable, Equatable {
    var enabled = true
    var bass = EQBand(frequency: Band.bass.center)
    var mid = EQBand(frequency: Band.mid.center)
    var treble = EQBand(frequency: Band.treble.center)

    subscript(_ band: Band) -> EQBand {
        get {
            switch band {
            case .bass: return bass
            case .mid: return mid
            case .treble: return treble
            }
        }
        set {
            switch band {
            case .bass: bass = newValue
            case .mid: mid = newValue
            case .treble: treble = newValue
            }
        }
    }

    func response(at frequency: Double) -> Double {
        guard enabled else { return 0 }
        let rate = 24_000.0
        return Band.allCases.reduce(0) { total, band in
            total + Biquad(band: self[band], rate: rate).decibels(at: frequency, rate: rate)
        }
    }
}

extension EQ {
    init(from decoder: Decoder) throws {
        let values = try decoder.container(keyedBy: CodingKeys.self)
        enabled = try values.decodeIfPresent(Bool.self, forKey: .enabled) ?? enabled
        bass = try values.decodeIfPresent(EQBand.self, forKey: .bass) ?? bass
        mid = try values.decodeIfPresent(EQBand.self, forKey: .mid) ?? mid
        treble = try values.decodeIfPresent(EQBand.self, forKey: .treble) ?? treble
        for band in Band.allCases {
            var settings = self[band]
            settings.frequency = min(band.range.upperBound, max(band.range.lowerBound, settings.frequency))
            settings.gain = min(12, max(-12, settings.gain))
            settings.q = min(3.5, max(0.35, settings.q))
            self[band] = settings
        }
    }
}

struct Biquad {
    private let b0: Double
    private let b1: Double
    private let b2: Double
    private let a1: Double
    private let a2: Double
    private var z1 = 0.0
    private var z2 = 0.0

    init(band: EQBand, rate: Double) {
        let frequency = min(rate * 0.45, max(20, band.frequency))
        let amplitude = pow(10, min(12, max(-12, band.gain)) / 40)
        let angle = 2 * Double.pi * frequency / rate
        let alpha = sin(angle) / (2 * max(0.3, band.q))
        let base = 1 + alpha / amplitude
        b0 = (1 + alpha * amplitude) / base
        b1 = -2 * cos(angle) / base
        b2 = (1 - alpha * amplitude) / base
        a1 = b1
        a2 = (1 - alpha / amplitude) / base
    }

    mutating func process(_ input: Double) -> Double {
        let output = b0 * input + z1
        z1 = b1 * input - a1 * output + z2
        z2 = b2 * input - a2 * output
        return output
    }

    func decibels(at frequency: Double, rate: Double) -> Double {
        let angle = 2 * Double.pi * frequency / rate
        let cosine = cos(angle)
        let sine = sin(angle)
        let c2 = cos(2 * angle)
        let s2 = sin(2 * angle)
        let numerator = hypot(b0 + b1 * cosine + b2 * c2, b1 * sine + b2 * s2)
        let denominator = hypot(1 + a1 * cosine + a2 * c2, a1 * sine + a2 * s2)
        return 20 * log10(max(1e-9, numerator) / max(1e-9, denominator))
    }
}
