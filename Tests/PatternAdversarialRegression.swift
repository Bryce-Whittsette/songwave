import Foundation

@main struct PatternAdversarialRegression {
    static func main() throws {
        let event: [String: Any] = ["Time": 0, "EventType": "HapticTransient"]
        func data(_ entries: [[String: Any]]) throws -> Data {
            try JSONSerialization.data(withJSONObject: ["Version": 1, "Pattern": entries])
        }
        var failures = 0
        for invalid: Any in [NSNull(), "quiet", 0, true,
                             [NSNull()], [["ParameterID": "HapticIntensity"]],
                             [["ParameterID": "HapticIntensity", "ParameterValue": 0.1], "bad"]] {
            var malformed = event; malformed["EventParameters"] = invalid
            do {
                _ = try HapticPattern(data: data([["Event": malformed]]))
                fputs("FAIL: malformed EventParameters silently became default intensity 1.\n", stderr); failures += 1
            } catch {}
        }
        guard failures == 0 else { exit(1) }
        let duplicate = [["ParameterID": "HapticIntensity", "ParameterValue": 0.1],
                         ["ParameterID": "HapticIntensity", "ParameterValue": 1]]
        var duplicated = event; duplicated["EventParameters"] = duplicate
        let curve: [String: Any] = ["Time": 0, "ParameterID": "HapticIntensityControl",
            "ParameterCurveControlPoints": [["Time": 0, "ParameterValue": 1]]]
        let invalid = [try data([["Event": duplicated]]), try data([["Event": event, "ParameterCurve": curve]]),
            Data(repeating: 32, count: 1_048_577), Data([0xff, 0xfe, 0x00]),
            Data(#"{"Version":1,"Pattern":[{"Event":{"Time":1e999,"EventType":"HapticTransient"}}]}"#.utf8)]
        for bytes in invalid {
            do { _ = try HapticPattern(data: bytes); preconditionFailure("An adversarial AHAP fixture was accepted") } catch {}
        }
        // Embedded audio is deliberately ignored, including hostile-looking paths.
        for path in ["../../private/secret.wav", "file:///etc/passwd", "https://example.invalid/audio", "$(touch nope)"] {
            let document = try HapticPattern(data: data([["Event": event],
                ["Event": ["Time": 0, "EventType": "AudioCustom", "EventWaveformPath": path]]]))
            precondition(document.events.count == 1 && document.skippedAudio == 1)
        }
        let overlap: [String: Any] = ["Time": 0, "EventType": "HapticContinuous", "EventDuration": 1]
        _ = try HapticPattern(data: data(Array(repeating: ["Event": overlap], count: 32)))
        do { _ = try HapticPattern(data: data(Array(repeating: ["Event": overlap], count: 33))); preconditionFailure("Overlap limit was ignored") } catch {}
        let original = try data([["Event": event]])
        var random: UInt64 = 0x534f4e4757415645
        var accepted = 0
        for _ in 0..<10000 {
            var mutated = original
            random = random &* 6364136223846793005 &+ 1
            mutated[Int(random % UInt64(mutated.count))] ^= UInt8(truncatingIfNeeded: random >> 32) | 1
            if let pattern = try? HapticPattern(data: mutated) {
                accepted += 1
                var player = HapticPattern.Player(pattern)
                for time in [0.0, 0.008, 0.2, 3600, 10800, 0, Double.nan, -Double.infinity] {
                    let frame = player.frame(at: time)
                    precondition(frame.level.isFinite && (0...1).contains(frame.level))
                    precondition(frame.tones.allSatisfy { $0.hertz.isFinite && $0.weight.isFinite && $0.weight >= 0 })
                }
            }
        }
        print("Malformed AHAP parameter shapes are rejected instead of producing default-strength haptics.")
        print("10,000 deterministic byte mutations, ambiguous/duplicate parameters, invalid encodings/numbers, hostile audio references and overlap boundaries passed; \(accepted) valid mutations stayed bounded.")
    }
}
