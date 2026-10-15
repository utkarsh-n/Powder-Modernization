# Scene intelligence and Metal rendering in 0.3

For the current Mac-only 0.5.1 prompt interface and keyboard shortcuts, see the [floating prompt bar guide](Prompt-Bar-v5.1.md). Both providers remain available. The engine, model and rendering results below describe the 0.3 integration and are retained as historical evidence.

The native app's planners now target the original The Powder Toy v100.1.400 engine through `EngineKnowledge`, `EngineElement`, `AppleSceneLayout`, and `EngineScenes`. The runtime catalog contains 195 identifiers including `NONE`, rather than the 28 identifiers of the historical Swift prototype. Both paths produce declarative scene data and bounded drawing operations; neither can execute scripts, access local files, or invoke arbitrary tools through a scene plan.

| Path | Adapter behavior | Requirements and validation status |
| --- | --- | --- |
| On Device | Apple Foundation Models chooses a 2–8 component semantic composition; a native compiler creates the geometry; at most two attempts with validation feedback | macOS/iOS 26+, eligible hardware, Apple Intelligence enabled and model ready. Availability is checked at runtime. A real tank request passed the compact-layout path and a 45-tick engine check. A separate nuclear-scene request failed safely. Neither establishes arbitrary prompt reliability. |
| Cloud | OpenAI Responses API; full element descriptions and strict JSON Schema; configurable model ID | Network access, a compatible model and the user's API key stored in Keychain. Transport tests are simulated; no live cloud credential/request was available for this validation. |

