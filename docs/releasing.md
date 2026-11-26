# Release process

## Public preview

The first public release is v0.5.2. It is a GitHub prerelease, named Public Preview. The README links directly to its DMG because GitHub's latest-release shortcut may exclude prereleases.

The DMG is the primary download. The ZIP is an alternative. The source archive and checksums are for developers and users who want to inspect the release. The app is Apple silicon, ad hoc signed and unnotarized. Do not describe it as Apple-verified or universally hardware-tested.

## Prepare an update

1. Update the version and build number in `Resources/Info.plist`.
2. Run default tests, the optional neural suite for relevant changes, and a build. Listen on actual supported hardware and check call suppression, stop, relaunch, muting restoration and keyboard restoration.
3. Update user-facing instructions and release notes. Keep compatibility and known issues explicit.
4. Build from the commit you intend to tag, then package it:

```sh
bash build.sh /tmp/SongWave.app
bash Tools/package.sh /tmp/SongWave.app /tmp/songwave-release
```

5. Create a draft release, upload the DMG, app ZIP, source ZIP and SHA256SUMS, verify the tag points to the reviewed commit, then publish. Check public download links after publishing.

The packaging script creates a drag-to-Applications DMG and verifies an extracted ZIP's signature. It does not notarize the app. Build in a clean checkout; the source archive includes tracked files, including the bundled vocal model.

## Signing milestone

A later release should use an Apple-issued Developer ID identity, notarization and stapling before broad promotion. Keep signing credentials out of the repository. The current preview does not contain an auto-updater; users install a new release explicitly.

## Feedback phase

Use GitHub Issues for bugs and feature requests. Fix reproducible routing, synchronization, crash and permission issues before expanding hardware claims. Update the tested-hardware matrix as real results arrive. A stable version should be based on that evidence, not only the current Mac's test results.
