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

The default suite checks EQ controls, percussion/vocal separation heuristics, timing offsets, adversarial AHAP parsing, envelope behavior, simulated live routes, stale startup/route recovery, extreme sample rates, malformed PCM/file boundaries, explicit-player interruption/reconnect/failure handling, access recovery, and signed-update feed rejection. It does not play audio or actuate the trackpad or keyboard. See the [session stress report](audits/session-stress-1.0.md) for test scope and hardware limits.

Optional actual-model tests:

```sh
bash Tests/test-isolation.sh
```

This generates speech directly into a temporary file with macOS `say`, then runs the bundled Core ML model. It checks separation improvement on a controlled mix, sample counts, EOF draining, cancellation, and rapid mode changes under CPU load through production playback with fake I/O. It does not play the fixture over speakers. Results on a generated fixture do not establish accuracy on every real song.

Access-check deadline/admission tests and the real menu/controller's injected sleep/wake bindings run in the default suite. The optional model stress test also covers recognized-call suppression and lost PCM followed by explicit recovery. [Live authorization evidence and hardware limits](audits/capture-authorization-1.0.md) distinguish those checks from physical sleep, real calls and OS permission revocation.

`bash Tests/test-call-permission.sh` compiles the real controller, playback, capture and access helper against a symbol-audited fake Core Audio boundary. It assesses ringing/active calls, late startup, rapid call changes, stopped/zero callbacks, persistent denial and same-process recovery. CI runs it separately. It prints known acceptance gaps; `--require-all` returns nonzero while they remain. See the [interruption/revocation assessment](audits/call-permission-1.0.md); fixture passes are not live-call/TCC verification.

GitHub Actions runs default tests and a build on `macos-26`. Neural tests can be selected in a manual workflow run. CI does not measure physical haptics or validate the private driver ABI on different hardware.

`python3 Tests/UpdateNetworkRegression.py` exercises real Sparkle HTTP checks against a disposable loopback server: unavailable endpoint, HTTP errors, dropped/truncated feeds, cancellation, a background-check failure, and signed-feed retries. CI runs it separately from the offline suite. The fixture has its own actual bundle identifier and temporary signing key; it downloads no app payload and never installs an update or changes the listener's network settings. See [updater network coverage](audits/update-network-1.0.md).

`python3 Tests/UpdateDiskSpaceRegression.py` is an opt-in installer test on a bounded disposable disk image. It verifies a real out-of-space error, preservation of the old signed app, and successful installation after freeing space. **Checks → Run workflow → disk_space** runs it in CI. See [disk-space test safeguards and limits](audits/update-disk-space-1.0.md).

The default suite also checks first-success state/cancellation, unmuted non-actuating preview, bounded explicit test output with fake hardware, adversarial diagnostics privacy, and display suspension/recovery and the iPhone PCM queue/analysis-suspension policy. The separate iPhone workflow compiles unsigned Simulator and device targets. See the [mobile development guide](mobile.md) and [energy measurement protocol](energy.md).

## Layout

- `Sources/`: native Swift/SwiftUI app and DSP.
- `Resources/`: icon, licenses, and bundled Spleeter Core ML model.
- `YouTube/` and `Helpers/`: optional category filter and native messaging host.
- `Examples/`: an AHAP example; embedded audio references are skipped.
- `Tests/`: offline regression tests.
- `Tools/`: release packaging.

The vocal model is included for offline use. Its weights are approximately 38 MB uncompressed; Light and Speakers + haptics do not load the model. Do not commit built apps, release images, personal settings, signing material, or credentials.
