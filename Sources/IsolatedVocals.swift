import Foundation

// Spleeter's neural vocal mask runs off the playback queue. Only the isolated
// vocal PCM reaches the haptic analyzer. The Light path never loads this model.
final class IsolatedVocals {
    static let outputRate = 24_000.0
    static let buffering = 0.75
    private let modelRate = 44_100.0
    private let hop = 22_050
    private let lookahead = 11_025
    private let context = 44_100
    private let blend = 512
    private let queue = DispatchQueue(label: "songwave.vocal-isolation", qos: .userInitiated)
    private let lock = NSLock()
    private var input: [Float] = []
    private var history = [Float](repeating: 0, count: 44_100)
    private var output: [Float] = []
    private var outputIndex = 0
    private var priorBlend: [Float] = []
    private var sourceRate = 0.0
    private var inputResampler = VocalResampler(from: 44_100, to: 44_100)
    private var outputResampler = VocalResampler(from: 44_100, to: 24_000)
    private var resamplerGeneration = -1
    private var generation = 0
    private var busy = false
    private var loaded = false
    private var finishing = false
    private var cancelled = false
    private var lastPush: Double?
    private var lastRead: Double?
    private var inferenceSeconds = 0.0
    private var text = "Loading vocal isolation…"
    private var problem: String?
    // This property is used only on the worker queue.
    private var separator: SpleeterSeparator?

    init(modelURL: URL? = nil) {
        let url = modelURL ?? Bundle.main.url(forResource: "Spleeter2Model", withExtension: "mlmodelc", subdirectory: "Vocals")
        queue.async { [self] in
            do {
                guard let url else { throw GlassError("The bundled vocal model is missing.") }
                let inference = try CoreMLMaskInference(contentsOf: url, stems: .two)
                let model = SpleeterSeparator(stems: .two, inference: inference,
                    configuration: SpleeterConfiguration(framesPerWindow: inference.modelFrames ?? 216),
                    fft: try AccelerateRealFFT(size: 4096))
                lock.lock()
                guard !cancelled else { lock.unlock(); return }
                separator = model
                loaded = true
                text = "Buffering isolated vocals…"
                lock.unlock()
                schedule()
            } catch { fail(error) }
        }
    }

    var status: String { locked { text } }
    var failure: String? { locked { problem } }
    var isReady: Bool { locked { loaded && !cancelled && problem == nil } }
    var hasPendingAudio: Bool { locked { !cancelled && (busy || !input.isEmpty || outputIndex < output.count) } }
    var latency: Double {
        locked {
            let pending = Double(input.count) / modelRate + Double(output.count - outputIndex) / Self.outputRate
            return max(Self.buffering + inferenceSeconds, pending + (busy ? Double(hop) / modelRate : 0))
        }
    }
    var isDrained: Bool {
        locked { cancelled || problem != nil || (loaded && finishing && !busy && input.isEmpty && outputIndex >= output.count) }
    }

    func push(_ samples: [Float], rate: Double, at now: Double) {
        guard !samples.isEmpty, rate.isFinite, (8_000...192_000).contains(rate) else { return }
        lock.lock()
        guard !cancelled, !finishing, problem == nil else { lock.unlock(); return }
        if rate != sourceRate || lastPush.map({ now - $0 > 0.5 }) == true {
            resetLocked()
            sourceRate = rate
            inputResampler = VocalResampler(from: rate, to: modelRate)
        }
        lastPush = now
        input.append(contentsOf: inputResampler.convert(samples))
        // A cold model or a slow machine cannot accumulate a song in memory.
        // Keep a bounded cold-load reserve, then resume from recent audio if
        // inference falls behind for longer than that reserve.
        let maximum = hop * 4 + lookahead
        if input.count > maximum {
            input.removeFirst(input.count - maximum)
            history = [Float](repeating: 0, count: context)
            priorBlend.removeAll(keepingCapacity: true)
            generation += 1
            output.removeAll(keepingCapacity: true)
            outputIndex = 0
        }
        lock.unlock()
        schedule()
    }

    func read(maximum: Int, at now: Double) -> [Float] {
        lock.lock()
        defer { lock.unlock() }
        guard !cancelled, problem == nil, maximum > 0 else { return [] }
        // A paused consumer must not play stale vocals when it comes back.
        if lastRead.map({ now - $0 > 0.25 }) == true {
            output.removeAll(keepingCapacity: true)
            outputIndex = 0
        }
        lastRead = now
        let count = min(maximum, output.count - outputIndex)
        guard count > 0 else { return [] }
        let samples = Array(output[outputIndex..<(outputIndex + count)])
        outputIndex += count
        if outputIndex == output.count {
            output.removeAll(keepingCapacity: true)
            outputIndex = 0
        } else if outputIndex > 24_000 {
            output.removeFirst(outputIndex)
            outputIndex = 0
        }
        return samples
    }

