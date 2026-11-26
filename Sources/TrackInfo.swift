import AppKit
import AVFoundation
import Foundation
import ImageIO

struct TrackInfo: Equatable {
    var title: String?
    var artist: String?
    var cover: Data?
}

enum TrackCatalog {
    private struct SpotifyPreview: Decodable {
        let title: String
        let thumbnail_url: URL?
    }

    private struct AppleLookup: Decodable {
        struct Item: Decodable {
            let trackId: Int?
            let collectionId: Int?
            let trackName: String?
            let collectionName: String?
            let artistName: String?
            let artworkUrl100: URL?
        }
        let results: [Item]
    }

    static func metadata(for source: PlaybackSource) async -> TrackInfo? {
        switch source {
        case .demo, .ultraBeat, .macAudio:
            return nil
        case .file(let url):
            return await localMetadata(url)
        case .player(let link):
            switch link.provider {
            case .spotify: return await spotifyMetadata(link.url)
            case .apple: return await appleMetadata(link.url)
            }
        }
    }

    private static func spotifyMetadata(_ url: URL) async -> TrackInfo? {
        var endpoint = URLComponents(string: "https://open.spotify.com/oembed")!
        endpoint.queryItems = [URLQueryItem(name: "url", value: url.absoluteString)]
        guard let data = await request(endpoint.url),
              let preview = try? JSONDecoder().decode(SpotifyPreview.self, from: data) else { return nil }
        return TrackInfo(title: preview.title, cover: await artwork(preview.thumbnail_url))
    }

    private static func appleMetadata(_ url: URL) async -> TrackInfo? {
        let components = URLComponents(url: url, resolvingAgainstBaseURL: false)
        let trackID = components?.queryItems?.first { $0.name == "i" }?.value.flatMap { Int($0) }
        let itemID = trackID ?? Int(url.lastPathComponent)
        if let itemID {
            var endpoint = URLComponents(string: "https://itunes.apple.com/lookup")!
            var query = [URLQueryItem(name: "id", value: String(itemID))]
            if let region = url.pathComponents.dropFirst().first, region.count == 2 {
                query.append(URLQueryItem(name: "country", value: region))
            }
            endpoint.queryItems = query
            if let data = await request(endpoint.url),
               let lookup = try? JSONDecoder().decode(AppleLookup.self, from: data),
               let item = lookup.results.first(where: { $0.trackId == itemID || $0.collectionId == itemID }) {
                return TrackInfo(title: item.trackName ?? item.collectionName, artist: item.artistName,
                                 cover: await artwork(item.artworkUrl100))
            }
        }

        // Apple Music playlist links use non-numeric IDs and expose their display metadata on the page.
        guard let data = await request(url), let html = String(data: data, encoding: .utf8),
              let title = openGraph("og:title", in: html), title != "Apple Music Web Player" else { return nil }
        let imageURL = openGraph("og:image", in: html).flatMap(URL.init(string:))
        return TrackInfo(title: title, cover: await artwork(imageURL))
    }

    private static func openGraph(_ key: String, in html: String) -> String? {
        let escaped = NSRegularExpression.escapedPattern(for: key)
        let pattern = #"<meta\b(?=[^>]*\bproperty=["']"# + escaped + #"["'])[^>]*\bcontent=["']([^"']*)["'][^>]*>"#
        let regex = try? NSRegularExpression(pattern: pattern, options: .caseInsensitive)
        let range = NSRange(html.startIndex..<html.endIndex, in: html)
        guard let match = regex?.firstMatch(in: html, range: range),
              let valueRange = Range(match.range(at: 1), in: html) else { return nil }
        return String(html[valueRange])
            .replacingOccurrences(of: "&quot;", with: "\"")
            .replacingOccurrences(of: "&#39;", with: "'")
            .replacingOccurrences(of: "&amp;", with: "&")
            .replacingOccurrences(of: "&nbsp;", with: " ")
            .replacingOccurrences(of: "\u{00a0}", with: " ")
    }

    private static func localMetadata(_ url: URL) async -> TrackInfo? {
        let asset = AVURLAsset(url: url)
        guard let items = try? await asset.load(.commonMetadata) else { return nil }
        let title = items.first { $0.identifier == .commonIdentifierTitle }
        let artist = items.first { $0.identifier == .commonIdentifierArtist }
        let cover = items.first { $0.identifier == .commonIdentifierArtwork }
        let coverData = try? await cover?.load(.dataValue)
        return TrackInfo(title: try? await title?.load(.stringValue),
                         artist: try? await artist?.load(.stringValue),
                         cover: thumbnail(coverData))
    }

    private static func artwork(_ url: URL?) async -> Data? {
        guard var components = url.flatMap({ URLComponents(url: $0, resolvingAgainstBaseURL: false) }),
              let host = components.host?.lowercased(),
              host.hasSuffix(".scdn.co") || host.hasSuffix(".spotifycdn.com") || host.hasSuffix(".mzstatic.com") else { return nil }
        components.scheme = "https"
        return thumbnail(await request(components.url, limit: 4_000_000))
    }

    static func videoCover(_ id: String?) async -> Data? {
        guard let id, id.count == 11, id.utf8.allSatisfy({ (48...57).contains($0) || (65...90).contains($0) || (97...122).contains($0) || $0 == 45 || $0 == 95 }) else { return nil }
        return thumbnail(await request(URL(string: "https://i.ytimg.com/vi/\(id)/mqdefault.jpg"), limit: 400_000))
    }

