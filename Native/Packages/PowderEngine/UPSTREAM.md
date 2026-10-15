# Original simulation core

This package builds The Powder Toy **v100.1.400**, commit `d768aeb89acad986bd252d7e904bf44bb374545f`, as a headless C++20 library behind a C ABI and a native Swift value wrapper. The release matches the supplied Steam macOS build. Source provenance and archive checksums are recorded in `UPSTREAM.json`.

The upstream source is from https://github.com/The-Powder-Toy/The-Powder-Toy and is covered by the GNU GPL v3 in `COPYING`. Copyright belongs to The Powder Toy contributors. The new adapters are distributed under GPL-3.0-or-later. JsonCpp and pocketfft retain their own licenses and notices in their respective source directories.

## Preserved behavior

- Original 612 × 384 particle canvas, element identifiers, all enabled elements, element callbacks, heat, pressure, air movement, gravity modes, electronics, optics, portals, stickmen, life, nuclear particles, and the original simulation tick sequence.
- Matter and energy maps remain separate. The bridge exports every active particle, including overlapping/stacked particles, and arbitrary per-particle fields used by original elements.
- Native OPS saves are encoded and decoded by upstream GameSave. Legacy PSv/fuC decoding remains available. OPS uses upstream quantization; it is not a lossless in-memory checkpoint.
- In-memory clones use upstream snapshots plus omitted control/settings/RNG and gravity solver state. Access to shared upstream element data is protected by a recursive process-wide mutex.

## Native integration changes

- `TPTBridge.cpp` exports bounded C APIs, catalog metadata, particle samples/mutations, air/gravity samples, erasing, seeding, stepping, and compatibility settings. Exceptions are converted to thread-local error messages.
- `TPTOverlays.cpp` exports the full original wall catalog, 4 × 4 wall blocks, charge timers, fan vectors and resolved plain sign labels. Its editing adapters invoke original wall behavior and enforce original OPS sign text constraints (45 printable ASCII characters). Sign link labels expose no click actions.
- `TPTRenderSnapshot.cpp` copies immutable 16-byte presentation cells and a consistent header under one engine lock. It preserves separate decoration alpha, native photon-spectrum display, energy priority and walls while avoiding per-particle Swift objects. It does not change physics, randomness or copy-on-write checkpoints.
- `TPTSave.cpp` exposes OPS and snapshot adapters. It bounds compressed and declared decompressed save size before parsing and validates decoded numeric settings.
- `TPTGravity.cpp` retains upstream FFT gravity convolution, masks, normalization and asynchronous exchange. Header-only pocketfft replaces desktop FFTW so the backend can compile for both Apple platforms.
- `Generated/Config.h`, element/tool number headers and compressed-font data are generated equivalents of upstream build resources. `Config.h` undefines SwiftPM's DEBUG macro before the upstream typed constant.
- `Generated/HeadlessFormat.cpp` retains upstream text/temperature/PPM formatting. PNG encode/decode entry points return null: the native shell owns image codecs and the engine exposes OPS. The unused PNG header was removed from upstream Graphics.cpp. The original Format.cpp remains in the vendor tree for provenance and is not compiled.
- Original software renderer support remains linked because element callbacks, save migrations and FIRW physics use its tables; the app renders through its independent Metal renderer.
- SDL, Lua, the original widget frontend, online account/network code and platform integration are not compiled into this package. Their source remains in the pinned vendor tree to preserve provenance.

## Optional historical fusion behavior

`legacyFusionSideEffects` is off by default. When enabled, the O2 fusion callback can spawn the historical hot SING particle with bounded coordinates and the intended SING lifetime; tagged fusion photons can use the historical low-pressure H2 interaction. The normal path consumes no additional random values when the option is disabled. The option is copied with worlds and stored in an additional OPS BSON key, ignored by ordinary upstream readers. The altered upstream files are listed in `UPSTREAM.json`.

## Build and checks

From this directory, run `swift test`. A host whose default Swift module cache is unavailable can set `CLANG_MODULE_CACHE_PATH` and `SWIFTPM_MODULECACHE_OVERRIDE` to a writable directory and select a writable `--scratch-path`. The package is an explicit source list; unlisted upstream GUI and platform sources are not compiled. The native macOS app resolves this local package through Xcode. `Benchmarks/run-render-snapshot-benchmark.sh` measures CPU frame preparation against the former Swift expansion path.