    // End-of-file is explicit. Pad only the final model call, then let the
    // caller drain its remaining vocal PCM at the normal playback rate.
    func finish() {
        lock.lock()
        if !cancelled { finishing = true }
        lock.unlock()
        schedule()
    }

    func reset() {
        lock.lock()
        guard !cancelled else { lock.unlock(); return }
        resetLocked()
        lock.unlock()
    }

    func cancel() {
        lock.lock()
        cancelled = true
        resetLocked()
        text = "Vocal isolation stopped"
        lock.unlock()
        queue.async { [self] in separator = nil }
    }

    private func resetLocked() {
        generation += 1
        input.removeAll(keepingCapacity: true)
        output.removeAll(keepingCapacity: true)
        outputIndex = 0
        priorBlend.removeAll(keepingCapacity: true)
        history = [Float](repeating: 0, count: context)
        sourceRate = 0
        lastPush = nil
        lastRead = nil
        finishing = false
        text = loaded ? "Buffering isolated vocals…" : "Loading vocal isolation…"
    }

    private func schedule() {
        lock.lock()
        guard loaded, !busy, !cancelled, problem == nil,
              input.count >= hop + lookahead || (finishing && !input.isEmpty) else { lock.unlock(); return }
        busy = true
        let id = generation
        let count = min(hop, input.count)
        let available = min(input.count, count + lookahead)
        let window = history + input.prefix(available)
        let previous = priorBlend
        history = Array((history + input.prefix(count)).suffix(context))
        input.removeFirst(count)
        lock.unlock()
        queue.async { [self] in
            do {
                guard let separator else { throw GlassError("The vocal model is unavailable.") }
                let start = ProcessInfo.processInfo.systemUptime
                let separated = try separator.separate([window])[0][0]
                let elapsed = ProcessInfo.processInfo.systemUptime - start
                var vocal = Array(separated[context..<(context + count)])
                let fadeCount = min(blend, min(previous.count, vocal.count))
                if fadeCount > 1 {
                    for i in 0..<fadeCount {
                        let mix = Float(0.5 - 0.5 * cos(.pi * Double(i) / Double(fadeCount - 1)))
                        vocal[i] = previous[i] * (1 - mix) + vocal[i] * mix
                    }
                }
                let extraEnd = min(separated.count, context + count + blend)
                let extra = Array(separated[(context + count)..<extraEnd])
                lock.lock()
                guard !cancelled, id == generation else {
                    busy = false
                    lock.unlock()
                    schedule()
                    return
                }
                if resamplerGeneration != id {
                    outputResampler = VocalResampler(from: modelRate, to: Self.outputRate)
                    resamplerGeneration = id
                }
                let converted = outputResampler.convert(vocal)
                priorBlend = extra
                inferenceSeconds = elapsed
                if outputIndex > 0 {
                    output.removeFirst(outputIndex)
                    outputIndex = 0
                }
                output.append(contentsOf: converted)
                if output.count > 60_000 {
                    output.removeFirst(output.count - 60_000)
                    text = "Isolated vocals · catching up"
                } else { text = "Isolated vocals" }
                busy = false
                lock.unlock()
                schedule()
            } catch { fail(error) }
        }
    }

    private func fail(_ error: Error) {
        lock.lock()
        if !cancelled {
            problem = "Vocal isolation could not run. " + error.localizedDescription
            text = "Vocal isolation unavailable"
            input.removeAll()
            output.removeAll()
            outputIndex = 0
        }
        busy = false
        lock.unlock()
    }

    private func locked<T>(_ body: () -> T) -> T {
        lock.lock()
        defer { lock.unlock() }
        return body()
    }
}

// A bounded streaming sample-rate adapter. Fractional position is retained across
// blocks, so capture block size cannot change pitch or slowly drift timing.
private struct VocalResampler {
    private let step: Double
    private var position = 0.0
    private var previous: Float?

    init(from: Double, to: Double) { step = from / to }

    mutating func convert(_ input: [Float]) -> [Float] {
        guard !input.isEmpty else { return [] }
        if step == 1 { return input.map { $0.isFinite ? $0 : 0 } }
        let source = previous.map { [$0] + input } ?? input
        var result: [Float] = []
        result.reserveCapacity(Int(Double(input.count) / step) + 2)
        while position < Double(source.count - 1) {
            let index = Int(position)
            let fraction = Float(position - Double(index))
            let value = source[index] + (source[index + 1] - source[index]) * fraction
            result.append(value.isFinite ? value : 0)
            position += step
        }
        position -= Double(source.count - 1)
        previous = source.last
        return result
    }
}
