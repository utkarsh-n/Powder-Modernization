# Powder: historical reference analysis and first native prototype

This document records the initial v0.1/v0.2 first-principles Swift prototype and the verified reference artifact. **It is historical:** at the user's later request, v0.3 integrates the original GPL-licensed v100.1.400 C++ simulation behind the native SwiftUI and Metal shell. See [Upstream History.md](Upstream%20History.md), [the current README](../Native/README.md), and [Validation.md](Validation.md) for the current implementation and tests. iPad adaptation remains a later priority.

## Verified reference artifact

| Property | Evidence |
| --- | --- |
| Supplied file | `powder-v100.1.400+steam-x86_64-darwin-macos.dmg` |
| Product | The Powder Toy |
| Bundle identifier | `uk.co.powdertoy.tpt` |
| Version | `100.1 (build 400)` |
| Executable | `Contents/MacOS/powder`, Intel x86_64 |
| Declared minimum macOS | 10.13 |
| Registered formats | `.stm`, `.cps`; `ptsave:` URL scheme |
| SHA-256 | `b4189170bfca65171c1774bd4f5eedc644e9861c07a52e570d282440e6d6e64e` |

The local DMG hash matches the exact asset on the [official v100.1.400 release](https://github.com/The-Powder-Toy/The-Powder-Toy/releases/tag/v100.1.400). That release identifies commit prefix `d768aeb`. Its [public source archive](https://github.com/The-Powder-Toy/The-Powder-Toy/archive/refs/tags/v100.1.400.tar.gz) is retained separately as reference material. The source license file contains GNU GPL version 3; this records metadata and makes no distribution-rights conclusion.

Local evidence: [bundle metadata](../reference/The%20Powder%20Toy.app/Contents/Info.plist), [original README](../reference/ORIGINAL-README.md), [binary symbols](../evidence/binary-symbols-demangled.txt), [linked libraries](../evidence/binary-linked-libraries.txt), and [upstream research](../evidence/upstream-research.txt).

**The old UI could not be launched and captured in this investigation.** There is no live interaction audit or verified screenshot comparison. The behavior below comes from metadata, symbols, documentation, and read-only examination of official source. It should not be represented as directly observed runtime behavior.

## Recovered behavior contract

| Area | Reference behavior |
| --- | --- |
| Drawing and materials | Paint powders, liquids, gases, solids and specialized elements; erase, sample, search, change brush shape/size, draw lines/rectangles and zoom. |
| Time controls | Pause/resume and advance one simulation frame. Rendering and simulation pacing are separate concerns. |
| Editing history | Undo/redo, copy/cut/paste, rotate/mirror selections, reusable stamps and local saves. |
| Physics | Falling particles and reactions, temperature and phase changes, pressure and air velocity, ambient heat, multiple gravity modes and Newtonian gravity. |
| Advanced construction | Conductors and electrical components, sensors, powered elements, pipes, portals and other element-specific state. |
| Presentation | Material colors, diagnostic display modes, decoration colors, signs, HUD, screenshots and simulation options. |
| Scripting and community | Lua console/API, online save search/preview/upload, accounts, tags and favorites. |

The reference uses a 612 × 384 logical particle canvas with coarser 153 × 96 pressure/wall/gravity grids. Its palette includes many specialized behaviors; visual resemblance between two materials does not establish simulation compatibility. See the [official README](https://github.com/The-Powder-Toy/The-Powder-Toy/blob/v100.1.400/README.md) and [simulation configuration](https://github.com/The-Powder-Toy/The-Powder-Toy/blob/v100.1.400/src/SimulationConfig.h).

## Current native prototype boundary

New code lives under [Native](../Native/). It uses an original Swift `PowderCore`, a SwiftUI interface, and bitmap frames presented through `CGImage`. This is not a Metal physics solver.

The initial material model has **12 cases including empty, with 11 visible materials**. It establishes a small native sandbox and shared data model, not parity with the original element library. Shared core code supports consistent rules between Mac and iPhone; each platform needs its own interaction and packaging. The iPhone interface must provide touch-accessible tools rather than depending on desktop mouse buttons or modifier keys.

Documents use a version-validated JSON **`.powderlab`** format. They are not compatible with original `.cps` or `.stm` files. Original pressure fields, circuitry, Lua behavior, online saves, stamps, and the complete material catalog remain separate compatibility or feature work. This document makes no build, test, performance, or device-validation claims.

## Save-format implications

The [reference save reader](https://github.com/The-Powder-Toy/The-Powder-Toy/blob/v100.1.400/src/client/GameSave.cpp) recognizes modern `OPS1` and older `PSv`/`fuC` signatures. OPS1 contains a header and bzip2-compressed BSON, with dimensions, version constraints, element identifiers, particle-specific fields, simulation options and optional pressure/heat/gravity data. Historical element migrations and stacked or specialized particles affect interpretation.

A future importer must distinguish unsupported versions, corrupt files, unknown materials and partially recoverable state. Successfully decoding a file does not mean its machines or reactions will behave identically. Import should preserve the source file and report lost or approximated information.

## Development sequence

1. Establish an extensible material model and explicit reaction rules, with reproducible simulation and document tests.
2. Add temperature and phase behavior, then pressure/air and gravity fields with defined update order and boundary conditions.
3. Introduce circuitry and specialized components as separately validated features.
4. Build a legacy importer against representative fixture saves, with honest compatibility and loss reporting.
5. Refine accessibility: VoiceOver labels, keyboard access, adequate touch targets, contrast and clear selected-tool feedback.
6. Measure frame pacing, memory and thermal behavior on actual Mac and iPhone hardware; optimize measured bottlenecks before choosing a GPU simulation design.

Build and validate separate macOS universal (`arm64`/`x86_64`), iOS device, and iOS Simulator products. Sharing source does not make these binaries interchangeable. Apple's [multiplatform framework documentation](https://developer.apple.com/documentation/xcode/creating-a-multi-platform-binary-framework-bundle) describes the platform distinction.

Lua and online features need dedicated later design. LuaJIT documents an [interpreter-only iOS configuration](https://luajit.org/install.html); unrestricted desktop scripts should not be promised on iPhone. Any downloadable-code feature also needs review against Apple's [current app review guidelines](https://developer.apple.com/app-store/review/guidelines/), without assuming acceptance.
