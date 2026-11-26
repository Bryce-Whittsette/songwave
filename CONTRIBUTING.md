# Contributing

Start with [development setup](docs/development.md) and [architecture](docs/architecture.md). Open an issue before a large change. Small fixes can go straight to a pull request.

Keep audio callbacks bounded, preserve call/speech suppression, and release taps, keyboard brightness and queued model work on every exit. Document changes to private interfaces or permission handling. Do not add network audio processing, telemetry or automatic playback without a clear user-facing reason and discussion.

Run `bash Tests/run.sh` and build the app. If you change vocal isolation, run `bash Tests/test-isolation.sh`. State which Mac and OS you tested and distinguish offline fixtures from physical listening tests. Do not imply hardware safety or universal compatibility from a passing unit test.

Pull requests should explain the user-visible problem, the final behavior and relevant validation. Preserve third-party notices.
