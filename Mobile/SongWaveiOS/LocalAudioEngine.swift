import AVFoundation
import Foundation

struct GlassError: LocalizedError {
    let errorDescription: String?
    init(_ message: String) { errorDescription = message }
}


final class LocalAudioEngine {
    private let engine = AVAudioEngine()
    private let node = AVAudioPlayerNode()
    private let ring = MobileRing()
    private let queue = DispatchQueue(label: "songwave.mobile.analysis", qos: .userInitiated)
    private let haptics = MobileHaptics()
    private var timer: DispatchSourceTimer?
    private var spectrum: Spectrum?
    private var samples: [Float] = []
    private var tuning = OutputMode.assist.defaults
    private var focus = HapticFocus.beat
    private var gain = 0.4
    private var foreground = true
    // These values belong exclusively to the analysis queue.
    private var analysisForeground = true
    private var analysisPlaying = false
    private var scheduled = false
    private var hasTap = false
    private var analysisRate = 0.0
    private var generation = UUID()
    private var analysisGeneration = UUID()
    private var file: AVAudioFile?
    var onFinish: (() -> Void)?
    var onHapticError: ((String) -> Void)?
    var supportsHaptics: Bool { haptics.supported }
    var duration: Double { file.map { Double($0.length) / $0.processingFormat.sampleRate } ?? 0 }
    var position: Double {
        guard let time = node.lastRenderTime, let playerTime = node.playerTime(forNodeTime: time) else { return 0 }
        return min(duration, Double(playerTime.sampleTime) / playerTime.sampleRate)
    }

    init() { engine.attach(node) }

    func load(_ url: URL) throws {
        stop()
        let next = try AVAudioFile(forReading: url, commonFormat: .pcmFormatFloat32, interleaved: false)
        guard next.length > 0, next.processingFormat.sampleRate.isFinite, (8000...192000).contains(next.processingFormat.sampleRate), (1...2).contains(next.processingFormat.channelCount) else { throw GlassError("The audio file is empty.") }
        file = next
        engine.connect(node, to: engine.mainMixerNode, format: next.processingFormat)
        node.installTap(onBus: 0, bufferSize: 1024, format: next.processingFormat) { [ring] buffer, _ in ring.push(buffer) }
        hasTap = true
        let rate = next.processingFormat.sampleRate
        let token = generation
        queue.sync { analysisGeneration = token; analysisRate = rate; spectrum = try? Spectrum(sampleRate: rate) }
        guard spectrum != nil else { throw GlassError("This audio format could not be analyzed.") }
    }

    func configure(focus: HapticFocus, intensity: Double, audible: Bool) {
        engine.mainMixerNode.outputVolume = audible ? 1 : 0
        queue.async { [self] in
            if self.focus != focus { spectrum = analysisRate > 0 ? try? Spectrum(sampleRate: analysisRate) : nil; haptics.stop() }
            self.focus = focus
            let nextGain = intensity.isFinite ? min(1, max(0, intensity)) : 0
            if gain != nextGain { haptics.stop() }
            gain = nextGain
            reconcileAnalysis()
        }
    }

    func play() throws {
        guard let file else { throw GlassError("Choose an audio file first.") }
        if !scheduled {
            file.framePosition = 0
            queue.sync { spectrum = try? Spectrum(sampleRate: analysisRate); haptics.stop() }
            let token = generation
            node.scheduleFile(file, at: nil, completionCallbackType: .dataPlayedBack) { [weak self] _ in
                DispatchQueue.main.async {
                    guard let self, self.generation == token else { return }
                    self.scheduled = false; self.node.stop(); self.onFinish?()
                }
            }
            scheduled = true
        }
        if !engine.isRunning { engine.prepare(); try engine.start() }
        node.play()
        setForeground(foreground)
    }

    func setForeground(_ value: Bool) {
        foreground = value
        let playing = node.isPlaying
        queue.async { [self] in
            analysisForeground = value
            analysisPlaying = playing
            reconcileAnalysis()
        }
    }

    private func reconcileAnalysis() {
        let active = MobileAnalysisPolicy.shouldRun(foreground: analysisForeground,
            playing: analysisPlaying, gain: gain, supported: haptics.supported)
        guard active else {
            ring.enable(false)
            timer?.cancel(); timer = nil
            haptics.stop()
            return
        }
        guard timer == nil else { return }
        spectrum = analysisRate > 0 ? try? Spectrum(sampleRate: analysisRate) : nil
        ring.enable(true)
        let timer = DispatchSource.makeTimerSource(queue: queue)
        timer.schedule(deadline: .now(), repeating: .milliseconds(16), leeway: .milliseconds(2))
        timer.setEventHandler { [weak self] in self?.analyze() }
        self.timer = timer
        timer.resume()
    }

    private func analyze() {
        ring.drain(maximum: max(1, Int(analysisRate * 0.08)), into: &samples)
        guard !samples.isEmpty else { return }
        for sample in samples { spectrum?.append(sample) }
        let frame = spectrum?.frame(tuning: tuning, mode: focus.analysisMode) ?? .empty
        do { try haptics.render(frame, focus: focus, gain: gain) }
        catch {
            haptics.stop()
            ring.enable(false)
            timer?.cancel(); timer = nil
            let message = error.localizedDescription
            let token = analysisGeneration
            DispatchQueue.main.async { [weak self] in
                guard let self, self.generation == token else { return }
                self.onHapticError?(message)
            }
        }
    }

    func pause() {
        node.pause(); engine.pause(); ring.enable(false)
        queue.async { [self] in analysisPlaying = false; timer?.cancel(); timer = nil; haptics.stop(); spectrum = analysisRate > 0 ? try? Spectrum(sampleRate: analysisRate) : nil }
    }
    func stop() {
        generation = UUID()
        node.stop()
        if hasTap { node.removeTap(onBus: 0); hasTap = false }
        engine.stop(); scheduled = false
        ring.enable(false)
        queue.sync { analysisPlaying = false; timer?.cancel(); timer = nil; haptics.stop(); spectrum = nil }
        file = nil
    }
    deinit { stop() }
}
