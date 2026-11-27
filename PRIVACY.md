# Privacy

SongWave processes captured audio on your Mac. It keeps audio in bounded memory and does not save recordings or upload audio for analysis. The vocal model is bundled; it requires no account or runtime model download.

**System Audio Recording** lets the app capture audio from other processes. Source selection, music recognition and call filtering happen locally. Filtering is approximate and should not be treated as a privacy boundary around which audio macOS makes available to the app.

**Automation** access to Spotify or Music is optional and reads the current song, artwork address and playback position. It is requested from Playback Access.

Song details and artwork can involve network requests to Spotify oEmbed, Apple's iTunes catalog, YouTube thumbnail hosts and artwork hosts supplied by catalog results. This can disclose a song/link lookup, title/artist query, or image request to those services. Network requests use an ephemeral URLSession. Captured audio is not part of those requests.

The optional YouTube extension reads information about the playing YouTube video, including category, title, position and video identity, and passes it to the local native host. It is restricted to YouTube domains. Browser native-messaging configuration and app preferences are stored locally.

SongWave has no built-in advertising, analytics service or application account. GitHub has its own policies for release downloads and issue submissions. Sharing through Messages opens a draft; the user chooses the recipient and sends it.

SongWave includes automatic update checks through Sparkle. The release feed and app downloads use GitHub hosting, which receives normal network connection information and the app's update request. Audio, song titles and listening history are not included. Sparkle system profiling is disabled. Checks can be turned off, and installation requires approval. See [Updates](docs/updates.md).

## iPhone development build

Imported files are copied into temporary storage on the iPhone and analyzed locally. They are not uploaded. Temporary imports are removed on the next launch; preferences remain in local UserDefaults. Album art is read from file metadata or loaded from Apple's catalog.

Apple Music access is optional and requested only when you choose Connect. Search, authorization and streaming use Apple's MusicKit services and their network requests. SongWave supplies the selected song's ISRC to the system Now Playing information for Apple's Music Haptics. It does not capture audio from Spotify or other iPhone apps. This prototype has no separate SongWave server or analytics service.

## Connection diagnostics

**Listening help → Copy diagnostics** builds a local clipboard report from app/build, validated Mac hardware model, numeric macOS version, output transport category, app category and categorical connection/error states. It excludes raw error text, song titles, filenames, personal paths, output-device names, bundle identifiers and recordings. Nothing is uploaded or sent automatically. First-success confirmation and unfinished-setup state are saved locally.
