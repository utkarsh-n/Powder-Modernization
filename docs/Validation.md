# Native validation record

This record distinguishes the **0.3 original-engine integration** from the earlier **0.1–0.2 Swift prototype**. Results were collected on October 2, 2026, on an Apple silicon Mac using Xcode beta. Package tests, compiled apps, interactive runtime checks and live model results are separate evidence. Authored scenes are not evidence of AI generation.

## Version 0.3: original engine integration

The original-engine package passed **24 tests, zero failures**, at 16:11:13 local time, with `swift test` exit 0 and 4.791 seconds elapsed for the test suite. The [archived log](../evidence/original-engine-tests.log) covers bridge validation, original reactions, walls/signs, document integration, snapshots and gravity. The package uses The Powder Toy v100.1.400, peeled commit `d768aeb89acad986bd252d7e904bf44bb374545f`; `c8be5165b7289706e17473bcfb38de112e78f140` is its annotated tag object, not the commit.

| Check | Verified result and scope |
| --- | --- |
| Original catalog | Runtime metadata includes all 195 enabled entries including NONE and hidden/support states. Native palette exposes 194 non-erase entries; upstream source marks 175 menu-visible. |
| Original reaction execution | PLUT and NEUT exercise actual upstream callbacks and change fuel in the integration test. SPRK transforms existing conductors without deleting them. This is game behavior. |
| Matter and energy | Scene construction and OPS round trips preserve the separate occupancy layers. Bridge tests cover stacked-particle erasing and deleting one layer without destroying the other. |
| Native documents | Version-3 wrapper round trips include OPS and the legacy setting. Earlier Swift documents migrate into the full canvas in the tested case. |
| Clone/undo | Snapshot clones retain tested future evolution, RNG/control state, pending gravity field, free-slot order and particle-map state. Editing/trial copies leave the original world intact. |
| Save and brush bounds | Malformed input and oversized declared OPS payloads reject without changing an existing world. Tests also cover invalid brush coordinates and invalid sign text. This is targeted validation, not a full parser fuzz campaign. |
| Walls and signs | The native source includes the 19-wall catalog, wall brush/rendering and saved-sign display. Package tests cover wall/sign state and saves; native palette visibility was checked in the simulator. |
| Newtonian gravity | Disabled state yields zero force; positive/negative sources attract/repel with the tested inverse-square strength. Clone and OPS tests retain the relevant setting/field. |
| Legacy fusion | Default off; clone/OPS persistence and targeted reaction regressions pass. Separate harness results are below. |
| Universal Mac Release and runtime | Universal Release build passed; [mac-build-v3.log](../evidence/mac-build-v3.log). Native runtime checks confirmed the 194-entry library, PLUT/URAN category entries, both gravity/fusion menus, 2× zoom and Metal GPU status without fallback. |
| Signed iPhone simulator | A normally signed build under `/private/tmp/powder-ios-v3` built, installed and launched. Play/Pause, Heat/Metal, PLUT search/selection and the collapsed 19-wall palette were checked. Intelligence settings no longer showed Keychain error `-34018`. [Workspace](../evidence/iphone-v3-workspace.jpg) and [PLUT selection](../evidence/iphone-v3-plutonium.jpg) are retained. |
| Generic iOS device Release | Compile/link passed with signing disabled; [ios-device-build-v3.log](../evidence/ios-device-build-v3.log). This was not installed on physical hardware. |
| Cloud adapter | [17 transport-injected tests](../evidence/cloud-tests-v3.log) passed at 15:51:07, including full-engine context injection. No live cloud request was run: a credential was unavailable. |
| Shared scene validation | [46 core tests](../evidence/core-tests-v3.log) passed at 16:11:10, including seven new tests for extended particle fields, exact catalog/schema handling, optional/null compatibility, numeric bounds and nonfinite rejection. |
| Live Apple generation | The final semantic tank request passed: a real model draft compiled to a hollow four-command layout and ran 45 finite, particle-conserving ticks. A separate nuclear request failed safely without an applied world. Details below. |
| Physical devices | No 0.3 run on a physical iPhone, iPad or Intel Mac is established. |

