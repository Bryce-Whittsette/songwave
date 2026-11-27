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
        for rms in [Double.nan, .infinity, -.infinity, -1, 0, .leastNonzeroMagnitude, 0.0001, 0.05, 1, 100, .greatestFiniteMagnitude] {
            let signal = SignalFrame(tones: [], level: 1, bands: [], inputRMS: rms, hasAudio: true)
            for beat in [Double.nan, -1, 0, 0.3, 1, 100] {
                let normal = VisualActivityPresentation(signal: signal, beat: beat, recentBeat: true, reduceMotion: false, visible: true)
                let reduced = VisualActivityPresentation(signal: signal, beat: beat, recentBeat: true, reduceMotion: true, visible: true)
                precondition(reduced.scale == 1 && reduced.opacity == 0.55 && !reduced.animates)
                precondition(reduced.level == normal.level && reduced.level.isFinite && (0...1).contains(reduced.level))
                precondition(reduced.accessibilityValue.contains("percent") && reduced.beatDetected)
                precondition(normal.opacity >= 0.28 && normal.opacity <= 0.620001 && normal.scale == 1)
                precondition(reduced.rhythmText == "Following music" && !reduced.decibelText.contains("nan"))
                let hidden = VisualActivityPresentation(signal: signal, beat: beat, recentBeat: true, reduceMotion: true, visible: false)
                precondition(!hidden.animates && !hidden.beatDetected)
            }
        }
        let silence = VisualActivityPresentation(signal: .empty, beat: 0, recentBeat: false, reduceMotion: true, visible: true)
        precondition(silence.level == 0 && silence.accessibilityValue.contains("No audio") && !silence.beatDetected)
        precondition(silence.rhythmText == "Waiting for music" && silence.decibelText == "— dB")
        let music = SignalFrame(tones: [], level: 0.4, bands: [], inputRMS: 0.05, hasAudio: true)
        let between = VisualActivityPresentation(signal: music, beat: 0, recentBeat: false, reduceMotion: false, visible: true)
        let attack = VisualActivityPresentation(signal: music, beat: 0.8, recentBeat: true, reduceMotion: false, visible: true)
        precondition(between.rhythmText == "Following music" && attack.rhythmText == between.rhythmText)
        precondition(between.level == attack.level && between.decibelText == "-26 dB", "A beat must not change the music-level reading.")
        precondition(between.listeningAccessibilityValue.contains("-26 dB"), "The retained dB reading must also be accessible.")
        precondition(attack.opacity > between.opacity && attack.scale == between.scale)
        let stale = VisualActivityPresentation(signal: .empty, beat: 1, recentBeat: true, reduceMotion: false, visible: true)
        precondition(!stale.beatDetected && stale.scale == 1 && stale.level == 0, "Stopped audio cannot leave a false visual beat.")
        print("Reduced Motion removes interpolation, scale and brightness pulses without losing level/text feedback; native OS reduction cannot be overridden off.")
    }
}
