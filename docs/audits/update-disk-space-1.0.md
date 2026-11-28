# Disk-full update installation

The real pinned Sparkle installer failed safely when its destination ran out of space, retained a valid build 1, and successfully installed build 2 after space was freed. This was a disposable fixture on the development Mac, not the installed SongWave app or a full system disk.

```sh
python3 Tests/UpdateDiskSpaceRegression.py
```

CI can run this through **Checks → Run workflow → disk_space**. It is opt-in because it creates and mounts a disk image. It uses user-owned fixtures and requires no production signing key, administrator elevation, audio permission or physical actuator.

## Evidence and safeguards

- A temporary 192 MB APFS image is mounted without appearing in Finder. Before filling, the test checks that its device differs from the parent filesystem and its capacity is below 256 MiB. It also requires at least 512 MiB free on the host before starting. The filler loop is capped at 256 MiB and writes only inside that verified image.
- A disposable app and candidate are signed with a temporary test key. The candidate contains an extra 16 MiB payload, larger than APFS's remaining reported reserve. The production archive, installed app, feed, signing key and signing scripts are unchanged.
- The filler write must actually fail with `ENOSPC`. APFS may still report several MB free; that reported reserve alone is not treated as proof of install failure.
- A separate fixture driver keeps Sparkle alive outside the target bundle. This observes final replacement errors even after the target would otherwise quit. Reaching “ready to install” is not counted as a successful installation or a disk-full failure.
- The real installer returned `SUSparkleErrorDomain/4005` with nested `NSCocoaErrorDomain/640` and `NSPOSIXErrorDomain/28`. The old target's version remained 1 and strict code signature verification passed before space was freed.
- After deleting only the test filler, the same updater process retried successfully. The target's version became 2 and strict signature verification passed again. The test deliberately disables relaunch of the target; this is installation/retry evidence, not another relaunch or UI approval test.
- The server binds only to loopback. The fixture driver supplies approval only for its disposable target. Temporary test preference domains, filler and volume are cleaned up; no global network, permission or power settings change.

The fixture follows Sparkle's supported separation between the [updater process and target app](https://github.com/sparkle-project/Sparkle/blob/2.10.1/Documentation/Installation.md). The script uses `hdiutil` on macOS 26 and the replacement `diskutil image` commands on macOS 27. A successful local pass is not multi-Mac compatibility evidence. This tests insufficient destination space during full-archive installation; full cache/system volume, sudden drive removal, power loss and delta-patch installation under disk exhaustion remain separate cases.
