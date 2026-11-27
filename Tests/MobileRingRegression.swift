import AVFoundation
import Foundation

@main struct MobileRingRegression {
    static func main() {
        let format = AVAudioFormat(standardFormatWithSampleRate: 48000, channels: 2)!
        let buffer = AVAudioPCMBuffer(pcmFormat: format, frameCapacity: 40000)!
        buffer.frameLength = 40000
        for i in 0..<40000 { buffer.floatChannelData![0][i] = Float(i) / 40000; buffer.floatChannelData![1][i] = Float(i) / 40000 }
        let ring = MobileRing()
        ring.push(buffer)
        var output: [Float] = []
        ring.drain(maximum: 3840, into: &output)
        precondition(output.count == 3840 && output.first == Float(40000 - 3840) / 40000 && output.last == Float(39999) / 40000,
                     "The mobile audio queue must retain only recent bounded PCM.")
        ring.drain(maximum: 3840, into: &output)
        precondition(output.isEmpty)
        ring.enable(false); ring.push(buffer); ring.drain(maximum: 3840, into: &output)
        precondition(output.isEmpty, "Background/paused haptics must not accumulate audio.")
        ring.enable(true)
        buffer.frameLength = 8
        for i in 0..<8 { buffer.floatChannelData![0][i] = 1; buffer.floatChannelData![1][i] = -1 }
        ring.push(buffer); ring.drain(maximum: 10, into: &output)
        precondition(output == Array(repeating: 0.5, count: 8), "Antiphase stereo must not disappear.")
        buffer.floatChannelData![0][0] = .nan; buffer.floatChannelData![1][0] = .infinity
        ring.push(buffer); ring.drain(maximum: 10, into: &output)
        precondition(output.count == 8 && output.allSatisfy(\.isFinite))
        ring.push(buffer); ring.drain(maximum: -1, into: &output)
        precondition(output.isEmpty)
        for foreground in [false, true] {
            for playing in [false, true] {
                for supported in [false, true] {
                    for gain in [Double.nan, -Double.infinity, -1, 0, 0.4, 1] {
                        let expected = foreground && playing && supported && gain.isFinite && gain > 0
                        precondition(MobileAnalysisPolicy.shouldRun(foreground: foreground, playing: playing, gain: gain, supported: supported) == expected)
                    }
                }
            }
        }
        print("Mobile analysis sleeps while hidden, paused, unsupported or at zero intensity.")
        print("Mobile PCM stays bounded/recent, discards paused input, preserves antiphase stereo, and sanitizes nonfinite samples.")
    }
}
