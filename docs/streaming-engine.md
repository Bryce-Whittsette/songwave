# Streaming engine decisions

SongWave's live speaker mode already uses Core Audio process taps, a bounded ring buffer and native DSP. It does not load the Spleeter model. Spleeter is an optional higher-quality path used only by Trackpad only → Isolated. Users install SongWave once; they do not need an SDK, Python environment, virtual audio driver, or another project's app.

## Engine comparison

| Option | Verified status | Decision |
| --- | --- | --- |
| Native DSP | Built into SongWave; no model download or license key. Existing spectral-flux percussion detection plus the low-bass envelope described below. | Implemented; default live path. |
| Rapidly SDK | Its music model lists 96 ms algorithmic latency and a roughly 1.4 MB file. The SDK is proprietary; clean output needs a valid license. Its README says the music-model desktop benchmark is not yet published. | Not bundled. Evaluate with a valid distribution license and a Mac benchmark before choosing it. |
| HS-TasNet | The paper reports 23 ms algorithmic latency. Full/small networks have 42M/16M parameters. The linked Python implementation demonstrates training or loading one's own checkpoint. | A research candidate, not a validated drop-in replacement. A suitable trained checkpoint, native streaming conversion, license/provenance check and Mac benchmark are still needed. |

Sources: [Rapidly model table](https://github.com/rapidly-labs/rapidly-sdk#models), [Rapidly license](https://github.com/rapidly-labs/rapidly-sdk/blob/main/LICENSE), [HS-TasNet paper](https://arxiv.org/abs/2402.17701), [implementation](https://github.com/lucidrains/HS-TasNet).

These are engineering references, not extra installation steps. An architecture implementation with randomly initialized weights is not a working music separator. Model file size is also not a RAM measurement, and algorithmic latency is not end-to-end physical haptic latency.

## Native rhythm path

1. Capture audio with the existing per-process tap. The callback only copies samples into bounded memory.
2. Analyze recent PCM on the playback queue. Existing positive spectral-flux detection creates discrete percussion events; harmonic checks reduce vocal triggers.
3. A causal high-pass/low-pass energy follower estimates low bass. Existing FFT pitch evidence gates sustain to 38–85 Hz and requires stable evidence across slices. This avoids making the tested 95–225 Hz voiced syllables into a constant rumble.
4. Render separate sharp attacks and softer low-bass sustain. Sustain is capped at 0.28 before the user's gain and volume controls. **Fine Tune → Bass sustain** scales it, including zero for taps only. Continuous bass does not create extra keyboard-light beat events. Transient emphasis adjusts the attack-to-tail contrast.
5. Clear or decay state on silence, capture gaps, source changes and suppression. Call and speech filtering still applies.

This is rhythm-focused DSP, not clean drum/bass stem separation. Very low voices, overlapping instruments, room noise and dense mixes can still be ambiguous. Broadly subtracting the center channel is not used: centered kicks, snares and bass must remain available. A future stereo mask needs evidence that it preserves these cases before replacing the current path.

The normal speaker audio is not delayed or re-emitted through SongWave. Haptics use reported output delay plus the existing manual offset. Bluetooth routes and capture buffering still affect synchronization.

## Measurements on the development M4 MacBook Air

An optimized offline benchmark processed 60 seconds of precomputed 24 kHz PCM in 7,500 analysis slices. The released baseline took 0.229 seconds; the sustain candidate took 0.239 seconds. Maximum resident size of the DSP-only test process was approximately 4.03 MB versus 4.05 MB. This is a single-run comparison, not the complete app's RAM usage or a physical timing certification.

In a synthetic 65 Hz onset test, the detector emitted the first percussion event 16 ms after onset and enabled bass sustain at 32 ms. These are digital analysis timings, excluding capture, output scheduling and physical motor response. The additional envelope state occupies 104 bytes and is fixed-size. No new neural model, lookahead buffer, network request or runtime dependency is introduced. The existing analysis window and capture/output buffers remain part of latency; there is no claim of under-5-ms end-to-end response.

Regression tests cover low bass at multiple rates, vocal syllables, sustain bypass, silence, suppression, independent transient shaping and the existing simulated live Spotify/Music/browser routing. Real-song listening remains necessary.

## Voice / Beat selection and pending separator decision

Haptic focus is independent of audible output. Beat uses the existing rhythm DSP; Voice uses the existing vocal-focused analysis. The existing Spleeter vocal-isolation path remains limited to Voice with Trackpad only. No separator weights, inference code or network service were changed. Extending the model to accompaniment or other output routes requires Bryce's approval before implementation.

UVR's official repository describes file-oriented processing with bundled Python/PyTorch and GPU/RAM requirements: [UVR](https://github.com/Anjok07/ultimatevocalremovergui). It is not a native live-stream engine. Rapidly's documented music-model latency is 96 ms, with clean output requiring an appropriate licence; the desktop music benchmark is not published in its model table. HS-TasNet's architecture alone does not supply a validated SongWave checkpoint or native integration. No new third-party runtime is bundled or audio uploaded.

The continuous bass layer covers 38–85 Hz. Transient analysis also covers mid/high percussion; those events use 125/250/375 Hz driver requests with different release envelopes. These are requested tactile tones, not measured motor frequencies, and the signal monitor's 65 Hz label is an input-spectrum marker. Stem separation and tactile rendering solve different problems. Hardware measurements and song/timestamp examples are needed to distinguish missed detection from weak physical reproduction.

A diagnostic sweep using isolated exponentially decaying sinusoidal attacks at 24 kHz detected one attack each at 65, 80, 90, 125, 200, 300, 800 and 2,500 Hz. The requested tactile tones were respectively 125, 125, 125, 125, 125, 250, 250 and 375 Hz. These synthetic fixtures establish basic range coverage, not recall under vocals or dense instrumentation, and do not measure the physical motor. The recurring report of bass-dominated feedback in Speakers + haptics remains a listening/measurement issue rather than a confirmed fix.
