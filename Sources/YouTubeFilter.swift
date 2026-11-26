import AppKit

struct YouTubeState: Decodable {
    let browser: String
    let category: String
    let title: String
    let videoID: String?
    let position: Double?
    let duration: Double?

    static func playing() -> [YouTubeState] {
        let manager = FileManager.default
        let directory = manager.temporaryDirectory.appendingPathComponent("studio.songwave.youtube")
        let keys: Set<URLResourceKey> = [.contentModificationDateKey, .fileSizeKey, .isRegularFileKey, .isSymbolicLinkKey]
        let files = (try? manager.contentsOfDirectory(at: directory, includingPropertiesForKeys: Array(keys))) ?? []
        return files.compactMap { file in
            guard file.pathExtension == "json", let attrs = try? file.resourceValues(forKeys: keys),
                  attrs.isRegularFile == true, attrs.isSymbolicLink == false, let date = attrs.contentModificationDate,
                  (0..<3.5).contains(Date().timeIntervalSince(date)), (attrs.fileSize ?? 9999) <= 4096,
                  let data = try? Data(contentsOf: file) else { return nil }
            return try? JSONDecoder().decode(Self.self, from: data)
        }
    }

    static func family(for bundle: String) -> String? {
        let id = bundle.lowercased()
        if id.contains("firefox") || id.contains("org.mozilla") { return "firefox" }
        if id.contains("com.google.chrome") || id.contains("/google chrome.app/") { return "chrome" }
        return nil
    }

    @MainActor static func setUp(_ browser: String) throws {
        guard let root = Bundle.main.resourceURL?.appendingPathComponent("YouTube/").appendingPathComponent(browser),
              FileManager.default.fileExists(atPath: root.appendingPathComponent("manifest.json").path) else {
            throw GlassError("Reopen SongWave from its installed app bundle to set up the browser filter.")
        }
        let chrome = browser == "Chrome"
        let helper = Bundle.main.bundleURL.appendingPathComponent("Contents/Helpers/SongWaveYouTubeHost")
        let support = FileManager.default.urls(for: .applicationSupportDirectory, in: .userDomainMask)[0]
        let folder = support.appendingPathComponent(chrome ? "Google/Chrome/NativeMessagingHosts" : "Mozilla/NativeMessagingHosts")
        try FileManager.default.createDirectory(at: folder, withIntermediateDirectories: true)
        let config: [String: Any] = ["name": "studio.songwave.youtube", "description": "SongWave YouTube filter",
            "path": helper.path, "type": "stdio",
            chrome ? "allowed_origins" : "allowed_extensions": chrome ? ["chrome-extension://kpiakiaghboeeldacdoeeoglmdamopog/"] : ["youtube@songwave.local"]]
        try JSONSerialization.data(withJSONObject: config).write(to: folder.appendingPathComponent("studio.songwave.youtube.json"), options: .atomic)
        NSWorkspace.shared.activateFileViewerSelecting([root])
    }
}
