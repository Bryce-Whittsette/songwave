# Updates

SongWave 0.5.4 adds an in-app updater. People on 0.5.3 need to install 0.5.4 manually once.

## For listeners

SongWave checks automatically, roughly once an hour, and asks before downloading and installing. Use **SongWave → Check for Updates…** or **Settings → Updates** to check now. **Check for Updates Automatically** turns background checks off or on.

People on 0.5.3 need one manual installation of the first updater-enabled release. Later versions can arrive through the app. Installing from a DMG still works.

Updates use [Sparkle](https://sparkle-project.org/). SongWave verifies the release feed and archive against its embedded public key. This protects update authenticity; it does not replace Apple notarization or guarantee macOS will never ask for permission again. Update checks contact GitHub's hosting/download services, which receive normal connection information. Audio, song titles and listening history are not sent; Sparkle system profiling is disabled.

Updates can download a smaller signed patch when the installed version matches a published base. Sparkle falls back to the full signed archive if a patch cannot be used. This reduces transfer size; check timing still depends on the app running, network access and Sparkle scheduling. Existing saved scheduling preferences remain respected. Nothing silently enables installation.

## For maintainers

An ordinary Git push does not release an app update. Publish a reviewed GitHub release with signed update assets; **Publish update feed** then advances the feed automatically after verification.

Update `Resources/Info.plist`, keep `CFBundleVersion` increasing, write `docs/releases/<version>.md` with a **What changed** section, and commit/review the source. On the release Mac, use a fresh packaging folder:

```sh
bash Tests/run.sh
bash build.sh /tmp/SongWave.app
bash Tools/package.sh /tmp/SongWave.app /tmp/songwave-release
bash Tools/publish-release.sh /tmp/songwave-release
```

The last command creates a **draft**. Review it, then publish on GitHub. Add `--publish` only for an already reviewed release.

The tool verifies the exact clean build commit and package hashes, signs the ZIP/feed and delta patches, and adds `appcast.xml` to the release. For up to three recent published builds, it verifies the old signed archive before extraction, creates a Sparkle v4 delta, applies it to the old app, compares reconstructed contents/permissions/symlinks and verifies its code signature. Only patches smaller than the full ZIP are included. `--full-only` prepares a release without patches. The workflow verifies signatures with the public key and checks the enclosed app's identity, version, key and minimum OS before updating `updates/appcast.xml` on `main`. It never moves the feed backward. Check the workflow before announcing a release. The first updater-enabled release needs this workflow on the default branch before publication. Normal CI and feed publication need no private signing key; the workflow needs repository contents-write permission. Future branch protection may require a feed PR or approved bot.

## Keys and distribution

Sparkle 2.10.1 is pinned to its official archive SHA-256 in `Tools/fetch-sparkle.sh`. The first source build downloads it. Downloaded apps include the framework and notices; listeners install no SDK.

The Ed25519 key stays in the release Mac's login Keychain under account **studio.songwave.trackpad**. Only its public key is committed. Keep an encrypted backup outside the repository. Never put a private key in source, issues, logs or release notes. Losing it prevents automatic updates until recovery distribution; feed-signature failures do not expire in this configuration.

Set `SONGWAVE_SIGNING_IDENTITY` to an installed **Developer ID Application** identity for distribution builds. Nested Sparkle tools are signed inside out; Developer ID builds enable hardened runtime and timestamps. Development builds can remain ad hoc. Complete notarization/stapling and test the actual identity before broad promotion. The updater does not notarize apps.

## Verification

`Tests/run.sh` instantiates the real pinned Sparkle updater with an isolated host bundle, without starting checks or touching listener preferences. It verifies the hourly default, opt-out and rejection of a saved automatic-install preference. A disposable signed-bundle test exercises real patch creation/reconstruction, wrong-base and corruption rejection. The feed verifier checks canonical patch URLs, source builds, unique bases, lengths and signatures. It also verifies the real signed seed feed and rejects content changes, wrong keys, unsigned suffixes, missing signatures and wrong lengths. `Tools/prepare-update.py` signs releases with the Keychain key; `Tools/verify-update.swift` repeats verification with only the public key.

Automated network recovery coverage runs separately with `python3 Tests/UpdateNetworkRegression.py`. It uses the pinned Sparkle framework and a disposable app/server to test failed manual/background checks followed by successful signed retries. It verifies that checks become available again and that the update stays undownloaded until approval. No production keys, installed app or listener preferences are used. This covers feed-check failures, not loss of connectivity during archive download or disk-full installation. See the [test report](audits/update-network-1.0.md).

For an interactive installation smoke test:

```sh
bash Tests/prepare-update-smoke.sh /private/tmp/songwave-update-test
python3 -m http.server 28945 --bind 127.0.0.1 --directory /private/tmp/songwave-update-test/server
```

Open the disposable app in `client`, then test damaged feeds, damaged archives and a valid installation. A successful relaunch writes `results/installed.txt`. The fixture uses a temporary test key and contains no SongWave audio/hardware code. Use a local temporary folder; cloud-synced folders can attach Finder metadata that invalidates development signatures. A successful fixture test is not multi-Mac compatibility evidence.

[Sparkle delta updates](https://sparkle-project.org/documentation/delta-updates/) · [Sparkle setup](https://sparkle-project.org/documentation/) · [Publishing signed updates](https://sparkle-project.org/documentation/publishing/) · [Apple notarization](https://developer.apple.com/documentation/security/notarizing-macos-software-before-distribution)
