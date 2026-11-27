# Release process

## Public preview

Public releases started with v0.5.2. The current Mac public preview is v0.5.12. Previews are GitHub prereleases; the README links directly to the current DMG because GitHub's latest-release shortcut may exclude prereleases. [Version history](../CHANGELOG.md) covers every public version.

The DMG is the primary download. The ZIP is an alternative. The source archive and checksums are for developers and users who want to inspect the release. The app is Apple silicon, ad hoc signed and unnotarized. Do not describe it as Apple-verified or universally hardware-tested.

## Prepare an update

1. Update the version and build number in `Resources/Info.plist`.
2. Run default tests, the optional neural suite for relevant changes, and a build. Listen on actual supported hardware and check call suppression, stop, relaunch, muting restoration and keyboard restoration.
3. Add `docs/releases/<version>.md` and a newest-first entry in `CHANGELOG.md`. Lead with a few plain-language changes and easy download/update steps. Put implementation details, validation scope, measurements and code comparisons in an expandable `<details>` section. State compatibility and known issues explicitly. Update the README's version, download link and short What's new list. Keep previous versions and their downloads available; never invent release entries for unarchived local prototypes.
4. Build from the commit you intend to tag, then package it:

```sh
bash build.sh /tmp/SongWave.app
bash Tools/package.sh /tmp/SongWave.app /tmp/songwave-release
```

5. Use that version's Markdown file as the GitHub release body. Create a draft release, upload the DMG, app ZIP, source ZIP and SHA256SUMS, verify the tag points to the reviewed commit, then publish. Check public download links after publishing, download the public assets and verify checksums. For historical releases missing detailed notes, use their version's file without replacing binaries or moving tags.

The packaging script creates a drag-to-Applications DMG and verifies an extracted ZIP's signature. It does not notarize the app. Build in a clean checkout; the source archive includes tracked files, including the bundled vocal model.

## Signing milestone

A later release should use an Apple-issued Developer ID identity, notarization and stapling before broad promotion. Keep signing credentials out of the repository. Versions through 0.5.3 have no updater and need one manual installation. Versions 0.5.4 onward include signed in-app updates; use the [release/update pipeline](updates.md). Checks can run automatically, but the listener approves downloading and installing. The iPhone source prototype is not a public mobile release; its separate signing and device-validation steps are in the [mobile guide](mobile.md).

## Feedback phase

Use GitHub Issues for bugs and feature requests. Fix reproducible routing, synchronization, crash and permission issues before expanding hardware claims. Update the tested-hardware matrix as real results arrive. A stable version should be based on that evidence, not only the current Mac's test results.
