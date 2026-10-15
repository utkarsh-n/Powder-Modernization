# Apple scene layout geometry

`AppleSceneLayout` compiles the model's semantic draft into bounded original-engine drawing instructions. It does not inspect the user's prompt to choose canned content. The conversation layer provides a confirmed brief; `AppleScenePlanner` carries that brief, including shape, material and layout choices, into both the first attempt and any validation repair.

The draft now has two explicit fields with source-compatible initializer defaults:

- `containerShape`: `rectangular` (closed four-sided chamber), `circular` (closed round vessel), or `openTank` (two sides and floor). Default: rectangular. The field is ignored when `containerMaterial` is NONE.
- `composition`: `balanced`, `compact`, `spacious`, or `layered`. These change spacing and, for layered powders/liquids, width and depth. They preserve the selected materials, causal order, and upper/middle/lower relationships. Default: balanced.

One through eight requested components are accepted. Zero is accepted only with a real solid container, permitting an intentionally empty vessel without invented filler. Zero components with NONE, unsupported materials, non-solid container materials, invalid numeric settings, excessive components, and a first component that claims to connect to a predecessor are rejected.

Rectangular containers draw four wall rectangles directly. Open tanks draw three. No filled interior needs to be erased. Circular containers use a closed 64-segment thick polyline in pixel coordinates, preserving a physically round shape on the 612 × 384 canvas. This works within the existing plan radius and command-count limits. Its contents and orthogonal connections fit inside an inset inscribed rectangle, leaving room so raster rounding cannot overwrite the shell. The existing engine review still checks requested material presence and crowding.

## Verification

`Native/scripts/verify-apple-scene-layout.swift` passed eight deterministic groups against the real original engine:

1. Hollow container, upper/lower separation, and actual sand motion over 45 ticks.
2. Eight large blocks in one row remain separate and present.
3. A single component receives no extra content or container; an empty closed vessel stays empty.
4. Circular wall closure by flood fill, physical aspect ratio, hollow interior, and contained eight-item composition without shell loss.
5. An open tank retains sides/floor while its interior connects to open air.
6. Compact/spacious spacing and layered pool proportions differ without changing material or vertical intent.
7. A generated touching BTRY/METL connection actually creates SPRK in the engine.
8. Invalid sizes, temperatures, materials, counts, empty scenes and first-item connections are rejected.

These authored compiler tests are not model responses and do not claim live inference reliability. The report is `evidence/apple-scene-layout-shapes.log`.

## Container construction benchmark

The harness's `--benchmark` option compares direct wall construction with an equivalent filled rectangle followed by an interior erase, appending the same sand/water contents to both. The resulting packed cells (including material appearance and temperature) and particle counts match: **25,843 particles**. A different creation history can affect hidden element initialization/RNG state; future simulation equivalence is not claimed.

Optimized Swift linked to the existing arm64 Release engine objects produced these medians over ten alternating measured constructions per path, following two warmups:

| Construction | Median |
| --- | ---: |
| Filled shell and interior erase | 68.323 ms |
| Four direct wall rectangles | 8.398 ms |
| Relative construction speed | 8.14× |

This is CPU world-construction time only. It is not model inference time or end-to-end scene generation latency. Raw results are in `evidence/apple-scene-layout-benchmark.json`.

To compile against an existing native Release build from `Native`:

```sh
xcrun swiftc -disable-sandbox -swift-version 6 -O -parse-as-library \
  -target arm64-apple-macos26.0 -module-cache-path /tmp/powder-layout-module-cache \
  -I DerivedData/Build/Products/Release \
  -Xcc -fmodule-map-file=DerivedData/Build/Intermediates.noindex/GeneratedModuleMaps/CBridge.modulemap \
  App/Intelligence/AppleSceneLayout.swift App/Intelligence/AppleScenePlanner.swift \
  scripts/verify-apple-scene-layout.swift \
  DerivedData/Build/Products/Release/PowderCore.o \
  DerivedData/Build/Products/Release/PowderEngine.o \
  DerivedData/Build/Products/Release/CBridge.o \
  DerivedData/Build/Products/Release/JsonCpp.o -lc++ -lbz2 \
  -o /tmp/verify-apple-scene-layout
/tmp/verify-apple-scene-layout --benchmark
```
