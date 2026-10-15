# Powder for Mac 0.5

The active app is now macOS-only (macOS 14+, universal arm64/x86_64). The iOS app target, active phone layout branches, and UIKit view wrapper are removed. Earlier cross-platform releases remain in versioned archives.

## Native workspace

- `NavigationSplitView` provides a resizable sidebar with system search, list selection, category filtering, all 194 materials and 19 wall types.
- The unified toolbar contains playback, single-step, Build/Run/Inspect, scene generation, canvas appearance and the optional inspector.
- Interface colors follow macOS appearance and accent settings. Color in the library identifies materials; large purple buttons, custom cards and the permanent prompt footer are gone.
- File, Edit, View, Simulation and Intelligence menus expose native keyboard commands. Text editing keeps its own undo manager and does not start playback when typing spaces.
- The canvas uses an AppKit `MTKView`, native trackpad magnification, pointer hover previews, and a stable frame source outside SwiftUI Observation.
- Both existing model providers remain available from the sparkle popover. This pass does not change or revalidate their live model behavior.

## Simulation, memory and recovery

`SimulationWorker` is a serial actor that exclusively owns the live C++ world and its history. It processes edit commands, physics, exports/imports, undo checkpoints and autosave encoding away from the main actor. Each batch prepares at most one immutable compact render frame. Frame submission redraws Metal directly; UI counters update at most five times a second during playback. The existing 30 Hz simulation cadence is retained.

An idle paused session waits for commands. A single debounced wake saves paused edits after five seconds without periodic polling. Window closure drains accepted edits; quitting pauses playback and waits for an ordered atomic-save barrier. The wake stream is recreated when a session's view task restarts. Playback creates one checkpoint at its start, allowing Undo to restore the pre-play state. macOS memory-pressure notifications discard redo and retain only the most recent undo checkpoint, without replacing the current world.

Compact render cells are 16 bytes instead of three float4 grids (48 bytes). The 612 × 384 upload is 3,760,128 bytes instead of 11,280,384 bytes: **66.7% smaller**. The immutable material profile table is cached, and three GPU upload slots are reused safely for in-flight work. Historical worlds retain the existing eight-checkpoint limit under normal memory conditions. This is reduced transient payload and allocation work, not a measured two-thirds reduction in total application RSS.

On the development Mac, a controlled 222,200-particle CPU frame-preparation benchmark measured **20.189 → 0.691 ms**. It excludes physics and GPU execution. See [Engine Performance](Engine%20Performance.md) for fixtures, less-dense cases and reproduction. GPU comparison is separately documented in [Rendering v5](Rendering-v5.md); a small GPU cost can accompany compact decoding even when CPU/upload costs improve. No whole-app FPS or thermal claim is inferred from these microbenchmarks.

Native `OSSignposter` intervals cover simulation steps, snapshot preparation and autosave for Instruments. Apple's [Metal tools](https://developer.apple.com/metal/tools/) and [Metal workload analysis](https://developer.apple.com/documentation/xcode/analyzing-your-metal-workload) informed the measurement-first approach. The implementation uses Metal/MetalKit, AppKit, SwiftUI, Foundation Models and C++/Clang; adopting a newer API name alone would not remove the observed CPU conversion bottleneck.

## Verified on October 2, 2026

- Universal macOS Release compile: arm64 + x86_64; final packaging verifies the extracted app's ad-hoc signature.
- Engine regression suite: 29 tests passed, including new compact ABI, photons/decorations, walls, coexistence, immutable frame and COW/RNG tests.
- Mac app suite: 16 tests passed (12 real-worker tests and 4 session lifecycle tests). Coverage includes command-order exports, imports and failures, stroke/history boundaries, pre-play Undo, bounds/Pan rejection, immutable retained frames, idle autosave, canceled-window drain, same-session restart and quit-save barriers.
- Native UI: painted 73,841 → 73,890 particles; Command-Z restored 73,841; Command-Shift-Z restored 73,890. Search found PLUT outside the Everyday filter and selection updated the brush. Inspector sampled Water at 20°C and cell 351,289. Playback ran to step 2,771 and paused.
- Native file panels: exported a version-3 `powder.upstream` document, then reopened it with 73,890 particles and step 2,771 preserved. No user autosave was overwritten during showcase UI checks.
- Scene generation popover and text entry were checked. No live cloud request was made.
- The exact packaged release launched and loaded the material study at 52,469 particles. A continuously updating inspector briefly prevented automation from settling; pausing resolved the observation delay, and native Command-Q exited normally. The final packaged release also quit cleanly during active playback and was relaunched in normal autosaving mode. Stack sampling showed SwiftUI layout activity, not a save deadlock.

Evidence: `evidence/mac-worker-tests-v5.log`, `evidence/engine-render-snapshot-tests.log`, `evidence/engine-render-snapshot-benchmark.json`, `evidence/mac-build-v5.log`, `evidence/mac-package-v5.log`, `evidence/mac-v5/`, and `evidence/rendering-v5/`.

The test build must specify `ARCHS=arm64 ONLY_ACTIVE_ARCH=YES` on this host: a host-only package test build otherwise tries to compile the app's Intel slice against missing Intel debug package modules. Release universal compilation uses both architectures. The first layer-sampling test fixture incorrectly attempted NEUT inside METL, which upstream creation rules reject; it was corrected to the existing supported PLUT/NEUT fixture. No simulation rule was changed to satisfy the test. XCTest logs also contain unrelated macOS automatic-shortcut service messages; all tests pass.

## Remaining limits

The simulation is still the original 2D Powder Toy world with 2.5D material lighting, not a volumetric 3D engine. Intel runtime/GPU behavior, long-duration RSS/thermal behavior, and complete VoiceOver canvas editing have not been measured. The build is locally ad-hoc signed, not distribution-signed or notarized. Existing source-preserved frontend gaps (region/stamp editing, full property editing, community services) remain. A brush stroke that hits only occupied cells can still create a no-op history checkpoint, as in the previous editor.
