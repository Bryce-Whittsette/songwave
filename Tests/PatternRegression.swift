import Foundation

@main struct PatternRegression {
    static func main() throws {
        let json = #"""
        {"Version":1,"Pattern":[
        {"Event":{"Time":0,"EventType":"HapticTransient","EventParameters":[{"ParameterID":"HapticIntensity","ParameterValue":0.8}]}},
        {"Event":{"Time":0.1,"EventType":"HapticContinuous","EventDuration":0.6,"EventParameters":[{"ParameterID":"HapticIntensity","ParameterValue":0.7}]}},
        {"ParameterCurve":{"Time":0.1,"ParameterID":"HapticIntensityControl","ParameterCurveControlPoints":[{"Time":0,"ParameterValue":1},{"Time":0.6,"ParameterValue":0}]}},
        {"Event":{"Time":0,"EventType":"AudioCustom","EventWaveformPath":"/should/never/open.wav"}}
        ]}
        """#
        let pattern = try HapticPattern(data: Data(json.utf8))
        precondition(pattern.skippedAudio == 1)
        var player = HapticPattern.Player(pattern)
        precondition(player.frame(at: 0).beatStrength == 0.8)
        precondition(player.frame(at: 0.008).beatStrength == 0)
        let middle = player.frame(at: 0.4)
        precondition(abs(middle.level - 0.35) < 1e-8, "Curve time must be relative to its own start.")
        precondition(player.frame(at: 0.71).level == 0)
        precondition(player.frame(at: 0).beatStrength == 0.8, "Seeking back must reset the event cursor.")
        precondition(player.frame(at: 600).level == 0, "Late callbacks must never replay stale events.")
        for invalid in [json.replacingOccurrences(of: "\"Time\":0.1", with: "\"Time\":-1"), json.replacingOccurrences(of: "\"EventDuration\":0.6", with: "\"EventDuration\":60")] {
            do { _ = try HapticPattern(data: Data(invalid.utf8)); preconditionFailure("Invalid pattern accepted") } catch {}
        }
        let booleanFields = [
            ("\"Version\":1", "\"Version\":true"),
            ("\"Time\":0,\"EventType\"", "\"Time\":false,\"EventType\""),
            ("\"EventDuration\":0.6", "\"EventDuration\":true"),
            ("\"ParameterValue\":0.8", "\"ParameterValue\":true"),
            ("\"ParameterCurve\":{\"Time\":0.1", "\"ParameterCurve\":{\"Time\":false"),
            ("\"Time\":0.6,\"ParameterValue\"", "\"Time\":true,\"ParameterValue\""),
            ("\"Time\":0,\"ParameterValue\":1", "\"Time\":0,\"ParameterValue\":true")
        ]
        for (original, replacement) in booleanFields {
            precondition(json.contains(original), "Boolean regression fixture did not match its target.")
            let invalid = json.replacingOccurrences(of: original, with: replacement)
            do { _ = try HapticPattern(data: Data(invalid.utf8)); preconditionFailure("Boolean accepted as an AHAP number") } catch {}
        }
        var renderer = MusicalEnvelope()
        let hit = SignalFrame(tones: [], level: 1, bands: [], inputRMS: 0, hasAudio: true, beatStrength: 1)
        precondition(renderer.frame(hit, at: 1).level == 1)
        let fading = renderer.frame(.empty, at: 1.05)
        precondition(fading.level > 0 && fading.level < 0.5)
        precondition(renderer.frame(.empty, at: 2).level == 0)
        var speech = MusicalEnvelope()
        let continuous = SignalFrame(tones: [Tone(hertz: 224, weight: 1)], level: 1, bands: [], inputRMS: 0.1, hasAudio: true)
        precondition(speech.frame(continuous, at: 1).level == 0, "Sustained audio without a rhythmic attack must not invent a hit.")
        if CommandLine.arguments.count > 1 {
            let imported = try HapticPattern(data: Data(contentsOf: URL(fileURLWithPath: CommandLine.arguments[1])))
            var loop = HapticPattern.Player(imported)
            var attacks = 0
            for index in 0...300 {
                let frame = loop.frame(at: Double(index) * 0.008)
                precondition(frame.level.isFinite && (0...1).contains(frame.level))
                if frame.beatStrength > 0 { attacks += 1 }
            }
            precondition(attacks >= 8 && imported.skippedAudio == 1)
        }
        print("Pattern curves, seek/late timing, bounded input, skipped audio, and live release envelopes passed.")
    }
}
