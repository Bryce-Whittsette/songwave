import CoreHaptics
import Foundation

// Core Haptics controls intensity and texture, not a speaker's pitch waveform.
// This is a foreground-only, bounded rendering of the shared musical analysis.
final class MobileHaptics {
    let supported = CHHapticEngine.capabilitiesForHardware().supportsHaptics
    private var engine: CHHapticEngine?
    private var sustained: CHHapticAdvancedPatternPlayer?
    private let resetLock = NSLock()
    private var generation = UUID()
    private var needsReset = false
    private var running = false
    private var activeGain = -1.0
    private var lastLevel = -1.0
    private var lastSharpness = -1.0

    func render(_ frame: SignalFrame, focus: HapticFocus, gain: Double) throws {
        guard supported else { return }
        let gain = min(1, max(0, gain.isFinite ? gain : 0))
        guard gain > 0 else { stop(); return }
        if gain != activeGain { stop(); activeGain = gain }
        if engine == nil {
            let next = try CHHapticEngine()
            next.isAutoShutdownEnabled = true
            next.playsHapticsOnly = true
            let token = UUID()
            resetLock.lock(); generation = token; needsReset = false; resetLock.unlock()
            next.resetHandler = { [weak self] in self?.markReset(token) }
            next.stoppedHandler = { [weak self] _ in self?.markReset(token) }
            engine = next
        }
        guard let engine else { return }
        resetLock.lock(); let reset = needsReset; needsReset = false; resetLock.unlock()
        if reset { sustained = nil; running = false; lastLevel = -1; lastSharpness = -1 }
        let budget = MobileHapticBudget(rhythm: focus.includesBeat, mixed: focus == .both, gain: gain)
        let sustainedLevel = focus == .beat ? frame.bassLevel : focus == .both ? 0.55 * frame.level + 0.45 * frame.bassLevel : frame.level
        let level = min(budget.continuous, max(0, sustainedLevel * gain))
        if !running && (level > 0.005 || (focus.includesBeat && frame.beatStrength > 0)) { try engine.start(); running = true }
        if focus.includesBeat && frame.beatStrength > 0 {
            let sharpness = min(1, max(0.15, (frame.beatFrequency - 100) / 300))
            let event = CHHapticEvent(eventType: .hapticTransient, parameters: [
                .init(parameterID: .hapticIntensity, value: Float(min(budget.transient, frame.beatStrength * gain))),
                .init(parameterID: .hapticSharpness, value: Float(sharpness))], relativeTime: 0)
            let player = try engine.makePlayer(with: CHHapticPattern(events: [event], parameters: []))
            try player.start(atTime: CHHapticTimeImmediate)
        }
        if level <= 0.005 {
            if let sustained { try? sustained.stop(atTime: CHHapticTimeImmediate) }
            sustained = nil
            lastLevel = -1
            return
        }
        let frequency = frame.tones.max { $0.weight < $1.weight }?.hertz ?? 125
        let sharpness = focus == .beat ? 0.12 : min(1, max(0, log2(max(100, frequency) / 100) / 4))
        // The static event is bounded by the user's gain even before controls apply.
        let ceiling = budget.continuous
        let control = Float(min(1, level / ceiling))
        if sustained == nil {
            let event = CHHapticEvent(eventType: .hapticContinuous, parameters: [
                .init(parameterID: .hapticIntensity, value: Float(ceiling)),
                .init(parameterID: .hapticSharpness, value: 0)], relativeTime: 0, duration: 1)
            let player = try engine.makeAdvancedPlayer(with: CHHapticPattern(events: [event], parameters: []))
            player.loopEnabled = true
            // Set controls before the first actuation, rather than starting at full gain.
            try player.sendParameters([
                .init(parameterID: .hapticIntensityControl, value: control, relativeTime: 0),
                .init(parameterID: .hapticSharpnessControl, value: Float(sharpness), relativeTime: 0)], atTime: CHHapticTimeImmediate)
            try player.start(atTime: CHHapticTimeImmediate)
            sustained = player
            lastLevel = level; lastSharpness = sharpness
        }
        guard abs(lastLevel - level) > 0.01 || abs(lastSharpness - sharpness) > 0.03 else { return }
        try sustained?.sendParameters([
            .init(parameterID: .hapticIntensityControl, value: control, relativeTime: 0),
            .init(parameterID: .hapticSharpnessControl, value: Float(sharpness), relativeTime: 0)], atTime: CHHapticTimeImmediate)
        lastLevel = level; lastSharpness = sharpness
    }

    private func markReset(_ token: UUID) {
        resetLock.lock(); defer { resetLock.unlock() }
        if generation == token { needsReset = true }
    }

    func stop() {
        resetLock.lock(); generation = UUID(); needsReset = false; resetLock.unlock()
        running = false
        try? sustained?.stop(atTime: CHHapticTimeImmediate)
        sustained = nil
        engine?.stop(completionHandler: nil)
        engine = nil
        lastLevel = -1; lastSharpness = -1; activeGain = -1
    }
}