OPS uses upstream quantization for position, velocity, temperature and air data. A disk round trip is therefore not asserted to preserve bit-identical future evolution. In-memory snapshot cloning has separate exact-evolution tests.

### Historical fusion regression

The [real-engine harness log](../evidence/legacy-fusion-tests.log) records 256 matched random seeds: 51 O2 fusion events in each mode, 20 legacy singularities, and none in modern mode. It checks singularity temperature/lifespan, the intentional correction of the source-particle lifespan bug, tagged photon conversion at pressure 0/44.99/45/100, unchanged ordinary-photon reactions, four active-grid corners, and a full 235008-particle pool. Settings survive clones and OPS in both modes.

A separately linked, unmodified pinned-release O2 implementation produces the same modern-mode state/RNG fingerprint `f0e27add85a3bc3b`. These tests use real production reaction callbacks with controlled force/pressure, rather than a substitute physics implementation. They isolate reaction behavior; they do not test UI controls. See [source history](Upstream%20History.md).

### Portable Newtonian solver

The [standalone gravity log](../evidence/portable-gravity-validation.log) records 238 comparisons against direct force evaluation with maximum absolute error `4.42998e-08`, plus passing source/output-mask tests. Its optimized host benchmark ran 240 recalculations on a padded 306 × 192 transform grid in 138.293 ms, or **0.576219 ms per recalculation**. This excludes particle simulation, rendering and UI; it is not an iPhone frame-time measurement. The reproducible harness is [portable-gravity-math.cpp](../evidence/portable-gravity-math.cpp).

The backend uses pocketfft revision `c90e55b3d529f8efa40ed01a20de22405f45fc65` and retains upstream convolution/masking/normalization. It avoids a platform FFTW runtime. See [dependency notice](../Native/Packages/PowderEngine/Sources/CBridge/PocketFFT/NOTICE.md).

### Memory and remaining runtime checks

The [static memory accounting](../evidence/original-engine-memory.json) estimates **24.054 MiB per base world**, before approximately 2–3 MiB of enabled FFT workspace, frame buffers and native UI. Undo history, a generated candidate and its trial can each retain additional worlds. This is a structure/allocation estimate, not measured peak resident memory. Physical-device profiling, long-running memory/thermal behavior, frame pacing, input responsiveness and full accessibility remain open.

The C save bridge and native reader include OPS/PSv/fuC routing, and the Open panel accepts `.powderlab`, `.cps` and `.stm`. The picker workflow and broad real-world legacy-save coverage are not yet validated. The shell includes 19 wall brushes, saved-sign display, Fit/2×/4× zoom, a Pan tool and the Newtonian toggle. Online saves, Lua, region stamps, character controls, sign editing, fan-velocity controls and a complete particle/field-property editor remain outside its present scope.

### Final live Apple composition and independent compiler checks

The [final semantic tank probe](../evidence/on-device-engine-v3-semantic-tank/on-device-engine-v3-summary.json) ran on the host at 21:06:58 UTC. The real model selected a glass container, water in the middle and sand above it, on the first draft in **9.869 seconds**. The native layout compiler produced four operations: GLAS shell, NONE interior, water and sand. It did not substitute an authored fixture. All **21335 particles** remained present and finite through 45 original-engine ticks. Mean sand y increased from **96.06 to 193.62**, while water moved from 195.50 to 237.35. The recorded 45-tick simulation took 0.948 seconds on the host; this is not a phone performance measurement.

Four [deterministic compiler verification groups](../evidence/apple-scene-layout-compiler-tests.log) passed separately: hollow/falling layout, eight-component packing, actual BTRY-to-METL conduction and invalid-input rejection. These checks use synthetic compiler input and are distinct from real model inference.

