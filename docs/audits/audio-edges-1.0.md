# Extreme-input and long-pattern integration

Existing tests already cover 16 capture/playback rates from 8–768 kHz, invalid format metadata, malformed ring layouts, empty/truncated audio files and AHAP byte mutations. This pass connects those boundaries: the real `AudioTap` callback, `SampleRing`, router and `Playback` now run together at 8 and 192 kHz against disposable SDK/output replacements.

Run:

```sh
bash Tests/test-call-permission.sh --audio-edges
```

The normal Checks workflow runs this after the call/permission fixture. Both use a unique test bundle and symbol-audit the executable before running; real Core Audio capture/property entry points must be absent. The edge fixture also rejects a link to the system `AVAudioPlayer` class. No recording grants, microphone, speaker, keyboard or actuator are used. Temporary files and the fixture's own preference domain are removed on exit.

## Coverage and results

- Eight real callback/ring/playback routes: 8/192 kHz × automatic/explicit source × both outputs. Empty, stopped, zero-filled, half-frame, missing-data, invalid-channel, misaligned, oversized, missing/short-plane and nonfinite callbacks remain bounded. Sustained missing PCM releases mute ownership, generates uncertain recovery guidance and resumes on fresh audio.
- Fifty maximum-valid 1 MiB packets offer 13,107,200 samples. The ring retains exactly its newest 32,768 samples. An oversized declaration is rejected before accessing the data.
- A 4,096-event AHAP spans 60 minutes plus a final 30-second sustain. 453,751 simulated 8 ms ticks produce exactly 4,095 transient attacks and expire the sustain. Tests cover the 1 MiB input boundary, 256 parameter curves, delayed/repeated/invalid transport positions and backwards seeks.
- Real Playback starts near 60 minutes in a disposable sparse WAV, replaces/removes a long pattern 200 times, bypasses/resumes and stops without retained output. Its speaker clock and motor are mocks. The sparse file has about 116 MB of logical zero PCM without allocating that much audio in memory or writing it all to disk.

All passed locally. No production defect was found in these cases, so no production code or protected DSP/model files were changed. An initial buffer-list indexing mistake in the new fixture was corrected before acceptance; it was not an application finding.

## Limits

Buffer backing memory is always valid. Tests corrupt declared layout/contents, not pointer lifetime: a raw C pointer provides no allocation length that SampleRing can independently verify. Deliberately dangling or underallocated pointers would be undefined behavior in the harness, not a safe capture simulation.

The hour is simulated transport time, not a physical hour-long listening/energy test. Device sample-rate support, audible quality, physical actuator response and OS permission behavior are not established by these passes. Pattern parsing/rendering internals, isolation/model code, branding, signing and notarization remain untouched.
