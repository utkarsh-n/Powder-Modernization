# Native macOS rendering and performance

The macOS renderer now accepts a compact snapshot directly from the original engine, uses an immutable material table, and receives frames through an AppKit `MTKView` without observing each simulation tick in SwiftUI. The material appearance from [Rendering v4](Rendering-v4.md), including the stronger nuclear halo, remains in place. The measured improvements are principally CPU preparation, upload cost and memory. GPU speed is not uniformly improved.

## Frame ownership and native presentation

[`EngineRenderSnapshot`](../Native/Packages/PowderEngine/Sources/PowderEngine/EngineRenderSnapshot.swift) owns immutable `Data`. The engine copies the visible grid, tick, counts and options under one lock; the renderer does not retain mutable engine storage. [`MetalFrame`](../Native/App/Rendering/MetalFrame.swift) accepts that data directly, avoiding per-particle Swift objects and three expanded per-cell arrays. This is one compact CPU snapshot followed by a copy into an available shared Metal upload buffer, not a zero-copy engine/GPU architecture.

Each cell has a fixed 16-byte layout:

| Offset | Field | Purpose |
|---|---|---|
| 0 | UInt32 RGB | Original element color or resolved PHOT spectrum |
| 4 | UInt32 ARGB | Decoration, retained separately for floating alpha blending |
| 8 | Float Celsius | Heat inspection and temperature-derived emission |
| 12 | UInt32 type and flags | Low 16 bits element ID; liquid, energy, wall and powered-wall bits |

Element ID 0 is empty; `0xFFFF` is the wall sentinel. A shared `MetalMaterialTable` supplies each element's surface parameters and visual family/emission. The pipeline uploads this table once per table identity. The shader applies decoration, wall checker shading, powered-wall glow and hot-material emission. The retained array-based `MetalFrame` initializer exists for controlled verification fixtures, not the app's frame path.

[`MetalFrameSource`](../Native/App/Rendering/MetalFrame.swift) is an ordinary main-actor object rather than an observable model. The background worker sends a completed frame to this stable mailbox, and the native [`MetalSimulationView`](../Native/App/Rendering/MetalSimulationView.swift) requests display directly. The source does not invalidate SwiftUI for each tick. The MTKView is input-transparent so that the canvas owns brush/pan gestures, and its representable removes subscriptions when dismantled.

The presenter keeps three reusable upload/resource slots and never blocks the UI thread waiting for the GPU. When all slots are occupied, it retains the newest frame and requests another draw after completion. CPU encode and GPU timestamp metrics are available on the non-observed source. Quality and size changes allocate matching resources; unchanged resources are reused.

## Measured CPU and memory changes

At the full 612×384 simulation grid, dynamic upload data fell from **11,280,384 bytes to 3,760,128 bytes**, a **66.7% reduction**. Three upload slots consequently use **10.758 MiB instead of 32.273 MiB**, saving **21.516 MiB**, excluding textures and the small immutable profile table.

The independent [engine extraction benchmark](../evidence/engine-render-snapshot-benchmark.json) measured the old Swift particle/array preparation against compact extraction in Release builds, alternating order for 30 samples per fixture:

| Particles | Old CPU preparation | Compact CPU preparation |
|---:|---:|---:|
| 20,200 | 1.922 ms | 0.123 ms |
| 101,000 | 9.222 ms | 0.364 ms |
| 222,200 | 20.189 ms | 0.691 ms |

These timings exclude simulation stepping, GPU work and UI presentation. See [Engine Performance](Engine%20Performance.md) for the extraction contract, tests and reproduction commands.

## Warm GPU and upload measurements

The untouched renderer's source, compiled shader and initial measurements were saved before editing in [`evidence/rendering-v5/baseline`](../evidence/rendering-v5/baseline). The final comparison uses the same controlled sparse/dense 612×384 fixtures, both 1280×800 and **2560×1600 Retina** drawables, and all three quality levels. Each case reuses its resources, warms for 32 frames, then records 96 sequential samples. An autorelease pool drains between cases. GPU times come from command-buffer timestamps; CPU encode times include the upload. There is no simulation, MTKView presentation, readback or app FPS measurement in this benchmark.

