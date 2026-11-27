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
    let rhythmText: String
    let decibelText: String
    var listeningAccessibilityValue: String {
        accessibilityValue + (decibelText == "— dB" ? "" : " Signal level \(decibelText).")
    }

    init(signal: SignalFrame, beat: Double, recentBeat: Bool, reduceMotion: Bool, visible: Bool) {
        let decibels = signal.inputRMS.isFinite && signal.inputRMS > 0 && signal.hasAudio ?
            20 * log10(signal.inputRMS) : nil
        level = decibels.map { min(1, max(0, 1 + $0 / 60)) } ?? 0
        let beat = visible && signal.hasAudio && beat.isFinite ? min(1, max(0, beat)) : 0
        beatDetected = visible && signal.hasAudio && (reduceMotion ? recentBeat : beat > 0)
        scale = reduceMotion ? 1 : 1 + beat * 0.25
        opacity = reduceMotion ? 0.55 : 0.22 + beat * 0.68
        animates = visible && signal.hasAudio && !reduceMotion
        accessibilityValue = "\(signal.hasAudio ? "Audio detected" : "No audio"). Level \(Int(level * 100)) percent. \(beatDetected ? "Recent beat detected." : "No recent beat.")"
        rhythmText = !signal.hasAudio ? "No signal" : beatDetected ? "Detected" : "Between beats"
        decibelText = decibels.map { "\(Int($0.rounded())) dB" } ?? "— dB"
    }
}
