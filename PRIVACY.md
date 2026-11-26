# Privacy

SongWave processes captured audio on your Mac. It keeps audio in bounded memory and does not save recordings or upload audio for analysis. The vocal model is bundled; it requires no account or runtime model download.

**System Audio Recording** lets the app capture audio from other processes. Source selection, music recognition and call filtering happen locally. Filtering is approximate and should not be treated as a privacy boundary around which audio macOS makes available to the app.

**Automation** access to Spotify or Music is optional and reads the current song, artwork address and playback position. It is requested from Playback Access.

Song details and artwork can involve network requests to Spotify oEmbed, Apple's iTunes catalog, YouTube thumbnail hosts and artwork hosts supplied by catalog results. This can disclose a song/link lookup, title/artist query, or image request to those services. Network requests use an ephemeral URLSession. Captured audio is not part of those requests.

The optional YouTube extension reads information about the playing YouTube video, including category, title, position and video identity, and passes it to the local native host. It is restricted to YouTube domains. Browser native-messaging configuration and app preferences are stored locally.

SongWave has no built-in advertising, analytics service or application account. GitHub has its own policies for release downloads and issue submissions. Sharing through Messages opens a draft; the user chooses the recipient and sends it.