Balanced quality on **Apple M1 Max**:

| Scene / drawable | GPU median before → after | GPU p95 before → after | CPU encode median before → after |
|---|---:|---:|---:|
| Sparse, 1280×800 | 0.410 → 0.361 ms | 1.265 → 1.178 ms | 0.302 → 0.114 ms |
| Sparse, 2560×1600 | 0.792 → 0.733 ms | 1.375 → 1.157 ms | 0.307 → 0.133 ms |
| Dense, 1280×800 | 0.629 → 0.529 ms | 1.181 → 0.914 ms | 0.307 → 0.117 ms |
| Dense, 2560×1600 | 1.594 → 1.775 ms | 2.156 → 2.302 ms | 0.308 → 0.120 ms |

The dense Retina case has a **0.181 ms GPU regression**, while its CPU encode time falls by roughly **61%**. The per-case Metal allocation reported for balanced Retina rendering falls from **32.05 to 24.86 MiB**; this is one benchmark resource slot plus target/pipeline allocations, not the app's RSS. The three-slot savings above are the exact upload-buffer allocation calculation.

GPU clock state, scheduling and background workloads cause variation: the initial short run showed a GPU improvement that the longer comparison did not reproduce in every case. The raw [before](../evidence/rendering-v5/baseline/results-final.json), [after](../evidence/rendering-v5/compact/results-final.json) and [comparison](../evidence/rendering-v5/comparison.json) retain all quality cases. A tested texture-channel metadata cache was discarded after it failed to improve measured GPU time; the final shader uses the simpler direct profile lookup.

These results support the CPU/memory changes and establish a small GPU cost for the densest Retina case on this host. They do not establish an end-to-end frame rate or sustained thermal behavior. The separate simulation, UI and window compositor still contribute to frame pacing.

## Rendering verification and reproduction

The final production shader and shared encoder passed **82 assertions across 72 real GPU renders**, including finite HDR output, all 17 families, nuclear bloom, crisp sRGB accuracy, heat independence, surface parameters, resource clearing, odd sizes and boundary cells. New compact-path checks cover ABI strides, floating decoration blending, both wall checker phases, powered-wall glow, temperature-derived emission and bounded unknown-profile lookup. All 17 specimen PNGs were regenerated; the [contact sheet](../evidence/rendering-v5/compact/material-contact-sheet.png) was inspected visually.

The [GPU verification log](../evidence/rendering-v5/compact/gpu-verification.log), [machine-readable results](../evidence/rendering-v5/compact/results.json) and [source/library hashes](../evidence/rendering-v5/compact/source-sha256.txt) identify the tested result. `verified.metallib` is retained beside them. These checks ran offscreen and did not launch the app or access an autosave.

The reproducible tools are [`benchmark-rendering.swift`](../Native/scripts/benchmark-rendering.swift) and [`verify-material-rendering.swift`](../Native/scripts/verify-material-rendering.swift). Compile either with the production `MetalFrame.swift` and `MetalParticlePipeline.swift`, using Swift 6, `-O`, Metal and CoreGraphics. The verification harness additionally links ImageIO and UniformTypeIdentifiers. The shader is compiled with `-std=macos-metal2.4`. The benchmark accepts `metallib result.json label`; the verifier accepts `metallib evidence-directory specimen-directory`. Compiling the benchmark with the preserved baseline Swift files reproduces the previous architecture. [Rendering v4](Rendering-v4.md) records the host-specific Metal toolchain path and full build commands.

The app remains a conventional native Metal pipeline targeting macOS 14+ and a universal Mac build. This work does not adopt Metal 4 command APIs, neural rendering, MetalFX or ray tracing. Apple's [Metal 4 introduction](https://developer.apple.com/videos/play/wwdc2025/205/) describes a separate hardware/API boundary; Apple's [WWDC26 performance guidance](https://developer.apple.com/videos/play/wwdc2026/388/) supports measuring CPU/GPU timing and sustained sessions across actual devices. Intel GPU execution and sustained app performance have not been established by this M1 Max offscreen benchmark.