A [separate live PLUT/NEUT request](../evidence/on-device-engine-v3-semantic-particles/on-device-engine-v3-summary.json) failed: the first composition had an invalid connection, and the model declined repair. No world was applied. The passing manual nuclear engine test must not be described as successful nuclear prompt generation. The Apple path targets compact compositions of 2–8 components; one successful tank is not a guarantee of arbitrary machinery or general prompt reliability. Cloud inference remains untested without a credential.

### Earlier 0.3 coordinate-based probe: retained failure

The [0.3 tank probe](../evidence/on-device-engine-v3-tank/on-device-engine-v3-summary.json) used the host's available Apple model at 20:51:46 UTC. It generated six commands in 23.270 seconds, passed structural validation and built a 216384-particle world; 45 engine ticks ran in 5.654 seconds. Particle values remained finite. The [actual plan](../evidence/on-device-engine-v3-tank/on-device-engine-v3-plan.json) and resulting native document are retained alongside the summary.

This does **not** verify the requested “sand above water, room to fall” layout. Initially, mean sand y was 304.75 and mean water y was 239.16, so sand started lower on the screen. Glass occupied 151817 cells, about 65% of the full canvas. Sand count decreased from 23057 to 21304 by tick 45. The evidence establishes real model generation and engine execution while exposing a scene-quality failure; it does not establish successful requested behavior or a phone inference benchmark.

### Reproduction

From `Native`, run `swift test --package-path Packages/PowderEngine --scratch-path /private/tmp/powder-engine-build`. The final shared-core check used `swift test --package-path Native/Packages/PowderCore --scratch-path /private/tmp/powder-core-final-build --cache-path /private/tmp/powder-core-final-cache --disable-sandbox` from the project root, with writable module caches. In restricted environments the recorded runs used writable module/package caches and disabled the nested SwiftPM sandbox where necessary. From the project root, `python3 scripts/run-legacy-fusion-check.py /private/tmp/powder-engine-build` links the regression against those completed macOS CBridge/JsonCpp build objects and compares modern O2 to the pinned reference source.

The successful simulator build kept normal ad-hoc signing enabled and used a `/private/tmp` DerivedData directory. Earlier builds in Documents acquired FinderInfo metadata that invalidated signing, and disabling signing caused Keychain error `-34018`. [README build instructions](../Native/README.md) reflect the working configuration.


### Final packaged build

The final universal Mac ZIP was extracted into a clean local temporary directory, passed `codesign --verify --deep --strict`, and launched successfully. Its runtime palette showed 194 materials, 19 wall types, and nuclear search results including PLUT, URAN, NEUT, DEUT and SING; it restored the existing 18,432-particle experiment. Both x86_64 and arm64 slices are present. [Artifact checksums](../evidence/final-artifacts-v3.json) and the [final signed simulator build/run result](../evidence/ios-simulator-build-v3.json) are retained.

The app has local ad-hoc signing, without distribution signing or notarization. This workspace's iCloud-managed Documents folder automatically attaches FinderInfo to `.app` directories, so the loose copies there fail a strict signature check. The ZIP was produced from a clean staging copy and independently verified after extraction; extract it into a local folder such as Downloads.

## Historical version 0.2: Metal and live model probes

The [production-metallib check](../evidence/metal-pipeline-harness.log) passed on Apple M1 Max: shading, sRGB color/orientation, crisp sampling, bloom halo, heat isolation and odd-grid allocations. It used a 17 × 13 grid and a 136 × 104 render target. This is offscreen shader execution; it excludes MTKView lifecycle, resize callbacks, fallback UI and full-engine/device performance. The [Mac v0.2 build](../evidence/mac-build-v2.log) is retained separately from the 0.3 build.

