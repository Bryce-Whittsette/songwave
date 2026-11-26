import Foundation

struct TabState: Codable {
    let browser: String
    let category: String
    let title: String
    let videoID: String?
    let position: Double?
    let duration: Double?
}

let manager = FileManager.default
let directory = manager.temporaryDirectory.appendingPathComponent("studio.songwave.youtube", isDirectory: true)
try manager.createDirectory(at: directory, withIntermediateDirectories: true, attributes: [.posixPermissions: 0o700])
let file = directory.appendingPathComponent(UUID().uuidString + ".json")
defer { try? manager.removeItem(at: file) }

func readExactly(_ count: Int) -> Data? {
    var data = Data()
    while data.count < count {
        guard let chunk = try? FileHandle.standardInput.read(upToCount: count - data.count), !chunk.isEmpty else { return nil }
        data.append(chunk)
    }
    return data
}

while let header = readExactly(4) {
    let size = header.withUnsafeBytes { Int(UInt32(littleEndian: $0.loadUnaligned(as: UInt32.self))) }
    guard size > 0, size <= 4096, let bytes = readExactly(size),
          let state = try? JSONDecoder().decode(TabState.self, from: bytes),
          ["chrome", "firefox"].contains(state.browser),
          ["music", "other", "unknown"].contains(state.category), state.title.count <= 256 else { break }
    try bytes.write(to: file, options: .atomic)
}