    private static func thumbnail(_ data: Data?) -> Data? {
        guard let data, let source = CGImageSourceCreateWithData(data as CFData, nil),
              let image = CGImageSourceCreateThumbnailAtIndex(source, 0, [
                kCGImageSourceCreateThumbnailFromImageAlways: true,
                kCGImageSourceThumbnailMaxPixelSize: 320,
                kCGImageSourceCreateThumbnailWithTransform: true
              ] as CFDictionary) else { return nil }
        return NSBitmapImageRep(cgImage: image).representation(using: .png, properties: [:])
    }

    private static let session: URLSession = {
        let configuration = URLSessionConfiguration.ephemeral
        configuration.timeoutIntervalForRequest = 7
        configuration.timeoutIntervalForResource = 10
        return URLSession(configuration: configuration)
    }()

    private static func request(_ url: URL?, limit: Int = 2_000_000) async -> Data? {
        guard let url, url.scheme == "https" else { return nil }
        guard let (data, response) = try? await session.data(from: url),
              let response = response as? HTTPURLResponse, (200..<300).contains(response.statusCode),
              data.count <= limit else { return nil }
        return data
    }
}

struct PlayerTrack {
    let id: String
    let info: TrackInfo
    let duration: Double
    let position: Double
    let coverURL: URL?
    let observed = ProcessInfo.processInfo.systemUptime
}

// Both desktop players publish their playback dictionary through standard Apple events.
// Query on a utility task, by PID, so a closed player is never launched.
extension TrackCatalog {
    static func playing(_ provider: Provider) async -> PlayerTrack? {
        guard let pid = NSRunningApplication.runningApplications(withBundleIdentifier: provider.bundle).first?.processIdentifier else { return nil }
        return await playing(provider, pid: pid)
    }

    static func playing(_ provider: Provider, pid: pid_t) async -> PlayerTrack? {
        await Task.detached(priority: .utility) {
            guard pid == getpid() || PlaybackAccess.playerStatus(pid, ask: false) == noErr else { return nil }
            func code(_ name: String) -> UInt32 { name.utf8.reduce(0) { $0 << 8 | UInt32($1) } }
            func property(_ key: String, of container: NSAppleEventDescriptor? = nil) -> NSAppleEventDescriptor? {
                let spec = NSAppleEventDescriptor.record()
                spec.setDescriptor(.init(typeCode: code("prop")), forKeyword: code("want"))
                spec.setDescriptor(.init(enumCode: code("prop")), forKeyword: code("form"))
                spec.setDescriptor(.init(typeCode: code(key)), forKeyword: code("seld"))
                spec.setDescriptor(container ?? NSAppleEventDescriptor.null(), forKeyword: code("from"))
                return spec.coerce(toDescriptorType: code("obj "))
            }
            func read(_ key: String, of container: NSAppleEventDescriptor? = nil) -> NSAppleEventDescriptor? {
                let event = NSAppleEventDescriptor(eventClass: code("core"), eventID: code("getd"),
                    targetDescriptor: NSAppleEventDescriptor(processIdentifier: pid), returnID: -1, transactionID: 0)
                guard let operand = property(key, of: container) else { return nil }
                event.setParam(operand, forKeyword: code("----"))
                guard let reply = try? event.sendEvent(options: [.waitForReply, .neverInteract], timeout: 1.5),
                      reply.paramDescriptor(forKeyword: code("errn"))?.int32Value ?? 0 == 0 else { return nil }
                return reply.paramDescriptor(forKeyword: code("----"))
            }
            guard read("pPlS")?.enumCodeValue == code("kPSP"), let item = property("pTrk") else { return nil }
            let spotify = provider == .spotify
            guard let id = read(spotify ? "spur" : "pPIS", of: item)?.stringValue,
                  let title = read("pnam", of: item)?.stringValue else { return nil }
            let artist = read("pArt", of: item)?.stringValue
            let rawDuration = (read("pDur", of: item)?.doubleValue ?? 0) / (spotify ? 1000 : 1)
            let duration = rawDuration.isFinite && rawDuration > 0 && rawDuration < Double(Int.max) ? rawDuration : 0
            let rawPosition = read("pPos")?.doubleValue ?? 0
            let position = rawPosition.isFinite ? min(duration, max(0, rawPosition)) : 0
            let cover = spotify ? read("aUrl", of: item)?.stringValue.flatMap(URL.init(string:)) : nil
            guard read(spotify ? "spur" : "pPIS", of: item)?.stringValue == id else { return nil }
            return PlayerTrack(id: id, info: TrackInfo(title: title, artist: artist), duration: duration,
                               position: position, coverURL: cover)
        }.value
    }

    static func cover(for track: PlayerTrack, provider: Provider) async -> Data? {
        if let url = track.coverURL { return await artwork(url) }
        if provider == .spotify, let link = try? MusicLink(track.id) { return await spotifyMetadata(link.url)?.cover }
        guard let artist = track.info.artist, let title = track.info.title else { return nil }
        var query = URLComponents(string: "https://itunes.apple.com/search")!
        query.queryItems = [.init(name: "term", value: artist + " " + title),
                            .init(name: "entity", value: "song"), .init(name: "limit", value: "6")]
        guard let data = await request(query.url), let lookup = try? JSONDecoder().decode(AppleLookup.self, from: data),
              let match = lookup.results.first(where: {
                  $0.trackName?.caseInsensitiveCompare(title) == .orderedSame &&
                  $0.artistName?.caseInsensitiveCompare(artist) == .orderedSame
              }) else { return nil }
        return await artwork(match.artworkUrl100)
    }
}
