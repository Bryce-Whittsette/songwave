import AVFoundation
import Foundation

// Copy PCM in the render callback; analysis and haptics run on their own queue.
final class MobileRing {
    private let lock = NSLock()
    private var data = [Float](repeating: 0, count: 32768)
    private var index = 0
    private var count = 0
    private var enabled = true
    func enable(_ value: Bool) { lock.lock(); enabled = value; count = 0; lock.unlock() }
    func push(_ buffer: AVAudioPCMBuffer) {
        guard let channels = buffer.floatChannelData, lock.try() else { return }
        defer { lock.unlock() }
        guard enabled else { return }
        for i in 0..<Int(buffer.frameLength) {
            let left = channels[0][i]
            let right = buffer.format.channelCount > 1 ? channels[1][i] : left
            let mid = (left + right) * 0.5
            let sample = abs(mid) < abs(left) * 0.2 ? left * 0.5 : mid
            data[index] = sample.isFinite ? sample : 0
            index = (index + 1) % data.count
            count = min(count + 1, data.count)
        }
    }
    func drain(maximum: Int, into result: inout [Float]) {
        lock.lock(); defer { lock.unlock() }
        result.removeAll(keepingCapacity: true)
        let n = min(count, max(0, maximum)), start = (index - n + data.count) % data.count
        for i in 0..<n { result.append(data[(start + i) % data.count]) }
        count = 0
    }
}


// Pure policy shared by the engine and resource-regression tests.
enum MobileAnalysisPolicy {
    static func shouldRun(foreground: Bool, playing: Bool, gain: Double, supported: Bool) -> Bool {
        foreground && playing && supported && gain.isFinite && gain > 0
    }
}
