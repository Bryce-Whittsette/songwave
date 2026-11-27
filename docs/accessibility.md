# Accessibility checks

SongWave explores music through touch and visual rhythm, including for deaf and hard-of-hearing listeners. These checks protect the interface's accessibility semantics; they do not establish a hearing-accessibility benefit, physical sensation or comfort.

## Automated coverage

Run the ordinary regression suite:

```bash
bash Tests/run.sh
```

It checks that the system's Reduce Motion preference can never be overridden off, reduced-motion transactions suppress animation, and the visual activity presentation keeps its pulse scale and brightness fixed while retaining level and beat text. It also checks beat-text expiry, retriggering, silence and hidden-window cancellation without a background polling loop.

Run the native interface checks on a Mac with Xcode and macOS 26 or later:

```bash
bash Tests/Accessibility/run.sh
```

The **Native accessibility** GitHub Actions workflow runs the same command. It builds a disposable app using the production setup/recovery views and controller with fake audio, trackpad and permission edges. It never captures music, moves the motor or opens a permission dialog.

The checks cover the permission step, test-in-progress, sensation confirmation and recovery. End-to-end cases exercise permission → explicit test → confirmation, retries staying in recovery, recovery starting at the top after scrolling setup in a compact window, and optional/advanced controls remaining grouped in the production Console. They check descriptions and actions with Apple's accessibility audit, button/progress roles, labeled heading text, and depth-first reading order from XCTest's native hierarchy snapshot. The visual indicator exposes the native progress-indicator role with an audio/level/beat value description. Reduced-motion fixtures run in light and dark appearances. The fixture can add motion reduction, but cannot negate the OS preference.

macOS does not expose XCTest's trait audit or `hasFocus` API. XCTest also maps AX headings to static text. A separate live check in `Tests/Accessibility/native-tree-check.js` verifies native heading roles, action order and the progress value description against a fresh full `getAXState()` snapshot in an authorized computer-use session. This check runs locally; CI does not have permission for direct AX API reads and does not claim to validate heading traits. Reading order is not a substitute for testing VoiceOver's spoken navigation and rotor, or keyboard traversal under the listener's keyboard-access preferences. The empty system-created Touch Bar node, the unlabeled outer fixture hosting wrapper and the system Full Screen glyph's nested group are excluded narrowly by role, ownership and geometry. The production `support.content` group and its descendants remain audited; content failures remain failures.

The local Xcode UI runner can fail before starting tests with “Timed out while enabling automation mode.” That is an environment failure, not a passing audit. No test enables security bypasses or changes Accessibility/Automation permissions to work around it. Use the CI result and preserve the `.xcresult` path printed by the script when diagnosing a failure.

The main-listening case also exercises a forced 810 × 640 content window in light/dark with motion reduction on/off. Simulated music with haptics disabled must produce one passive, labeled progress indicator with a positive level. Its frame must stay visible and avoid Stop/Intensity. Silence clears the level, and Stop returns the player to its idle action. These simulation controls exist only in the test fixture, not the shipping app.

## Listener checks still needed

- Navigate setup and Listening help with VoiceOver: headings, action names, disabled test state, return from recovery and exit.
- Traverse actions with Tab and Shift-Tab under the listener's preferred keyboard-access setting. Check that focus remains visible and follows the task.
- Enable macOS Reduce Motion and verify that the pulse stays still, level/text remain useful, and state changes have no unwanted movement.
- Compare Voice, Beat and Both on real hardware. In Both, detected percussion should briefly stand in front of the vocal texture, then let it return smoothly. Check dense mixes and quiet hits as well as loud music.
- Ask deaf and hard-of-hearing listeners who choose to participate about clarity, comfort, missed details and useful visual feedback. Record hardware and output route without collecting music history.

Please report an interface problem through [GitHub issues](https://github.com/Bryce-Whittsette/songwave/issues/new/choose). Listening help can copy categorical connection diagnostics; it does not include song titles, recordings or personal paths.

## Advanced controls

The Tools category checks exercise Sound, Trackpad EQ and Experiments separately in light/dark and normal/reduced-motion fixtures. They check descriptive actions, category visibility, EQ/genre/intensity retention, band headings and opening/canceling Ultra without activation. Fine Tune cases cover Beat, Voice and Both in both outputs, heading order, unchanged Light selection, disabled volume following for Trackpad only, and reaching the last applicable section in a compact window. These are native hierarchy/action checks, not spoken VoiceOver or measured decision-time validation.

Advanced-sheet audits are scoped to each labeled production content container and all its descendants. XCTest's app-wide audit also visits the blocked player behind a sheet; snapshot identity (role, identifier, label and frame) limits these tests to the active content, excluding the inactive player and AppKit window/hosting wrappers. Existing setup/recovery audit scope is unchanged. Scroll actions target the active tuning container rather than the background player's scroll view. Genre is addressed by its identifier because macOS/XCTest can expose native menu pickers under different roles.
