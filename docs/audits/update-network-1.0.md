# Update-check network recovery

## Result

The pinned Sparkle 2.10.1 updater recovered from each tested feed-check failure without restarting the fixture app. Every successful retry verified its signed feed and offered build 2 in the **not downloaded** state. No update payload was requested, downloaded or installed without approval. No production updater change was needed for these cases.

Run on macOS:

```sh
python3 Tests/UpdateNetworkRegression.py
```

The Checks workflow runs this separately from the offline suite.

## What runs

The test compiles a disposable native host around the real Sparkle updater. Only its presentation driver is replaced: it records errors/update offers, acknowledges errors, cancels a pending request, and dismisses update offers. Sparkle owns HTTP, feed signature verification, session cleanup, retry and update availability. The test observes the same `canCheckForUpdates` publisher used by SongWave's menus. It waits for the session to finish as well as the check action to become available; a visible offer/error can allow focusing an existing session, so action availability alone is not a completion signal.

The app copies the production approval/signature policy with a unique **actual Info.plist bundle identifier**, its own temporary Ed25519 key and a loopback-only feed. Local HTTP exceptions apply only to the disposable fixture. A separately signed placeholder payload is advertised but must never be requested; the test is deliberately not an installer test.

| Case | Assertion |
| --- | --- |
| Reserved endpoint with no listening server | A network error is surfaced; acknowledgement allows a signed retry at the same URL. The observed URLSession error on the development Mac was timeout, not necessarily immediate connection refusal. |
| HTTP 503 | A check error is surfaced; the next signed check succeeds. |
| Server closes without headers | The broken connection fails, then a signed retry succeeds. |
| Server advertises a full response but sends a short fragment | The incomplete feed fails, then a signed retry succeeds. |
| Server accepts the request but sends no response | The user driver's supplied cancel action ends the session; retry succeeds. This tests cancellation, not a long automatic network timeout. |
| Background check receives HTTP 503 | The delegate receives the failure without presenting a manual-check error; the next manual signed retry succeeds. |
| Every healthy retry | The feed signature succeeds, the offered build is correct and not downloaded, and dismissing returns to a completed/retryable session. |
| Entire sequence | No archive URL requests, download callbacks or install callbacks occur. The host executable/build remain unchanged and strict code signature verification still passes. |

The fixture disables scheduled checks only in its own preference domain to keep requests deterministic. Automatic download/install remain forbidden by the production policy. Failure cleanup also removes that unique test preference domain. The test does not access production signing keys, change Wi-Fi, interrupt other apps, use the public feed or run SongWave audio/haptic code.

The unavailable-endpoint case allows up to 75 seconds for the SDK/URLSession network timeout; macOS versions differ in connection retry/wait behavior. Other transitions have 12-second assertion budgets, and the complete child process is capped at 120 seconds. The separate hanging-response case verifies explicit cancellation without waiting for that timeout. These are test budgets, not new application network settings.

## Remaining limits

This is an API integration test with recorded presentation callbacks, not a VoiceOver or visual test of Sparkle's standard update windows. It does not prove behavior during archive download/extraction, disk-full installation, proxy/captive-portal authentication or every physical network transition. Existing offline tests separately cover public-feed signatures and real signed-bundle delta reconstruction/rejection. The public 1.0.0 release and feed are unchanged by this coverage batch.
