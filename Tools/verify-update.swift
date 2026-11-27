import Foundation
import CryptoKit

enum UpdateError: Error, CustomStringConvertible {
    case invalid(String)
    var description: String { switch self { case .invalid(let message): return message } }
}

// Sparkle signs exactly the byte prefix named in its trailing signature comment.
// Verify before XML parsing, and reject any unsigned suffix or mismatched length.
func verifiedFeed(_ data: Data, publicKey: Data) throws -> Data {
    guard data.count <= 2_097_152,
          let text = String(data: data, encoding: .utf8),
          let range = text.range(of: "<!-- sparkle-signatures:", options: .backwards) else {
        throw UpdateError.invalid("Missing signed update feed.")
    }
    let suffix = String(text[range.lowerBound...])
    let expression = try NSRegularExpression(pattern: #"\A<!-- sparkle-signatures:\s*edSignature: ([A-Za-z0-9+/=]+)\s*length: ([0-9]+)\s*-->\s*\z"#)
    guard let match = expression.firstMatch(in: suffix, range: NSRange(suffix.startIndex..., in: suffix)),
          let signatureRange = Range(match.range(at: 1), in: suffix),
          let lengthRange = Range(match.range(at: 2), in: suffix),
          let length = Int(suffix[lengthRange]),
          length == text[..<range.lowerBound].utf8.count,
          let signature = Data(base64Encoded: String(suffix[signatureRange])), signature.count == 64 else {
        throw UpdateError.invalid("Invalid feed signature or unsigned trailing content.")
    }
    let prefix = Data(data.prefix(length))
    let key = try Curve25519.Signing.PublicKey(rawRepresentation: publicKey)
    guard key.isValidSignature(signature, for: prefix) else { throw UpdateError.invalid("Update feed signature rejected.") }
    return prefix
}

final class FeedItems: NSObject, XMLParserDelegate {
    var items: [[String: String]] = []
    var latestDeltas: [[String: String]] = []
    private var inDeltas = false
    private var current: [String: String]?
    private var element = ""
    private var text = ""
    func parser(_ parser: XMLParser, didStartElement name: String, namespaceURI: String?, qualifiedName: String?, attributes: [String: String]) {
        element = name; text = ""
        if name == "item" { current = [:] }
        if name == "sparkle:deltas" { inDeltas = true }
        if name == "enclosure", current != nil, inDeltas {
            if items.isEmpty { latestDeltas.append(attributes) }
        } else if name == "enclosure", current != nil {
            current?["url"] = attributes["url"]
            current?["signature"] = attributes["sparkle:edSignature"]
            current?["length"] = attributes["length"]
        }
    }
    func parser(_ parser: XMLParser, foundCharacters string: String) { text += string }
    func parser(_ parser: XMLParser, didEndElement name: String, namespaceURI: String?, qualifiedName: String?) {
        if name == "sparkle:deltas" { inDeltas = false }
        if name == "item", let current { items.append(current); self.current = nil }
        else if name == element, current != nil { current?[name] = text.trimmingCharacters(in: .whitespacesAndNewlines) }
        text = ""
    }
}

func verifiedDeltas(_ deltas: [[String: String]], build: Int, fullLength: Int, tag: String,
                    folder: URL, key: Curve25519.Signing.PublicKey) throws {
    guard deltas.count <= 3 else { throw UpdateError.invalid("Too many delta updates.") }
    var bases = Set<Int>()
    for delta in deltas {
        guard let from = delta["sparkle:deltaFrom"], let fromBuild = Int(from), fromBuild > 0,
              fromBuild < build, bases.insert(fromBuild).inserted,
              delta["url"] == "https://github.com/Bryce-Whittsette/songwave/releases/download/\(tag)/SongWave-\(from)-\(build).delta",
              let size = delta["length"].flatMap(Int.init), size > 0, size < fullLength,
              let encoded = delta["sparkle:edSignature"], let signed = Data(base64Encoded: encoded), signed.count == 64 else {
            throw UpdateError.invalid("Delta source, URL, length or signature is invalid.")
        }
        let patch = try Data(contentsOf: folder.appendingPathComponent("SongWave-\(from)-\(build).delta"), options: .mappedIfSafe)
        guard patch.count == size, key.isValidSignature(signed, for: patch) else {
            throw UpdateError.invalid("Delta archive signature rejected.")
        }
    }
}

func runTool(_ path: String, _ arguments: [String]) throws -> Data {
    let process = Process(); let output = Pipe()
    process.executableURL = URL(fileURLWithPath: path); process.arguments = arguments
    process.standardOutput = output; process.standardError = FileHandle.nullDevice
    try process.run()
    let data = output.fileHandleForReading.readDataToEndOfFile()
    process.waitUntilExit()
    guard process.terminationStatus == 0 else { throw UpdateError.invalid("Cannot inspect the update archive.") }
    return data
}

func expectRejected(_ operation: () throws -> Void) throws {
    do { try operation() } catch { return }
    throw UpdateError.invalid("A malformed update fixture was accepted.")
}

func main() throws {
    let root = URL(fileURLWithPath: #filePath).deletingLastPathComponent().deletingLastPathComponent()
    let plist = try PropertyListSerialization.propertyList(from: Data(contentsOf: root.appendingPathComponent("Resources/Info.plist")), format: nil) as! [String: Any]
    guard let encodedKey = plist["SUPublicEDKey"] as? String, let publicKey = Data(base64Encoded: encodedKey), publicKey.count == 32 else {
        throw UpdateError.invalid("SongWave update public key is missing.")
    }
    var args = Array(CommandLine.arguments.dropFirst())
    let verifyBase = args.first == "--base"
    if verifyBase { args.removeFirst() }
    if args == ["--self-test"] {
        let feed = try Data(contentsOf: root.appendingPathComponent("updates/appcast.xml"))
        let prefix = try verifiedFeed(feed, publicKey: publicKey)
        var modified = feed; modified[100] ^= 1
        try expectRejected { _ = try verifiedFeed(modified, publicKey: publicKey) }
        try expectRejected { _ = try verifiedFeed(feed + Data("<rss/>".utf8), publicKey: publicKey) }
        try expectRejected { _ = try verifiedFeed(feed, publicKey: Data(repeating: 0, count: 32)) }
        try expectRejected { _ = try verifiedFeed(Data("<rss/>".utf8), publicKey: publicKey) }
        let wrongLength = String(decoding: feed, as: UTF8.self).replacingOccurrences(of: "length: \(prefix.count)", with: "length: \(prefix.count + 1)")
        try expectRejected { _ = try verifiedFeed(Data(wrongLength.utf8), publicKey: publicKey) }
        let nested = FeedItems()
        let nestedParser = XMLParser(data: Data("<rss><channel><item><enclosure url='full.zip'/><sparkle:deltas xmlns:sparkle='http://www.andymatuschak.org/xml-namespaces/sparkle'><enclosure url='patch.delta'/></sparkle:deltas></item></channel></rss>".utf8))
        nestedParser.delegate = nested
        guard nestedParser.parse(), nested.items.first?["url"] == "full.zip", nested.latestDeltas.first?["url"] == "patch.delta" else {
            throw UpdateError.invalid("Delta enclosures must not replace the full update enclosure.")
        }
        let temporaryKey = Curve25519.Signing.PrivateKey()
        let temporaryFolder = FileManager.default.temporaryDirectory.appendingPathComponent("songwave-delta-signature-" + UUID().uuidString)
        try FileManager.default.createDirectory(at: temporaryFolder, withIntermediateDirectories: true)
        defer { try? FileManager.default.removeItem(at: temporaryFolder) }
        let bytes = Data("test delta".utf8)
        let deltaPath = temporaryFolder.appendingPathComponent("SongWave-1-2.delta")
        try bytes.write(to: deltaPath)
        let delta = ["url": "https://github.com/Bryce-Whittsette/songwave/releases/download/v0.0.2/SongWave-1-2.delta",
            "sparkle:deltaFrom": "1", "length": String(bytes.count),
            "sparkle:edSignature": try temporaryKey.signature(for: bytes).base64EncodedString()]
        func verify(_ entries: [[String: String]]) throws {
            try verifiedDeltas(entries, build: 2, fullLength: 100, tag: "v0.0.2", folder: temporaryFolder, key: temporaryKey.publicKey)
        }
        try verify([delta])
        try expectRejected { try verify([delta, delta]) }
        for (field, value) in [("sparkle:deltaFrom", "2"), ("url", "https://example.com/patch"),
                               ("length", "100"), ("sparkle:edSignature", Data(repeating: 0, count: 64).base64EncodedString())] {
            var changed = delta; changed[field] = value
            try expectRejected { try verify([changed]) }
        }
        try Data("bad delta!".utf8).write(to: deltaPath)
        try expectRejected { try verify([delta]) }
        print("Signed feed/delta tampering, wrong URLs/sources/lengths, duplicate bases, and full/delta enclosure parsing passed.")
        return
    }
    guard args.count == 3 else { throw UpdateError.invalid("Usage: swift Tools/verify-update.swift appcast.xml SongWave-macOS.zip v0.5.4") }
    let xml = try verifiedFeed(Data(contentsOf: URL(fileURLWithPath: args[0])), publicKey: publicKey)
    let items = FeedItems(); let parser = XMLParser(data: xml)
    parser.shouldResolveExternalEntities = false; parser.delegate = items
    guard parser.parse(), let item = verifyBase ? items.items.first(where: { "v" + ($0["sparkle:shortVersionString"] ?? "") == args[2] }) : items.items.first,
          let version = item["sparkle:shortVersionString"],
          args[2] == "v" + version,
          item["url"] == "https://github.com/Bryce-Whittsette/songwave/releases/download/\(args[2])/SongWave-macOS.zip",
          let build = item["sparkle:version"], Int(build).map({ $0 > 0 }) == true,
          item["sparkle:hardwareRequirements"] == "arm64",
          let lengthText = item["length"], let length = Int(lengthText), length > 0, length <= 268_435_456,
          let encodedSignature = item["signature"], let signature = Data(base64Encoded: encodedSignature), signature.count == 64 else {
        throw UpdateError.invalid("Feed version, release URL, build, length or signature is invalid.")
    }
    let archive = try Data(contentsOf: URL(fileURLWithPath: args[1]), options: .mappedIfSafe)
    let key = try Curve25519.Signing.PublicKey(rawRepresentation: publicKey)
    guard archive.count == length, key.isValidSignature(signature, for: archive) else { throw UpdateError.invalid("Update archive signature rejected.") }
    if !verifyBase {
        try verifiedDeltas(items.latestDeltas, build: Int(build)!, fullLength: length, tag: args[2],
            folder: URL(fileURLWithPath: args[1]).deletingLastPathComponent(), key: key)
    }
    let info = try PropertyListSerialization.propertyList(from: runTool("/usr/bin/unzip", ["-p", args[1], "SongWave.app/Contents/Info.plist"]), format: nil) as? [String: Any]
    let executable = try runTool("/usr/bin/unzip", ["-p", args[1], "SongWave.app/Contents/MacOS/SongWave"])
    guard Array(executable.prefix(8)) == [0xcf, 0xfa, 0xed, 0xfe, 0x0c, 0, 0, 1] else {
        throw UpdateError.invalid("The Apple silicon feed requires an arm64 executable.")
    }
    guard info?["CFBundleIdentifier"] as? String == "studio.songwave.trackpad",
          info?["CFBundleVersion"] as? String == build,
          info?["CFBundleShortVersionString"] as? String == version,
          info?["SUPublicEDKey"] as? String == encodedKey,
          info?["LSMinimumSystemVersion"] as? String == item["sparkle:minimumSystemVersion"] else {
        throw UpdateError.invalid("Signed feed does not match the enclosed SongWave app.")
    }
    print("Verified signed feed and archive for SongWave \(version), build \(build).")
}
do { try main() } catch { fputs("\(error)\n", stderr); exit(1) }
