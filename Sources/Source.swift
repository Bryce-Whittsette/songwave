import AppKit
import Foundation

enum Provider: String, CaseIterable {
    case spotify = "Spotify"
    case apple = "Apple Music"

    var bundle: String { self == .spotify ? "com.spotify.client" : "com.apple.Music" }
    var appName: String { self == .spotify ? "Spotify" : "Music" }
    var icon: String { self == .spotify ? "dot.radiowaves.left.and.right" : "music.note" }
}

struct MusicLink: Equatable {
    let url: URL
    let provider: Provider

    init(_ input: String) throws {
        let string = input.trimmingCharacters(in: .whitespacesAndNewlines)
        let invalid = GlassError("Paste a Spotify or Apple Music link to a song, album, or playlist.")
        if string.hasPrefix("spotify:") {
            let components = string.split(separator: ":", omittingEmptySubsequences: false)
            guard components.count == 3,
                  Self.spotifyType(String(components[1])), Self.spotifyID(String(components[2])),
                  let canonical = URL(string: "https://open.spotify.com/\(components[1])/\(components[2])") else { throw invalid }
            url = canonical
            provider = .spotify
            return
        }

        guard let components = URLComponents(string: string),
              components.scheme?.lowercased() == "https",
              components.user == nil, components.password == nil, components.port == nil,
              let url = components.url, let host = components.host?.lowercased() else { throw invalid }

        var path = url.pathComponents.dropFirst()
        if path.first?.hasPrefix("intl-") == true { path = path.dropFirst() }
        switch host {
        case "open.spotify.com":
            guard path.count == 2, let type = path.first, let id = path.last,
                  Self.spotifyType(type), Self.spotifyID(id),
                  let canonical = URL(string: "https://open.spotify.com/\(type)/\(id)") else { throw invalid }
            self.url = canonical
            provider = .spotify
        case "music.apple.com":
            guard path.count >= 3,
                  ["album", "song", "playlist"].contains(path[path.index(after: path.startIndex)]) else { throw invalid }
            self.url = url
            provider = .apple
        default:
            throw invalid
        }
    }

    private static func spotifyType(_ value: String) -> Bool {
        ["track", "album", "playlist"].contains(value)
    }

    private static func spotifyID(_ value: String) -> Bool {
        value.count == 22 && value.utf8.allSatisfy { (48...57).contains($0) || (65...90).contains($0) || (97...122).contains($0) }
    }

    var playerURL: URL {
        if provider == .spotify {
            return URL(string: "spotify:" + url.pathComponents.dropFirst().joined(separator: ":")) ?? url
        }
        return url
    }
}

enum PlaybackSource: Equatable {
    case macAudio
    case demo
    case ultraBeat
    case file(URL)
    case player(MusicLink)

    var title: String {
        switch self {
        case .macAudio: return "Mac Audio"
        case .demo: return "Sound Check"
        case .ultraBeat: return "Ultra Demo"
        case .file(let url): return url.deletingPathExtension().lastPathComponent
        case .player(let link): return link.provider.rawValue
        }
    }

    var detail: String {
        switch self {
        case .macAudio: return "Audio from apps on this Mac"
        case .demo: return "Built-in demo · 12 seconds"
        case .ultraBeat: return "Built-in beat · \(Int(PartyBurst.length)) seconds"
        case .file(let url): return "\(url.pathExtension.uppercased()) · Local audio"
        case .player(let link): return "Live audio from \(link.provider.appName)"
        }
    }

    var icon: String {
        switch self {
        case .macAudio: return "speaker.wave.2"
        case .demo, .ultraBeat: return "tuningfork"
        case .file: return "music.note"
        case .player(let link): return link.provider.icon
        }
    }

    var isLive: Bool {
        switch self {
        case .player, .macAudio: return true
        case .demo, .ultraBeat, .file: return false
        }
    }
}
