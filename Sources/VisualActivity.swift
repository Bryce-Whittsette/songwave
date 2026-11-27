import Foundation

// A presentation policy, independent of rendering and the audio/motor clocks.
// Reduced Motion keeps meaningful text/level feedback without a display timer,
// pulse scaling, brightness pulses or interpolation between progress values.
struct VisualActivityPresentation {
    let level: Double
    let beatDetected: Bool
    let scale: Double
    let opacity: Double
    let animates: Bool
    let accessibilityValue: String

    init(signal: SignalFrame, beat: Double, recentBeat: Bool, reduceMotion: Bool, visible: Bool) {
        level = signal.inputRMS.isFinite && signal.inputRMS > 0 && signal.hasAudio ?
            min(1, max(0, 1 + 20 * log10(signal.inputRMS) / 60)) : 0
        let beat = visible && beat.isFinite ? min(1, max(0, beat)) : 0
        beatDetected = visible && (reduceMotion ? recentBeat : beat > 0)
        scale = reduceMotion ? 1 : 1 + beat * 0.25
        opacity = reduceMotion ? 0.55 : beat > 0 ? 0.9 : 0.22
        animates = visible && signal.hasAudio && !reduceMotion
        accessibilityValue = "\(signal.hasAudio ? "Audio detected" : "No audio"). Level \(Int(level * 100)) percent. \(beatDetected ? "Recent beat detected." : "No recent beat.")"
    }
}
