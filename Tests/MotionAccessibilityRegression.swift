import SwiftUI

@main struct MotionAccessibilityRegression {
    static func main() {
        for system in [false, true] {
            for additional in [false, true] {
                let reduced = AccessibleMotion.reduced(system: system, additional: additional)
                if system { precondition(reduced, "App configuration must never negate the OS preference.") }
                var transaction = Transaction(animation: .linear(duration: 1))
                AccessibleMotion.apply(to: &transaction, reduced: reduced)
                if reduced { precondition(transaction.animation == nil && transaction.disablesAnimations) }
            }
        }
        for rms in [Double.nan, .infinity, -1, 0, 0.0001, 0.05, 1, 100] {
            let signal = SignalFrame(tones: [], level: 1, bands: [], inputRMS: rms, hasAudio: true)
            for beat in [Double.nan, -1, 0, 0.3, 1, 100] {
                let normal = VisualActivityPresentation(signal: signal, beat: beat, recentBeat: true, reduceMotion: false, visible: true)
                let reduced = VisualActivityPresentation(signal: signal, beat: beat, recentBeat: true, reduceMotion: true, visible: true)
                precondition(reduced.scale == 1 && reduced.opacity == 0.55 && !reduced.animates)
                precondition(reduced.level == normal.level && reduced.level.isFinite && (0...1).contains(reduced.level))
                precondition(reduced.accessibilityValue.contains("percent") && reduced.beatDetected)
                let hidden = VisualActivityPresentation(signal: signal, beat: beat, recentBeat: true, reduceMotion: true, visible: false)
                precondition(!hidden.animates && !hidden.beatDetected)
            }
        }
        let silence = VisualActivityPresentation(signal: .empty, beat: 0, recentBeat: false, reduceMotion: true, visible: true)
        precondition(silence.level == 0 && silence.accessibilityValue.contains("No audio") && !silence.beatDetected)
        print("Reduced Motion removes interpolation, scale and brightness pulses without losing level/text feedback; native OS reduction cannot be overridden off.")
    }
}
