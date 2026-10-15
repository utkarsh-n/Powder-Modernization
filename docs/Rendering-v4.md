# Material rendering verification

Powder keeps the original two-dimensional CPU simulation and presents its cells through a native Metal renderer. The material pass adds surface shape, reflection, transmission and emitted light; it does not change particle collisions, chemistry or heat transfer. SwiftUI supplies the workbench and controls. This document distinguishes the graphics techniques actually used from newer Apple APIs reviewed for future work.

## Apple guidance and implementation choices

Apple describes roughness, metallic response, normal information and emission as separate material properties. Powder follows these parameter meanings in its own Metal shaders: water and glass transmit more background, metal reflects a stronger directional highlight, and powder, wood and organic matter use different surface detail. These are deliberate approximations for a flat simulation. Powder does not use RealityKit, volumetric glass, a three-dimensional scene, or physically measured material constants. [Apple PhysicallyBasedMaterial documentation](https://developer.apple.com/documentation/realitykit/physicallybasedmaterial).

Lighting and bloom operate on linear values in `rgba16Float` textures. The final `bgra8Unorm_srgb` target performs the linear-to-sRGB conversion. A known-color readback test checks this path so that gamma is not applied twice. [Apple sRGB pixel format documentation](https://developer.apple.com/documentation/metal/mtlpixelformat/bgra8unorm_srgb).

WWDC25 introduced Metal 4's new command structure and explicit memory management on M1/A14 and newer hardware. Powder retains conventional Metal command queues and compute/render encoders, which also accommodate the app's Intel Mac target. Shader language syntax, a new Xcode compiler and the Metal 4 command API are separate choices. No Metal 4 command allocator, argument table or machine-learning encoder is used here. [Discover Metal 4](https://developer.apple.com/videos/play/wwdc2025/205/), [Metal feature tables](https://developer.apple.com/metal/feature-sets/), [Metal language reference resources](https://developer.apple.com/metal/resources/).

WWDC26 describes neural rendering through MetalFX, Metal 4 machine-learning commands and inline TensorOps. Those techniques require additional models, supported hardware and integration. They are not part of Powder's renderer, and the current material effects do not need them. [Build real-time neural rendering pipelines with Metal](https://developer.apple.com/videos/play/wwdc2026/359/).

Apple's WWDC26 performance workflow measures CPU/GPU timing and frame pacing across devices and sustained sessions, including changing thermal conditions. The newer `metalperftrace` and StateReporting workflows described there target macOS/iOS 27. The practical lesson for this app is to profile occupied-cell count, drawable resolution, zoom and bloom quality together. An offscreen correctness check cannot establish smooth app interaction, sustained battery use or performance on a physical iPhone. [Find and fix performance issues in your Metal games](https://developer.apple.com/videos/play/wwdc2026/388/).

## Production data contract

[`MetalFrame.swift`](../Native/App/Rendering/MetalFrame.swift) carries three row-major arrays: sRGB albedo plus emission, Celsius temperature plus material family/occupancy/refraction, and optional roughness/metalness/transmission/relief. The surface array can be omitted to select shader defaults. Each occupied cell remains part of the original simulation grid. The tick drives procedural animation; holding the tick still keeps paused materials stable.

[`MetalParticlePipeline.swift`](../Native/App/Rendering/MetalParticlePipeline.swift) is shared by the app and the offscreen test. Its compute passes prepare the linear material and emission fields and filter bloom. The fragment pass evaluates material relief at drawable resolution. Crisp and Heat remain inspection modes, with heat independent of cinematic relief and bloom. Intermediate resources are private Metal textures; explicit blits provide test readback after command completion.

The 17 visual families are generic, powder, water, stone/wall, wood, flame, gas, steam, oil, acid, ice, lava, metal, glass, organic, nuclear fuel and energy. A family describes appearance; it is not a replacement for the engine's individual elements. In particular, the nuclear glow is a visualization choice and not a physical prediction of visible radiation.

Cinematic presentation includes a teal water tint, warmer wood reflectance, subdued leaf greens and a lifted metal reflectance. The input palette remains the upstream palette; these appearance adjustments run after the Crisp and Heat branches. Original cell colors remain available in Crisp. Grain positions and sizes vary deterministically within the visual surface without moving the underlying simulation particles.

## Reproducible GPU checks

[`verify-material-rendering.swift`](../Native/scripts/verify-material-rendering.swift) compiles together with the production frame and encoder. It loads a freshly compiled production `ParticleShaders.metal` library, performs actual GPU work, reads back the scene/emission half-float textures and the final sRGB pixels, and exports PNG specimens. It neither launches the app nor accesses an autosave.

From `Native`, with a Metal compiler installed and discoverable by Xcode:

```sh
mkdir -p /private/tmp/powder-rendering-v4
xcrun -sdk macosx metal -std=macos-metal2.4 -fmodules-cache-path=/private/tmp/powder-rendering-v4/metal-cache -c App/Rendering/ParticleShaders.metal -o /private/tmp/powder-rendering-v4/ParticleShaders.air
xcrun -sdk macosx metallib /private/tmp/powder-rendering-v4/ParticleShaders.air -o /private/tmp/powder-rendering-v4/default.metallib
xcrun swiftc -swift-version 6 -parse-as-library -framework Metal -framework CoreGraphics -framework ImageIO -framework UniformTypeIdentifiers -module-cache-path /private/tmp/powder-rendering-v4/module-cache App/Rendering/MetalFrame.swift App/Rendering/MetalParticlePipeline.swift scripts/verify-material-rendering.swift -o /private/tmp/powder-rendering-v4/verify-material-rendering
/private/tmp/powder-rendering-v4/verify-material-rendering /private/tmp/powder-rendering-v4/default.metallib ../evidence/rendering-v4 App/Resources/Specimens
```

On this host `xcrun` could not resolve the installed Metal compiler. The verified compile used `/var/run/com.apple.security.cryptexd/mnt/com.apple.MobileAsset.MetalToolchain-v27.1.5194.15.TLP3r7/Metal.xctoolchain/usr/bin/metal` with `-std=macos-metal2.4` and a writable `-fmodules-cache-path=/private/tmp/powder-rendering-v4/metal-cache`; `metallib` came from the same directory. That mounted path is host-specific. The language target is Metal 2.4, not a claim of Metal 4 API adoption.

The checks cover all families, finite HDR fields, emission boundaries, equal-albedo family differentiation, roughness/metalness/transmission controls, exact crisp colors, heat independence, nuclear bloom, paused determinism, animation, odd grid/drawable sizes, occupied corners and malformed-array rejection. They also cover a 1×1 scene with shader-default surface parameters, nonfinite optional surface values falling back to finite defaults, and isolated powder/water/metal/glass particles at every grid boundary. Reusing previously emissive resources for an empty frame must match fresh empty resources exactly. Solid glass must remain still when the tick advances. The harness fails explicitly when its process cannot access a Metal device.

Specimens use controlled shapes and original element palette colors, rendered by the production shader at 256×256. Explicit surface parameters match `MaterialVisualProfile`, including the METL roughness override, and liquid flags match the app's frame assembly. They are material illustrations, not simulated reaction results or photographs. Their contact sheet order and per-family provenance are recorded in `results.json`. A shared family specimen is not an individual preview of every element or its decoration.

## Verified result

On October 2, 2026, the final harness completed **74 assertions and 65 offscreen renders on Apple M1 Max**, exiting successfully after the material polish pass and the final nuclear radiance adjustment. All 17 specimens were exported to [`Native/App/Resources/Specimens`](../Native/App/Resources/Specimens). The test process required access outside the execution sandbox because the sandbox exposed no Metal device. This did not require launching the app or touching a saved simulation.

Evidence is preserved in [`gpu-verification.log`](../evidence/rendering-v4/gpu-verification.log), [`results.json`](../evidence/rendering-v4/results.json), the [contact sheet](../evidence/rendering-v4/material-contact-sheet.png), [crisp output](../evidence/rendering-v4/crisp.png), [heat output](../evidence/rendering-v4/heat.png), and the [nuclear bloom comparison](../evidence/rendering-v4/nuclear-bloom.png). The [source and compiled library hashes](../evidence/rendering-v4/source-sha256.txt) identify the tested implementation; its compiled library is retained as `verified.metallib` beside the evidence.

Visual inspection of the final contact sheet confirmed irregular golden sand grains, continuous teal water with surface highlights, warmer wood grain, brighter brushed metal, leaf detail and emissive flame/energy. Glass has a restrained diagonal studio reflection over its dark transmitted substrate; transmission also changes measured pixels. This is screen-space transmission and procedural studio lighting, not ray-traced refraction or reflection of a complete scene.

The final nuclear pass normalizes emitted hue independently of dark palette brightness, while keeping base albedo and the Crisp/Heat branches unchanged. With the PLUT profile's emission intensity of 0.7, measured peak linear radiance increased from **0.108154 to 0.800781**, a **7.404×** increase; a separate readback assertion confirms the requested 0.7–1.0 range. The [comparison receipt](../evidence/rendering-v4/nuclear-radiance-comparison.json) and [prior measurements](../evidence/rendering-v4/pre-nuclear-normalization/results.json) preserve that change. Visual inspection of the regenerated [nuclear specimen](../Native/App/Resources/Specimens/Specimen-nuclear.png) confirms a visible green halo. This remains an artistic radioactive-material effect, not a physical radiation model.

These results cover the shared production encoder and shaders with synthetic fixtures. They do not establish MTKView resize/lifecycle behavior, full-app frame rate, thermal performance, Intel GPU behavior, physical iPhone rendering or the correctness of a simulated reaction. Those require separate application and device testing.