Historical Apple-model probes did run on the host, but do not establish successful arbitrary generation: the [electrical-scene attempt](../evidence/on-device-scene-summary.json) was declined, and the [terrarium attempt](../evidence/on-device-terrarium/on-device-scene-summary.json) failed that earlier provider's validation. The 0.3 catalog and review implementation differ. No fixture or failed model attempt is recorded as a successful live scene.

## Historical version 0.2: original Swift engine and scene planner

The expanded core run completed at 15:10:36 with `swift test` exit 0: **39 tests, zero failures, 3.454 seconds**. This includes 12 original world tests, 12 expanded physics tests, and 15 scene-plan tests. The archived record is [core-tests-v2.log](../evidence/core-tests-v2.log).

The archived cloud-adapter run completed at 15:16:30 with **16 tests and zero failures**, exit 0. Those tests use injected HTTP responses, never credentials or real requests. The log is [cloud-tests-v2.log](../evidence/cloud-tests-v2.log). This run predates full-engine context injection; it is historical adapter evidence, not a live 0.3 model result.

| Check | Verified result |
| --- | --- |
| Existing simulation behavior | Original motion, conservation, deterministic RNG, heat, quenching, acid, bounds, and document tests still pass. |
| Electrical propagation | A pulse travels one conductor per tick, has an active and recovery period, heats its conductor, and does not jump an empty gap. |
| Battery to fuse to blast | A battery, six wire cells, seven fuse cells, and a fixed explosive trigger a blast within the test window; adjacent glass breaks and pressure exceeds 100 simulation units. |
| Destructive explosions | Blast displaces sand, breaks brick, heats nearby charges, and produces nonzero air velocity. |
| Plant behavior | Seeds germinate with water; plants consume water to grow and stop growing when no water remains. |
| Salt chemistry | Salt dissolves, salt water carries an electrical pulse, and boiling releases steam while leaving salt. |
| Thermite | Sustained combustion heats above 2000°C, melts adjacent metal, and ends as lava. Temperatures are sandbox values, not a scientific measurement. |
| Save compatibility | Version 1 loads with an initially resting air field. Version 2 restores the air field, circuit state, RNG, and subsequent evolution exactly in the tested scenario. |
| Numeric bounds | Blast stress remains finite and within the engine's pressure, velocity, and temperature limits. Invalid air data is rejected. |
| Declarative scene plans | Bounds, material names, command count, schema, shape rasterization, overwrite behavior, deterministic scatter, empty scenes, and excessive drawing workloads are tested. |
| Authored reaction fixtures | A battery/wire/fuse fixture consumes its charge within 180 ticks at 64 × 48; a terrarium fixture germinates within 20 ticks. These are authored fixtures. |
| Connectivity assessment | Disconnected paths are reported. A battery directly touching a fuse is correctly rejected as a powered conductor path. |
| Cloud adapter with simulated transport | Strict schema and `store: false` requests, invalid prompt/model/key, HTTP errors, error envelopes, incomplete output, refusal, invalid scene data, response size, transport failure, and cancellation before/after transport are tested. |

No live Apple or cloud model result is established by this package run. No claim about the new Metal renderer's runtime correctness, visual quality, or GPU performance follows from these CPU tests. Current app builds and visual/model checks should be recorded separately after they run; the earlier app results are preserved below as historical evidence.

### Expanded simulation timing

The expanded engine benchmark ran 600 steps after 60 warmup steps using `swiftc -O`, with exit 0. The captured log is [core-benchmark-v2.log](../evidence/core-benchmark-v2.log).

| Grid | Particles in the demo | Mean simulation step |
| --- | ---: | ---: |
| 240 × 160 | 7,927 | 2.213 ms |
| 180 × 260 | 9,037 | 2.606 ms |

These measurements include CPU heat, motion, electrical-state scanning, and the air-field update. The benchmark scene is the standard sand/water/oil demo; it is not a worst-case chain-explosion benchmark. Measurements exclude frame preparation, Metal rendering, model inference, and UI work. They do not establish iPhone frame rate, thermal behavior, or battery use.

