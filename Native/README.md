# Powder for Mac 0.6.2

Version 0.6.2 adds a built-in scene builder and automatic fallback when a selected model declines, is unavailable or fails. Supported game material layouts remain usable without a model or API key; complex requests get concrete layout choices. Preview and confirmation still protect the current experiment. See the [fallback guide](../docs/Intelligence-v6.2.md).

Version 0.6.1 adds a native Icon Composer app icon: a glass chamber with amber powder, aqua water and a mint energy bead on graphite. Xcode compiles the layered icon and an older-macOS fallback. See the [icon design and integration notes](../docs/App-Icon-v6.1.md).

Version 0.6 adds a conversational scene assistant: resolve missing choices, inspect a separate preview and confirm before replacing the canvas. It includes thirteen linked community design references, more expressive native container layouts, and faster brush/inspection paths. See [the 0.6 guide](../docs/Intelligence-v6.md).

Every material and wall retains a matching colored SF Symbol: 194 materials, 19 walls, plus erase, with 214 distinct symbols. The same identities appear in the sidebar, search, current brush and inspector. Tints adapt to light/dark appearance and Increased Contrast while preserving material hue. See the [catalog and validation](../docs/Material-Symbols-v5.2.md).

Powder combines a macOS-only SwiftUI and AppKit interface with **The Powder Toy's original v100.1.400 C++ simulation engine**. The engine runs on the CPU; Metal provides the native visual presentation. This replaces the smaller original Swift simulation used in versions 0.1–0.2. That earlier engine remains in `PowderCore` for old native-document migration and its historical tests.

The pinned release contains **195 enabled element implementations**, including `NONE` and hidden/support states. The native palette exposes all **194 non-erase entries**; the upstream source marks 175 entries menu-visible. Some support states require element-specific properties or a mechanism to be useful; the count does not imply 194 independent paint-and-play systems. See the [complete inventory](../evidence/upstream-v100.1.400-elements.tsv).

