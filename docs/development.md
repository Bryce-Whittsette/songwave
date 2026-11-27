# Build and test

The public download is an Apple silicon build. The source compiles for the host Mac's architecture; Intel builds and older OS versions have not been hardware-validated.

## Requirements

macOS, Apple's command-line tools or Xcode, and the macOS 26 SDK or newer. The deployment target is macOS 14.2. A Force Touch trackpad is needed to run haptics, but not to compile the app or run the default tests.

Install Apple's developer tools if you don't already have them. Paste this into Terminal, press Return, and finish the installation window:

```sh
xcode-select --install
```

After that installation completes, paste:

```sh
mkdir -p "$HOME/Developer"
cd "$HOME/Developer"
git clone https://github.com/Bryce-Whittsette/songwave.git
cd songwave
bash install.sh
open "$HOME/Applications/SongWave.app"
```

If you've already cloned the project, use `cd "$HOME/Developer/songwave"` rather than cloning again. The installer puts SongWave in your personal Applications folder. It refuses to replace a different application at that location.

To use the downloadable source archive instead, extract `songwave-source.zip` into Downloads and paste:

```sh
cd "$HOME/Downloads/songwave-source"
bash install.sh
open "$HOME/Applications/SongWave.app"
```

Build without installing:

```sh
bash build.sh /tmp/SongWave.app
```

Builds are ad hoc signed by default. A replacement binary can cause macOS to ask for recording permission again. SongWave preserves its own setup, while macOS controls the permission decision. The first 0.5.4 source build downloads a pinned, checksum-verified Sparkle archive; installed apps need no SDK download. Release identity and updater instructions are in [Updates](updates.md).

## Tests

```sh
bash Tests/run.sh
```

The default suite checks EQ controls, percussion/vocal separation heuristics, timing offsets, AHAP parsing, envelope behavior, simulated live routes, explicit-player interruption/reconnect/failure handling, access recovery, and signed-update feed rejection. It does not play audio or actuate the trackpad or keyboard.

Optional actual-model tests:

```sh
bash Tests/test-isolation.sh
```

This generates speech directly into a temporary file with macOS `say`, then runs the bundled Core ML model. It checks separation improvement on a controlled mix, sample counts, EOF draining, and cancellation. It does not play the fixture over speakers. Results on a generated fixture do not establish accuracy on every real song.

GitHub Actions runs default tests and a build on `macos-26`. Neural tests can be selected in a manual workflow run. CI does not measure physical haptics or validate the private driver ABI on different hardware.

The default suite also checks display suspension/recovery and the iPhone PCM queue/analysis-suspension policy. The separate iPhone workflow compiles unsigned Simulator and device targets. See the [mobile development guide](mobile.md) and [energy measurement protocol](energy.md).

## Layout

- `Sources/`: native Swift/SwiftUI app and DSP.
- `Resources/`: icon, licenses, and bundled Spleeter Core ML model.
- `YouTube/` and `Helpers/`: optional category filter and native messaging host.
- `Examples/`: an AHAP example; embedded audio references are skipped.
- `Tests/`: offline regression tests.
- `Tools/`: release packaging.

The vocal model is included for offline use. Its weights are approximately 38 MB uncompressed; Light and Speakers + haptics do not load the model. Do not commit built apps, release images, personal settings, signing material, or credentials.