The framework and response formats follow [Apple Foundation Models](https://developer.apple.com/documentation/foundationmodels) and [OpenAI Structured Outputs](https://developers.openai.com/api/docs/guides/structured-outputs). A model's structured response still requires application validation and may not satisfy the requested behavior.

## Grounding and construction

`EngineKnowledge` combines actual engine catalog metadata with selected causal rules. It distinguishes ordinary SPRK conductors from the `WIRE` cellular automaton, matter from energy occupancy, `PLUT` neutron interactions from `URAN` pressure heating, and element-specific uses of `life`, `tmp` and `ctype`. The catalog exposes the full element set; these concise rules are not an exhaustive specification of every interaction.

1. Pause the current experiment and capture its canvas size.
2. Send the prompt and engine-specific instructions to the selected provider.
3. Cloud generates a version-1 geometric `ScenePlan` directly. Apple generates an `AppleSceneDraft`: component materials, relative placement, shape/size, optional properties, desired container and intentional connections. `AppleSceneLayout` compiles that draft into the same plan format.
4. Validate the exact material codes, finite values, text limits, geometry, command count and raster workload.
5. Construct a separate, seeded `EngineWorld` on the original 612 × 384 canvas. Later commands replace their own occupancy layer; `NONE` erases matter and energy. Energy can coexist with matter.
6. Simulate 45 ticks on a copy and report changes and newly observed material types separately from the model's expectations.
7. Install the initial candidate, paused, as one undoable operation.

Shapes are rectangles, lines, circles and deterministic scatter regions, with coordinates normalized to 0–1. The shared validator accepts up to 128 commands, bounds radius to 0–0.25, temperature to −273–9725°C for this engine, and drawing work to 8 million estimated visits. Optional `ctype`, `life`, `tmp` and `tmp2` are validated element properties. Cloud plans can also supply bounded velocity components and local pressure; the current Apple generated type does not expose those three fields. JSON scene data is capped at 256 KiB, and cloud response envelopes at 2 MB. These are application bounds for a fictional sandbox, not physical units or safe real-world operating ranges.

The Apple path uses reusable layout rules rather than asking its small model to produce precise normalized geometry. It carves a hollow container, spaces same-row components, honors upper/middle/lower ordering, and creates touching traces only when requested by the draft. Its review requires each requested material to survive construction and limits matter occupancy to less than 55% of the canvas. It can ask the model for one corrected draft. The compiler does not inspect prompt keywords or substitute a preset scene.

This path deliberately handles small compositions of 2–8 components. Cloud retains direct geometric control. Neither a layout check nor the 45-tick trial proves arbitrary circuit connectivity, containment or machinery. The historical Swift prototype's battery-path assessment is not applied to the original engine, whose conduction rules differ. Some processes require longer trials, and model choices can still be wrong.

Cancellation discards pending results. Generation and trial failures preserve the current experiment. `ScenePlanInspector` presents construction steps, expectations, observations and warnings. The ideas menu fills the prompt only. `EngineScenes.demonstration()` is an authored launch example and is never returned in place of an AI result. The older `SceneFixtures` belong to prototype tests.

## Cloud request data

Cloud requests contain the prompt, canvas dimensions in the instructions, supported engine rules/catalog, and the scene schema. They do not attach saved experiments. The user's key is sent in the authorization header to the OpenAI Responses endpoint, not embedded in the prompt. Requests use an ephemeral URL session and set `store: false`; no claim of zero provider retention follows from that request field. The model ID is configurable, and service access/support remains subject to the account and selected model.

Injected-transport tests cover request construction, missing credentials, invalid inputs, HTTP errors, error/incomplete/refusal envelopes, malformed scene data, size bounds and cancellation. The current [17-test adapter run](../evidence/cloud-tests-v3.log) includes full-engine context injection and passed without real requests. The final [live Apple tank probe](../evidence/on-device-engine-v3-semantic-tank/on-device-engine-v3-summary.json) chose glass, water and sand in 9.869 seconds; the compiler emitted four commands for a hollow container and its contents. All 21335 particles survived 45 ticks, with sand moving downward from mean y96.06 to y193.62. Four [deterministic compiler checks](../evidence/apple-scene-layout-compiler-tests.log) independently cover spacing, container layout, an actual battery/conductor pulse and invalid input; they are not model-inference tests.

A [live PLUT/NEUT request](../evidence/on-device-engine-v3-semantic-particles/on-device-engine-v3-summary.json) did not produce an applied scene: its draft failed compilation and the model declined repair. The original nuclear engine's passing tests do not establish successful nuclear scene generation. Earlier failed coordinate-based probes remain in [Validation](Validation.md) as historical evidence.

## GPU presentation

`EngineWorld` runs original C++ particle, air and reaction code on the CPU. Newtonian gravity is also CPU code, using the portable pocketfft adapter. The Swift editor converts particle snapshots into per-cell albedo, emission, temperature, occupancy and liquid-refraction metadata for Metal. Energy particles remain visible when sharing a cell with matter. Photon display color is derived from its wavelength mask.

The renderer uses three protected resource slots. Compute passes shade particles, produce/downsample emission, apply horizontal and vertical Gaussian bloom, and composite a tonemapped image into an sRGB drawable. Cinematic mode adds surface shading, grain, glow and a screen-space liquid effect. Crisp mode uses nearest-neighbor sampling, while heat mode maps temperature independently of bloom. Quality presets adjust bloom resolution and blur radius. The native canvas also renders wall cells and saved sign text and supports Fit/2×/4× zoom with a Pan tool.

Simulation ticks drive visual animation, so pausing freezes procedural movement. A bitmap fallback handles unavailable Metal devices or renderer failures. The rendering menu identifies fallback use. This is a new visual interpretation: original element-specific drawing callbacks, decoration effects and every upstream display mode are not reproduced. The app does not use a GPU physics solver or ray tracing.

The production-metallib harness verified sRGB output, orientation, crisp sampling, bloom, heat isolation and odd-grid allocations on this Mac before the full engine integration. That shader check does not establish 0.3 UI correctness, frame rate, phone thermals or complete visual fidelity. [Validation](Validation.md) separates those results from engine and provider tests.

## Source ownership and license

The SwiftUI shell, scene adapters and Metal presentation surround reused GPL-covered upstream C++ code. The earlier statement that the original app was only a behavioral reference applies to the historical 0.1–0.2 prototype, not version 0.3. [Upstream provenance](../Native/Packages/PowderEngine/UPSTREAM.md), [GPL license](../Native/LICENSE), [third-party notices](../Native/THIRD_PARTY_NOTICES.md), and [historical fusion evidence](Upstream%20History.md) identify the source and local changes.