Source is pinned to commit [`d768aeb89acad986bd252d7e904bf44bb374545f`](https://github.com/The-Powder-Toy/The-Powder-Toy/tree/d768aeb89acad986bd252d7e904bf44bb374545f), matching the supplied release. [Provenance and local modifications](Packages/PowderEngine/UPSTREAM.md), [LICENSE](LICENSE), and [third-party notices](THIRD_PARTY_NOTICES.md) accompany the reused source. This version contains upstream implementation code.

## Run and build

Open `Powder.xcodeproj` with Xcode whose SDK includes Foundation Models. Choose `PowderMac` for My Mac. The minimum deployment target is macOS 14. On-device generation additionally checks for macOS 26+, eligible Apple Intelligence hardware, enabled intelligence, and an available model. The active project has no iOS target; the earlier cross-platform source remains archived in the 0.4 source ZIP.

The Mac target includes arm64 and x86_64 in one universal binary. From this directory:

```sh
# Regenerate the project after changing project.yml or source membership.
xcodegen generate

swift test --package-path Packages/PowderEngine
swift test --package-path Packages/PowderCore
swift test --package-path Packages/PowderIntelligence

xcodebuild -project Powder.xcodeproj -scheme PowderMac -configuration Release \
  -destination 'generic/platform=macOS' -derivedDataPath DerivedData \
  CODE_SIGNING_ALLOWED=NO build

xcodebuild -project Powder.xcodeproj -scheme PowderMac -configuration Debug \
  -destination 'platform=macOS,arch=arm64' -derivedDataPath /private/tmp/powder-mac-tests \
  CODE_SIGNING_ALLOWED=NO ARCHS=arm64 ONLY_ACTIVE_ARCH=YES test
```

Package with `scripts/package-macos.sh`. It stages outside iCloud-managed Documents, signs the universal app locally, and verifies a clean extracted copy.

These are local development builds. Actual build, runtime, model and device results are recorded separately in [Validation](../docs/Validation.md).

## Engine capabilities and native controls

| Area | Included in 0.6 | Native interface boundary |
| --- | --- | --- |
| Element library | All enabled release elements, with original identifiers and callbacks | Searchable palette includes hidden/support entries; erase is a separate tool. |
| Matter and heat | Original powders, liquids, gases, combustion, phase transitions and reactions | Draw, erase, sample, adjustable brush, pause and single step; Fit/2×/4× zoom and a Pan tool. |
| Air and gravity | Original pressure/air fields and gravity modes; portable FFT Newtonian gravity | Newtonian gravity has a scene toggle. The palette includes 19 wall types with wall painting and rendering; fan-velocity and full field-tool editing remain future work. |
| Electronics and mechanisms | Original SPRK conduction, sensors, logic elements, cloning and mechanisms | Specialized particle properties are supported in scene plans/C API; read-only particle inspection is available; no complete property editor or mechanism editor yet. `WIRE` is Wireworld, not ordinary conducting wire. |
| Energy and nuclear elements | Original PHOT, NEUT, PROT, PLUT, URAN, DEUT, POLO, SING and related game reactions | Matter and energy retain separate occupancy layers. These are the game's rules, not scientific engineering models. |
| Portals, life and characters | Original callbacks and state remain in the core | Dedicated life-rule, character-keyboard and portal editing workflows are not fully implemented. |
| History and recovery | Copy-on-write worlds, bounded undo/redo, automatic recovery saves | Native editor snapshots preserve the tested future simulation state. |
| Scripting and community | Upstream source retained for provenance | Lua/SDL frontend, online accounts, save browser, comments, votes and uploads are not compiled into the native app. |
| Walls, signs and region editing | 19 wall types, wall brush/rendering and saved-sign display | Region selection, stamps, copy/paste, rotations, sign creation/editing and the full property/field editor remain future UI work. |

The Newtonian backend retains upstream convolution, masks and normalization while using the vendored header-only pocketfft implementation instead of a platform FFTW binary. It runs on the CPU and has independent force/mask tests. Full engine parity does not mean every original frontend feature is exposed.

**Legacy fusion side effects** is a separate, default-off scene option. It restores the historical O2 fusion singularity side product and low-pressure conversion of fusion-origin photons when they encounter hydrogen. The patch keeps modern limits and fixes the historical lifespan assignment to the wrong particle. Ordinary mode retains the modern reactions. The setting survives undo and native documents; unmodified upstream readers ignore the custom option. [Historical evidence and verified behavior](../docs/Upstream%20History.md) describe the exact scope.


## Native Mac workspace and performance

The window uses a resizable `NavigationSplitView` sidebar, native search and list selection, a unified toolbar, segmented Build/Run/Inspect modes, and an optional inspector. File, Edit, View, Simulation and Intelligence menu commands provide keyboard access. The interface follows the Mac’s light/dark appearance and accent color. The floating scene prompt bar is visible at the bottom of the canvas by default; File → Open Example loads the three authored scenes.

A background actor owns the C++ world. Painting, physics steps, undo checkpoints, decoding and autosave encoding execute in mailbox order. The main actor receives immutable frames and refreshes counters at most five times per second while playing. Paused idle sessions wait for work instead of polling. The simulation retains its existing 30 Hz cadence; this change does not silently speed up the game rules. macOS memory-pressure events trim historical worlds, and quitting waits for pending edits and the atomic autosave.

The Metal upload now carries one 16-byte cell buffer and a cached material table instead of three 16-byte grids. At 612 × 384 this reduces each frame’s grid upload from 10.76 MiB to 3.59 MiB. On the development Mac, CPU preparation of a controlled 222,200-particle frame measured 20.19 ms before and 0.69 ms after. These are extraction timings, not end-to-end FPS. See [engine measurements](../docs/Engine%20Performance.md) and [Mac validation](../docs/Mac-v5.md). The existing optical material families and analytical heat/crisp views are retained. Version 0.6 additionally avoids undo copies for rejected material strokes and uses direct wall inspection; [interaction benchmarks](../docs/Engine%20Interaction%20Performance.md) document those changes separately.

## Documents

The writer emits `.powderlab` JSON **version 3**, format `powder.upstream`, containing an original-engine OPS payload and engine version. The OPS parser and writer are upstream code. OPS preserves original particle fields and matter/energy overlap, but quantizes some values; a disk save/load is not a bit-identical checkpoint. In-memory undo clones use snapshots and additional engine state instead.

Earlier native versions 1 and 2 migrate onto the 612 × 384 canvas using explicit material aliases and cell temperature. This is a best-effort conversion into different simulation rules, not an exact replay of the old Swift engine. The native document reader bounds input to 32 MB; the C bridge separately bounds compressed and declared decompressed save data.

The engine and native reader accept OPS and legacy PSv/fuC data. The Open panel accepts `.powderlab`, `.cps` and `.stm`; broad real-world legacy-file coverage and that picker workflow still need validation. There is no community-service dependency for local documents.

## Scene intelligence

The floating bar uses native `regularMaterial` styling. Close it with **×**; the toolbar’s sparkle button or **⇧⌘G** shows and focuses it again. **⌥⌘P** toggles visibility and **⌘Return** sends a message. Hiding preserves the draft, conversation and current work. Stop cancels a request; late responses cannot replace a newer result. On Device, Cloud and Built-in are available from the provider menu. On Device uses the deterministic builder first for recognized simple material layouts; selected Cloud still uses the configured model first.

The assistant asks unresolved shape, material, arrangement or activation questions, remembers selected choices and accepts free-form corrections. A complete proposal creates a thumbnail and separate 45-step trial. **Confirm scene** places the initial state as one undoable edit. Draft changes must be sent or cleared before confirming, and canvas edits or playback during preparation require a replacement confirmation. Relevant community descriptions inform suggestions with visible source links; this is a curated local catalog, not live archive search or verified save reproduction. See [conversation behavior and evidence](../docs/Intelligence-v6.md).

Both planners receive the **full runtime engine catalog** and selected original-engine rules. Apple Foundation Models chooses up to eight semantic components, relative positions, a rectangular/circular/open-tank container, arrangement and intended connections; a native compiler turns those choices into a compact hollow layout. The OpenAI cloud adapter returns geometric commands directly with element descriptions and strict Structured Outputs. No authored fixture is substituted for a model response. The cloud path needs the user's API key in Keychain and a compatible model ID; no key is included in this repository.

A `ScenePlan` is bounded data: ordered rectangles, lines, circles and scatter regions, with element identifiers, temperatures and optional element properties. It cannot run code. Validation checks material names, geometry, finite values and drawing workload. A candidate is built separately, simulated for 45 ticks on a copy, and placed paused as one undoable edit only after confirmation. The interface distinguishes model expectations from observed changes. A valid plan or a short trial cannot establish that an arbitrary requested machine works.

[Scene intelligence and rendering](../docs/Intelligence%20and%20Rendering.md) documents provider differences, request data, limits and the visual pipeline. A real host on-device tank request generated a hollow container with sand above water; the particles remained finite and conserved through 45 ticks. This verifies one simple case. An earlier nuclear-scene request was declined by Apple; version 0.6.2 now routes provider failures into the built-in design flow. Complex or precise machinery is not guaranteed, and live cloud generation remains untested; see Validation and the 0.6.2 fallback guide for exact evidence.

## Code map

| Location | Responsibility |
| --- | --- |
| `Packages/PowderEngine` | Pinned C++ engine, C ABI, portable gravity, upstream saves, Swift `EngineWorld`, runtime catalog and scene compiler. |
| `Packages/PowderCore` | Shared `ScenePlan` validation/schema plus the historical original Swift engine and native-file reader. |
| `Packages/PowderIntelligence` | OpenAI request/response adapter with injected transport tests and caller-provided engine context. |
| `App/Intelligence` | Apple adapter, prompt UI, cancellation, trial observations and Keychain credentials. |
| `App/Rendering` | Metal shading, emission, bloom, heat/crisp presentation and bitmap fallback. |
| `App/PlaygroundSession.swift` | Main-actor UI state and an ordered command mailbox; graphics frames bypass SwiftUI observation. |
| `App/SimulationWorker.swift` | Background actor owning the mutable world, history, physics, compact snapshots and file encoding. |
| `App/WorkspaceView.swift`, `MaterialPalette.swift`, `SimulationCanvas.swift` | Native layout, palette and Mac pointer and trackpad interaction. |

Large scenes, simultaneous trials and undo copies have a substantial memory cost: one base world is about 24 MiB before FFT workspaces and rendering. Long-running RSS, thermal behavior, Intel GPU execution, and full VoiceOver canvas editing still need measurement. The earlier Swift prototype's speed measurements do not describe this engine.
