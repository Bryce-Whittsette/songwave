# Diagnostic hardware-query coverage

`ListeningDiagnostics.swift` had been replaced by a stub in controller/recovery tests. A new direct fixture covers the production implementation with compile-time `sysctlbyname` and AudioHardware replacements. Before running, the default test suite symbol-audits the executable to reject real hardware-query imports.

The audit reproduced a failure under injected malformed responses: a successful `hw.model` read without a NUL terminator traps in `String(cString:)`. Invalid UTF-8 returned replacement characters, an empty model returned an empty string, and zero/oversized returned lengths were ignored. These are adversarial API-response findings, not an observed real macOS failure or permission issue.

The fix validates the returned length against allocated storage, requires a nonempty terminated value within that length, and decodes UTF-8 safely. Any failure returns the existing **Unknown Mac** label. The model remains cached; no new timer, I/O or permission is added.

The default `bash Tests/run.sh` suite runs 13 model-response scenarios in separate processes so each exercises the real static initialization: normal, sizing/read errors, zero/negative/huge sizes, missing NUL, invalid UTF-8, empty text and inconsistent/truncated returned lengths. Each also checks caching, ten transport-category mappings and device/transport read failures. Only model/category property requests are allowed; no names, song information, paths, recordings or actual devices are queried.

Isolation, haptic rendering, Signal.swift, HapticPattern.swift, Core ML, visual styling and signing/notarization remain unchanged. Physical OS/hardware behavior is not claimed by the fixture.
