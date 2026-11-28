import Foundation

struct GlassError: LocalizedError { let errorDescription: String?; init(_ value: String) { errorDescription = value } }

@main struct SourceRegression {
    static func main() throws {
        let id = "0123456789ABCDEFGHIJKL"
        var failures: [String] = []
        var accepted = 0, rejected = 0
        func check(_ condition: Bool, _ label: String) { if !condition { failures.append(label) } }
        for type in ["track", "album", "playlist"] {
            let canonical = "https://open.spotify.com/\(type)/\(id)"
            for input in ["spotify:\(type):\(id)", "https://open.spotify.com/\(type)/\(id)?si=fixture#fragment",
                          " \nHTTPS://OPEN.SPOTIFY.COM/intl-en/\(type)/\(id)\t"] {
                let link = try MusicLink(input)
                check(link.provider == .spotify && link.url.absoluteString == canonical && link.playerURL.absoluteString == "spotify:\(type):\(id)", "Spotify canonicalization/type")
                accepted += 1
            }
        }
        for type in ["track", "album", "playlist"] {
            for scheme in ["SPOTIFY", "Spotify", "sPoTiFy"] {
                do {
                    let link = try MusicLink("\(scheme):\(type):\(id)")
                    check(link.url.absoluteString == "https://open.spotify.com/\(type)/\(id)" &&
                        link.playerURL.absoluteString == "spotify:\(type):\(id)",
                        "Scheme normalization must preserve the type and case-sensitive item ID")
                    accepted += 1
                } catch { failures.append("Valid case-insensitive Spotify URI scheme rejected") }
            }
        }
        for input in ["https://music.apple.com/us/song/fixture/123", "https://music.apple.com/gb/album/fixture/123?i=456",
                      "https://music.apple.com/us/playlist/fixture/pl.fixture", "HTTPS://MUSIC.APPLE.COM/us/song/fixture/123"] {
            let link = try MusicLink(input)
            check(link.provider == .apple && link.playerURL == link.url && link.url == URL(string: input),
                "Apple Music source/player identity and song-selection query preservation")
            accepted += 1
        }
        let invalid = ["", " \n", "https://example.com/track/\(id)", "http://open.spotify.com/track/\(id)",
            "file:///tmp/fixture.m4a", "javascript:alert(1)", "spotify:episode:\(id)", "spotify:track:",
            "spotify:track:\(id):extra", "spotify:track:short", "spotify:track:" + String(repeating: "é", count: 22),
            "spotify:track:" + String(repeating: "A", count: 21), "spotify:track:" + String(repeating: "A", count: 23),
            "SPOTIFY:TRACK:\(id)", "ſpotify:track:\(id)", "spotify：track:\(id)", "spotify:track:\(id)?si=fixture",
            "https://open.spotify.com.evil.test/track/\(id)", "https://open.spotify.com@evil.test/track/\(id)",
            "https://user@open.spotify.com/track/\(id)", "https://user:secret@music.apple.com/us/song/fixture/123",
            "https://open.spotify.com:443/track/\(id)", "https://music.apple.com:443/us/song/fixture/123",
            "https://open.spotify.com/track/\(id)/extra", "https://open.spotify.com/episode/\(id)",
            "https://music.apple.com/", "https://music.apple.com/us/song", "https://music.apple.com/us/video/fixture/123",
            "https://music.apple.com.evil.test/us/song/fixture/123", "https://open.spotify.com/track/%2F" + id,
            "spotify:track:" + String(repeating: "A", count: 8192)]
        for input in invalid {
            do { _ = try MusicLink(input); failures.append("Malformed/unsupported or misleading source was accepted") }
            catch { rejected += 1 }
        }
        let mac = PlaybackSource.macAudio
        let file = PlaybackSource.file(URL(fileURLWithPath: "/fixture/Name.with.dots.FLAC"))
        let player = PlaybackSource.player(try MusicLink("spotify:track:\(id)"))
        check(mac.isLive && player.isLive && !file.isLive, "Live/local source distinction")
        check(file.title == "Name.with.dots" && file.detail == "FLAC · Local audio", "File source display facts")
        check(Provider.spotify.bundle == "com.spotify.client" && Provider.apple.bundle == "com.apple.Music", "Provider app identities")
        print("Source validation:", accepted, "accepted fixtures,", rejected, "rejected fixtures;", failures.count, "failures. No files, players, clipboard or network were opened.")
        for failure in failures { print("FAIL:", failure) }
        if !failures.isEmpty { exit(1) }
    }
}