Reproduce from `Native/Packages/PowderCore`:

```sh
CLANG_MODULE_CACHE_PATH=/private/tmp/powder-clang-cache \
SWIFT_MODULECACHE_PATH=/private/tmp/powder-swift-cache \
swift test --scratch-path /private/tmp/powder-core-build \
  --cache-path /private/tmp/powder-package-cache

swiftc -O Sources/PowderCore/Material.swift Sources/PowderCore/World.swift \
  Benchmarks/main.swift -o /private/tmp/powder-core-expanded-benchmark
/private/tmp/powder-core-expanded-benchmark
```

SwiftPM's nested sandbox was unavailable inside the agent sandbox. The successful test run used approved execution outside that nested restriction and temporary build/module caches.

### Capability boundaries

The engine currently exposes 27 paintable materials plus erase. Its electrical system is a pulse network, not a voltage/current solver. The 4 × 4 coarse air cells use bounded, damped pressure and velocity updates; particle movement respects occupied cells, but the air field does not solve detailed wall boundary conditions. Heat, combustion, explosions, plant growth, and material changes are local sandbox rules.

The scene-plan validator establishes bounded data and a constructible grid. Static connectivity assessment and a short trial can identify some issues and report observations, but do not verify arbitrary user intent. Forty-five trial ticks are insufficient for many long electrical/fuse paths. A model can still produce a valid plan with ineffective geometry or unsupported expectations. The cloud adapter's injected-response tests cover invalid credentials, refusals, and cancellation at the transport boundary. Actual service responses, live inference, cancellation during Apple inference and the app's trial phase, and end-to-end generated scene quality remain separate checks unless explicitly recorded later.

## Historical version 0.1: original Swift prototype

Verified on October 2, 2026, using Xcode beta on an Apple silicon Mac. These checks apply to the new first-principles Swift app, not the supplied Intel reference application.

| Check | Result |
| --- | --- |
| Universal macOS Release build | Passed, xcodebuild exit 0. `file` confirms both arm64 and x86_64 in the packaged executable. |
| iOS Simulator Debug build and launch | Passed on the booted iPhone 17 Pro simulator with iOS 27.0. Final build and launch completed successfully. |
| iOS device Release build | Passed, xcodebuild exit 0, signing disabled for compile validation. Not installed on a physical iPhone. |
| Engine unit tests | 12 tests, 0 failures, 1.316 seconds; swift test exit 0. |
| Mac playback | Play and pause change the live canvas; 598 steps observed, with sand settling through water. |
| Mac drawing and history | Paused brush stroke increased occupied cells from 7,927 to 8,334. Undo restored 7,927; redo restored the edited scene. |
| Mac file export | Native export panel opened. The resulting `.powderlab` file decoded as version 1, 240 × 160, tick 598, 38,400 cells and 8,334 occupied cells. |
| iPhone playback and palette | Play/pause verified; material sheet search found Fire and selecting it updated the active brush. |
| iPhone touch input | Dragging painted a fire stroke; occupied cells increased from 9,037 to 10,153. |
| iPhone recovery | Final rebuilt app restored the edited scene after install and relaunch. |

Build logs are saved in [evidence](../evidence/): `mac-build.log`, `ios-device-build.log`, and `ios-simulator-build.log`. The build emits an informational App Intents metadata warning because this app does not declare App Intents. The earlier iPad orientation warning was resolved by declaring all iPad orientations.

![Native iPhone workspace after recovery](../evidence/iphone-native.jpg)

### Version 0.1 Swift engine tests and timing

Tests cover gravity and density displacement, particle conservation, deterministic evolution, heat and phase transitions, fire and water interactions, acid, brush bounds, malformed documents, and save restoration including future RNG evolution. Test and benchmark output was captured in the task tool results rather than a separate stdout file.

