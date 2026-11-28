import AudioToolbox
import Foundation

struct GlassError: LocalizedError { let errorDescription: String?; init(_ text: String) { errorDescription = text } }

@main struct CaptureRegression {
    static func push(_ samples: [Float], into ring: SampleRing) {
        samples.withUnsafeBufferPointer { source in
            var list = AudioBufferList(mNumberBuffers: 1, mBuffers: AudioBuffer(
                mNumberChannels: 1, mDataByteSize: UInt32(samples.count * MemoryLayout<Float>.stride),
                mData: UnsafeMutableRawPointer(mutating: source.baseAddress)))
            withUnsafePointer(to: &list) { ring.push($0) }
        }
    }
    static func malformedPackets() {
        let ring = SampleRing()
        var output: [Float] = []
        push([.nan, .infinity, -.infinity, .greatestFiniteMagnitude, -.greatestFiniteMagnitude, 0.25, -0.25], into: ring)
        ring.takeNewest(maximum: 32, into: &output)
        guard output.count == 7 && output.prefix(5).allSatisfy({ $0 == 0 }) && Array(output.suffix(2)) == [0.25, -0.25] else {
            fputs("FAIL: corrupt PCM values passed the capture boundary instead of becoming silence.\n", stderr); exit(1)
        }
        let left: [Float] = [0.2, 0.6, 0.3, -0.3]
        let right: [Float] = [0.6, 0.2, 0.1, 0.1]
        left.withUnsafeBufferPointer { a in right.withUnsafeBufferPointer { b in
            let list = AudioBufferList.allocate(maximumBuffers: 3)
            defer { list.unsafeMutablePointer.deallocate() }
            let first = AudioBuffer(mNumberChannels: 1, mDataByteSize: 16, mData: UnsafeMutableRawPointer(mutating: a.baseAddress))
            let second = AudioBuffer(mNumberChannels: 1, mDataByteSize: 16, mData: UnsafeMutableRawPointer(mutating: b.baseAddress))
            func rejected(_ buffers: UInt32, _ x: AudioBuffer, _ y: AudioBuffer = AudioBuffer()) {
                list.unsafeMutablePointer.pointee.mNumberBuffers = 3
                list[0] = x; list[1] = y; list[2] = AudioBuffer()
                list.unsafeMutablePointer.pointee.mNumberBuffers = buffers
                ring.push(UnsafePointer(list.unsafeMutablePointer))
                ring.takeNewest(maximum: 32, into: &output)
                precondition(output.isEmpty, "A malformed capture layout was accepted")
            }
            rejected(0, first)
            rejected(3, first, second)
            rejected(UInt32.max, first, second)
            var invalid = first; invalid.mNumberChannels = 0; rejected(1, invalid)
            invalid.mNumberChannels = UInt32.max; rejected(1, invalid)
            invalid = first; invalid.mData = nil; rejected(1, invalid)
            invalid = first; invalid.mDataByteSize = 15; rejected(1, invalid)
            invalid.mDataByteSize = UInt32.max - 3; rejected(1, invalid)
            invalid = first; invalid.mData = invalid.mData!.advanced(by: 1); invalid.mDataByteSize = 12; rejected(1, invalid)
            rejected(2, first) // missing second plane must not silently become mono
            invalid = second; invalid.mDataByteSize = 4; rejected(2, first, invalid)
            invalid = second; invalid.mNumberChannels = 2; rejected(2, first, invalid)
            list.unsafeMutablePointer.pointee.mNumberBuffers = 2
            list[0] = first; list[1] = second
            ring.push(UnsafePointer(list.unsafeMutablePointer)); ring.takeNewest(maximum: 32, into: &output)
            precondition(output.count == left.count && zip(output, zip(left, right).map(fold)).allSatisfy { abs($0 - $1) < 0.00001 })
            list.unsafeMutablePointer.pointee.mNumberBuffers = 1
            list[0] = AudioBuffer(mNumberChannels: 2, mDataByteSize: 16, mData: first.mData)
            ring.push(UnsafePointer(list.unsafeMutablePointer)); ring.takeNewest(maximum: 32, into: &output)
            precondition(output.count == 2 && abs(output[0] - 0.4) < 0.00001 && abs(output[1] - 0.15) < 0.00001)
        }}
        var now = ContinuousClock.now
        let empty = SampleRing(clock: { now })
        push([0.1], into: empty); now = now.advanced(by: .milliseconds(150))
        push([], into: empty); now = now.advanced(by: .milliseconds(100))
        empty.takeNewest(maximum: 32, into: &output)
        precondition(output.isEmpty, "A zero-length callback refreshed stale PCM")
        push([-2, 2], into: empty); empty.takeNewest(maximum: .max, into: &output)
        precondition(output == [-2, 2], "Valid PCM headroom must stay unchanged")
        print("Empty/missing/misaligned/oversized/truncated PCM layouts are rejected; valid mono, interleaved and planar stereo remain intact; corrupt sample values become silence.")
    }
    static func main() {
        malformedPackets()
        let ring = SampleRing()
        var output: [Float] = []
        push([0.1, 0.2, 0.3], into: ring)
        Thread.sleep(forTimeInterval: 0.3)
        ring.takeNewest(maximum: 128, into: &output)
        guard output.isEmpty else {
            fputs("FAIL: a stalled capture replayed old PCM as fresh audio after 300 ms.\n", stderr); exit(1)
        }
        push([0.4, 0.5], into: ring)
        ring.takeNewest(maximum: 128, into: &output)
        precondition(output == [0.4, 0.5], "Fresh audio must resume immediately")
        push((0..<50000).map { Float($0 % 1000) / 1000 }, into: ring)
        ring.takeNewest(maximum: 7, into: &output)
        precondition(output == (49993..<50000).map { Float($0 % 1000) / 1000 }, "Only the newest bounded samples should remain")
        ring.takeNewest(maximum: 7, into: &output)
        precondition(output.isEmpty)
        var now = ContinuousClock.now
        let timed = SampleRing(clock: { now })
        for seconds in [0.201, 60.0, 10800.0, 86400.0] {
            push([0.8, -0.8], into: timed)
            now = now.advanced(by: .seconds(seconds))
            timed.takeNewest(maximum: 128, into: &output)
            precondition(output.isEmpty, "Old PCM survived an idle/sleep interval")
            push([0.2], into: timed)
            timed.takeNewest(maximum: 128, into: &output)
            precondition(output == [0.2], "Fresh input did not resume after a long idle")
        }
        push([0.5], into: timed)
        now = now.advanced(by: .seconds(-1))
        timed.takeNewest(maximum: 128, into: &output)
        precondition(output.isEmpty, "A backwards test clock admitted stale input")
        let concurrent = SampleRing()
        let group = DispatchGroup()
        group.enter()
        DispatchQueue.global().async {
            for index in 0..<10000 { push([Float](repeating: Float(index % 100) / 100, count: 192), into: concurrent) }
            group.leave()
        }
        for _ in 0..<10000 {
            concurrent.takeNewest(maximum: 1920, into: &output)
            precondition(output.count <= 1920 && output.allSatisfy(\.isFinite))
        }
        group.wait()
        print("Real capture ring discards stale PCM, resumes fresh input and stays bounded under overflow.")
        print("Continuous-clock idle jumps through 24 hours and 1.92 million concurrently offered samples passed; simulated clock jumps are not physical sleep tests.")
    }
}
