// Actual Core ML integration test. This does not touch audio capture, speakers, or haptic hardware.
import Foundation
import AVFoundation

struct GlassError: LocalizedError { let errorDescription:String?; init(_ s:String){errorDescription=s} }
@main struct VocalIsolationRegression {
 static func main() async throws {
  setbuf(stdout,nil)
  precondition(CommandLine.arguments.count == 3, "Supply the bundled model path and a spoken-voice audio fixture.")
  let path=URL(fileURLWithPath:CommandLine.arguments[1])
  let engine=IsolatedVocals(modelURL:path)
  let limit=ProcessInfo.processInfo.systemUptime+8
  while !engine.isReady && engine.failure == nil && ProcessInfo.processInfo.systemUptime<limit {
   try await Task.sleep(for:.milliseconds(10))
  }
  precondition(engine.isReady,engine.failure ?? "Model timed out")
  let voiceFile=try AVAudioFile(forReading:URL(fileURLWithPath:CommandLine.arguments[2]),commonFormat:.pcmFormatFloat32,interleaved:false)
  let voiceBuffer=AVAudioPCMBuffer(pcmFormat:voiceFile.processingFormat,frameCapacity:AVAudioFrameCount(voiceFile.length))!
  try voiceFile.read(into:voiceBuffer)
  let voiceRate=voiceFile.processingFormat.sampleRate
  let voiceValues=voiceBuffer.floatChannelData![0]
  func voice(_ t:Double)->Float {
   let p=t*voiceRate,a=Int(p),f=Float(p-Double(a))
   guard a+1<Int(voiceBuffer.frameLength) else {return 0}
   return (voiceValues[a]+(voiceValues[a+1]-voiceValues[a])*f)*0.7
  }
  let rate=48_000.0, size=960, blocks=100
  var truth:[Float]=[],mixture:[Float]=[]
  var received:[Float]=[]
  let start=ProcessInfo.processInfo.systemUptime
  for block in 0..<blocks {
   var samples=[Float](repeating:0,count:size)
   for offset in samples.indices {
    let t=Double(block*size+offset)/rate
    let backing=Float(0.12*sin(2 * .pi * 80 * t)+0.11*sin(2 * .pi * 330 * t)+0.06*sin(2 * .pi * 660 * t))
    samples[offset]=voice(t)+backing
    if offset % 2 == 0 { truth.append(voice(t));mixture.append(samples[offset]) }
   }
   let now=ProcessInfo.processInfo.systemUptime
   engine.push(samples,rate:rate,at:now)
   received += engine.read(maximum:480,at:now)
   try await Task.sleep(for:.milliseconds(20))
  }
  engine.finish()
  let drainLimit=ProcessInfo.processInfo.systemUptime+5
  while !engine.isDrained && ProcessInfo.processInfo.systemUptime<drainLimit {
   received += engine.read(maximum:480,at:ProcessInfo.processInfo.systemUptime)
   try await Task.sleep(for:.milliseconds(20))
  }
  print("Streaming source",blocks*size,"at",rate,"received",received.count,"at24000Hz, time",ProcessInfo.processInfo.systemUptime-start,"latency",engine.latency,"drained",engine.isDrained,"error",engine.failure as Any)
  precondition(engine.failure == nil && engine.isDrained)
  precondition(abs(received.count-48_000)<5,"Streaming sample count drifted or output was lost")
  precondition(received.allSatisfy(\.isFinite) && received.contains(where:{abs($0)>0.001}))
  func rms(_ x:[Float])->Double {sqrt(x.reduce(0){$0+Double($1*$1)}/Double(x.count))}
  func snr(_ guess:[Float])->Double {20*log10(rms(truth)/max(1e-12,rms(zip(truth,guess).map(-))))}
  print("Streaming quality input SNR",snr(mixture),"output",snr(received))
  precondition(snr(received)>snr(mixture)+4,"Chunked isolation failed to improve voice over instruments")
  engine.reset()
  precondition(!engine.isDrained && !engine.hasPendingAudio)
  engine.push([Float](repeating:0.1,count:44_100),rate:44_100,at:ProcessInfo.processInfo.systemUptime)
  engine.reset()
  try await Task.sleep(for:.milliseconds(180))
  precondition(engine.read(maximum:24_000,at:ProcessInfo.processInfo.systemUptime).isEmpty,"Reset released old inference output")
  engine.cancel()
  precondition(engine.isDrained && !engine.hasPendingAudio)
  let cold=IsolatedVocals(modelURL:path)
  cold.push([Float](repeating:0.1,count:44_100),rate:44_100,at:ProcessInfo.processInfo.systemUptime)
  cold.cancel()
  try await Task.sleep(for:.milliseconds(150))
  precondition(cold.isDrained && cold.read(maximum:24_000,at:ProcessInfo.processInfo.systemUptime).isEmpty)
  print("EOF, exact resampling, reset during inference, and cold cancellation passed.")
 }
}