The test command ran from `Native/Packages/PowderCore`:

```sh
CLANG_MODULE_CACHE_PATH=/private/tmp/powder-clang-cache \
SWIFT_MODULECACHE_PATH=/private/tmp/powder-swift-cache \
swift test --scratch-path /private/tmp/powder-core-build \
  --cache-path /private/tmp/powder-package-cache
```

The new engine benchmark measured 600 steps after 60 warmup steps in an optimized build:

| Grid | Mean simulation step |
| --- | ---: |
| 240 × 160 | 1.527 ms |
| 180 × 260 | 1.779 ms |

These are measurements on this Mac and exclude bitmap generation and UI rendering. They do not establish an iPhone frame rate, thermal budget, or battery impact. Reproduce with `Native/Packages/PowderCore/Benchmarks/main.swift`.

### Original review fixes

The Mac app uses one workspace window so multiple sessions cannot overwrite one recovery file. Playback invalidates stale redo history after an undo. Gesture cancellation and app lifecycle changes terminate a brush stroke so the next touch does not connect to an earlier stroke.

### Original remaining validation

The Intel slice was compiled but not run on an Intel Mac. No physical iPhone or iPad validation was performed. Landscape, large Dynamic Type, full VoiceOver editing, long-running memory/thermal behavior, and broad document fuzzing remain open. Legacy `.cps` and `.stm` import is not implemented. The binaries are local development builds, without distribution signing or notarization.

## Native 0.4 · October 2, 2026

The combined workbench design is implemented in native SwiftUI for Mac and iPhone. The actual MTKView renderer now uses the same shared MetalParticlePipeline as the material specimen exporter and offscreen GPU harness. Rendering, classification and UI changes are isolated from the vendored simulation physics.

- Universal Release Mac build: passed, arm64 + x86_64.
- iPhone Simulator Debug build and launch: passed on iPhone 17 Pro / iOS 27.
- Generic physical iOS Release compilation: passed; no device signing/deployment performed.
- Final Apple M1 Max GPU verification: 74 assertions / 65 renders, all passed. Nuclear emission, finite HDR, all17 families, resource reuse/clear, crisp/heat modes and boundary cases verified.
- Final shader SHA256: `248a8140763b2e3cad8727e73d008fc9851a9c8cd60572c2fdf706b7ca145891`.
- Exact painting/undo/redo counts, Pan→Inspect selection, temperature view, scene switching and a >9,000-step Mac run inspected live. iPhone library search and selection, complete Build drawer and paused Run entry inspected live.
- Release ZIP was extracted to a fresh temporary directory, passed strict codesign verification and launched with the correct new UI and resources.

See `Native/design-qa.md` for visual comparison and coverage limits. See `docs/Rendering-v4.md` for Apple's current guidance, rendering implementation and GPU evidence. Engine/Core/Intelligence regression suites from 0.3 were not rerun for this UI/rendering-only change; their earlier results remain separate historical evidence. The 17e first-boot UI automation timed out; iPhone17Pro provided the successful simulator checks. Active simulation's changing UI can prevent the automation snapshot from settling; no live-phone FPS claim is made.

## Native 0.5 · Mac-only workspace and background simulation

The active target is macOS-only, with a native split-view sidebar, unified toolbar, inspector and menu commands. The immutable compact render path removes per-particle Swift conversion from each frame and runs engine work off the main actor.

The full engine suite passes 29 tests. The new Mac app suite passes 16 worker/session tests, including idle autosave, window-close drain, wake-stream restart and quit-save ordering. Native painting/history, material search/selection, inspection, playback and file export/import were exercised. Exact measurements, implementation, evidence and validation limits are recorded in [Mac v5](Mac-v5.md), [Engine Performance](Engine%20Performance.md) and [Rendering v5](Rendering-v5.md). Earlier iOS results above are historical; there is no active iOS app target in 0.5.
