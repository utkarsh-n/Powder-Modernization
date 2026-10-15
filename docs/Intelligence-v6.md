# Powder 0.6 — conversation before construction

The floating assistant now discusses a scene before creating it. An incomplete request can produce up to three questions with concrete choices. The first choice is suggested, and the player can select alternatives or reply in their own words. Typed additions are preserved when submitting the choices. Use these choices explicitly moves to proposal generation and accepts recommended defaults for remaining details, so the on-device model cannot keep cycling through clarification questions.

A complete proposal shows its shape, materials, composition and expected behavior. The app constructs it in a separate engine world, produces an initial-layout thumbnail and runs a 45-step trial away from the main UI thread. **Confirm scene** places the initial world as one undoable edit; sending a message never replaces the canvas. The trial is an observation of initial behavior, not proof that a complex machine works.

The conversation stays available when the bar is collapsed or hidden. Command-Return sends a message. Shift-Command-G shows and focuses the bar; Option-Command-P toggles its visibility. The composer stays editable while the assistant works, and Stop invalidates late results. A typed revision must be sent or cleared before confirming an older preview. If the canvas was edited or running during preparation, a second replacement confirmation protects the newer work.

## Grounded suggestions

The assistant can draw from thirteen curated original-community references, selected by the current request and conversation. See [Community references](Community-References-v6.md) for original save/forum links and provenance. The collection covers electronics, computing, power-plant layouts, terrain, water cycles, optics and artwork. These are description-based design references; no community saves were downloaded, executed, copied into the app or claimed as verified implementations. This release does not search the web during each chat.

Both providers receive exact supported material identifiers, bounded conversation history, the retained design specification and selected choices. Cloud requests use a strict structured response schema and `store: false`; the recent conversation and applicable reference summaries are sent to the configured OpenAI model. API credentials remain in Keychain. On-device discussion requires Apple Intelligence and macOS 26 or later. Native provider refusals are respected. The native adapter reserves output space inside the model context, measures tokens on macOS 26.4+ and estimates conservatively on earlier supported systems. It removes repeated design snapshots and optional reference context before asking the player to shorten an overlong conversation; repeated user answers and their questions are preserved. One bounded retry can repair malformed output, but refusals and context errors are not retried.

## Geometry and efficiency

On-device layouts now support physically round containers, open tanks, empty vessels and balanced, compact, spacious or layered arrangements. A rectangular shell is constructed from four walls instead of filling and erasing its interior. In the recorded equivalent 25,843-particle fixture this reduced construction from 68.323 ms to 8.398 ms (8.14×). This measures scene construction, not language-model latency. See [layout validation](Apple%20Layout%20Geometry.md).

Brush handling now performs a native bulk traversal with a read-only collision preflight. Rejected strokes and empty erases avoid copying the undo world. History is recorded only when a brush actually changes the world, preserving Redo after a no-op. Wall tools also detect unchanged strokes, while retaining real effects such as resetting a moving fan and Erase All deleting particles or signs. Inspection directly queries the wall cell instead of copying the entire wall map. Recorded release medians: metal stroke 6.228 → 3.162 ms; blocked stroke 6.060 → 0.361 ms; empty erase 5.780 → 0.134 ms. See [engine measurements](Engine%20Interaction%20Performance.md) for fixtures and scope. These results are not FPS claims.

## Validation record

- Engine tests cover brush parity across all 194 materials, RNG continuity, sparks, energy-layer erase and wall bounds.
- Worker/session tests cover Undo/Redo, no-op edits and scene revision tracking.
- Injected assistant tests cover questions, retained choices, preview isolation, confirmation, Undo, stale cancellation results, changed or running canvas protection and missing required materials.
- Cloud transport/schema tests use mocked HTTP responses, including refusal, cancellation and invalid output. No billable cloud generation was performed.
- Layout checks cover closed rectangular/circular vessels, open tops, empty and single-content designs, eight separated contents, composition styles and invalid geometry.

Across the focused runs, 112 distinct automated tests passed: 40 engine tests (36 brush/engine plus four wall regressions), 33 worker/session/assistant tests (16 worker, five session and twelve assistant), and 39 cloud package tests. The final assistant/wall run used the current source and passed 13/13; earlier runs establish the unchanged cases. Eight layout verification groups and 62 reference-catalog checks also passed.

The universal Release build succeeded for arm64 and x86_64. The clean packaged app passed strict ad-hoc signature verification after extraction; this is a local development release, not a notarized distribution. Build and package evidence: `mac-build-v6-release.log` and `mac-package-v6-final.log`.

Live on-device validation of the final provider asked the missing shape in 4.92 seconds, returned a complete proposal after Circular was selected in 5.53 seconds, and generated a 65-command plan in 9.04 seconds. Independent checks of that unchanged plan confirmed a hollow circular boundary made of 64 connected glass segments. After 45 real engine ticks, all 5,770 GLAS and 1,260 WATR particles remained finite and contained; water settled downward as expected. An initial probe incorrectly demanded a single circle primitive, so its false-negative result is preserved alongside the corrected geometric and engine verification. Evidence: `on-device-conversation-v6-final-circular/benign-water/geometry-review.json`.

The first shared-instruction experiment declined both the requested explosive scene and a benign water scene. Instruction cleanup fixed the benign request, and the explicit proposal phase fixed repeated clarification loops. The original refused request was not rephrased or repeatedly attempted to evade the provider. Cloud conversation and construction remain transport-tested rather than live-API-tested. Complex machines and long-running reactions still require broader validation.

An intermediate packaged GUI build restored the existing 18,432-particle experiment paused, displayed live shape/material/layout choices, and preserved a typed draft through hide/restore. It exposed the missing-proposal behavior corrected in the final provider. Automatic approval review then blocked opening the final packaged GUI as an unrecognized local software source, so final GUI launch awaits explicit confirmation. No alternate launch was attempted. The user's canvas was not replaced during UI verification. See `mac-assistant-ui-v6-notes.md` and the live-provider evidence directories for the exact sequence.

## Build and package

`xcodegen generate`, then build `PowderMac` in Release for generic macOS. The Xcode project targets macOS 14+ with both arm64 and x86_64. If iCloud file coordination stalls Xcode startup inside Documents, copy the source to a local temporary directory and build there. `POWDER_MAC_APP=/absolute/path/to/Powder.app scripts/package-macos.sh` packages that build, verifies both architectures and checks the ad-hoc signature after extracting the ZIP. Source and app archives are versioned 0.6.0; earlier archives remain available.
