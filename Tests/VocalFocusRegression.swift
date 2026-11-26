import Accelerate
import Foundation

final class VocalTransform {
    let size = 2048
    let fft = vDSP_create_fftsetup(11, FFTRadix(kFFTRadix2))!
    var samples = [Float](repeating: 0, count: 2048)
    var real = [Float](repeating: 0, count: 2048)
    var imaginary = [Float](repeating: 0, count: 2048)
    var cursor = 0
    deinit { vDSP_destroy_fftsetup(fft) }
    func append(_ value: Float) { samples[cursor] = value; cursor = (cursor + 1) % size }
    func magnitudes() -> [Float] {
        for i in 0..<size { real[i] = samples[(cursor+i)%size] * Float(0.5-0.5*cos(2 * .pi * Double(i)/Double(size-1))); imaginary[i] = 0 }
        real.withUnsafeMutableBufferPointer { re in imaginary.withUnsafeMutableBufferPointer { im in
            var split = DSPSplitComplex(realp: re.baseAddress!, imagp: im.baseAddress!)
            vDSP_fft_zip(fft, &split, 1, 11, FFTDirection(FFT_FORWARD))
        } }
        return (0..<1024).map { hypot(real[$0],imaginary[$0]) }
    }
}
@main struct VocalFocusRegression {
    static func main() {
        setbuf(stdout, nil)
        let tuning = OutputMode.trackpad.defaults
        var cases = 0
        for rate in [16000.0,24000,44100] {
            for voicePitch in [115.0,225,440,750] {
                let transform = VocalTransform()
                var tracker = VocalFocus()
                var total = 0, voiced = 0, pitchErrors = 0
                var random: UInt64 = 27
                var phase = 0.0
                for block in 0..<200 {
                    let blockSize = Int(rate*0.016)
                    for index in 0..<blockSize {
                        let t=Double(block*blockSize+index)/rate
                        let f0 = voicePitch * pow(2, 0.015 * sin(2 * .pi * 5 * t))
                        phase += 2 * .pi * f0/rate
                        var voice = 0.0
                        for harmonic in 1...12 {
                            let hz=f0*Double(harmonic)
                            let formant = 0.4 + exp(-pow((hz-900)/500,2)) + 0.6*exp(-pow((hz-2400)/500,2))
                            voice += 0.05 * formant / Double(harmonic) * sin(phase*Double(harmonic))
                        }
                        random=random &* 6364136223846793005 &+ 1
                        let noise=Double(random>>11)/9007199254740992-0.5
                        let drumAge=t.truncatingRemainder(dividingBy: 0.5)
                        let percussion=0.18*exp(-drumAge*60)*noise
                        let bass=0.22*sin(2 * .pi * 68 * t)
                        transform.append(Float(voice+bass+percussion))
                    }
                    let result=tracker.frame(magnitudes: transform.magnitudes(),binWidth:rate/2048,analysisSize:2048,at:Double(block+1)*0.016,tuning:tuning)
                    if block>10 {
                        total += 1
                        if let pitch=result.fundamental, result.level>0.05 {
                            voiced += 1
                            if abs(log2(pitch/voicePitch))>0.10 {pitchErrors+=1}
                        }
                    }
                }
                // The harmonic voice should remain trackable over louder bass and percussion.
                precondition(voiced > total*7/10 && pitchErrors < total/10)
                cases += 1
            }
            for kind in 0..<3 {
                let transform = VocalTransform()
                var tracker = VocalFocus()
                var random: UInt64=47
                var events=0
                for block in 0..<200 {
                    let blockSize=Int(rate*0.016)
                    for index in 0..<blockSize {
                        let t=Double(block*blockSize+index)/rate
                        random=random &* 6364136223846793005 &+ 1
                        let noise=Double(random>>11)/9007199254740992-0.5
                        let age=t.truncatingRemainder(dividingBy:0.5)
                        let sample:Double
                        switch kind {
                        case 0: sample=0.3*sin(2 * .pi * 68 * t)+0.2*exp(-age*45)*sin(2 * .pi * 90 * age)
                        case 1: sample=0.2*exp(-age*60)*noise
                        default: sample=noise*0.06
                        }
                        transform.append(Float(sample))
                    }
                    let result=tracker.frame(magnitudes:transform.magnitudes(),binWidth:rate/2048,analysisSize:2048,at:Double(block+1)*0.016,tuning:tuning)
                    if result.level>0.05 {events+=1}
                }
                // Unpitched noise, percussion and sub-vocal bass should stay quiet.
                precondition(events==0)
                cases += 1
            }
        }
        print("\(cases) vocal-focused mixed-PCM cases passed")
    }
}
