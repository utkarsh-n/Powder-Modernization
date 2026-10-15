# Compact native engine presentation snapshots

The later [interaction audit](Engine%20Interaction%20Performance.md) measures brush editing and inspector lookups separately. The snapshot results below are the earlier macOS v0.5 validation record.

The macOS frame producer can now call `EngineWorld.renderSnapshot()` instead of constructing `EngineParticle` values and three dense Swift float4 arrays. `TPTRenderSnapshot.cpp` fills one row-major 612 × 384 buffer directly from the original C++ engine. The call does not step physics, consume randomness, mutate the world, or trigger a Swift copy-on-write clone.

## Shared layout and lifetime

Each cell is exactly 16 bytes, with four native-endian 32-bit words:

| Byte offset | Field | Meaning |
| --- | --- | --- |
| 0 | UInt32 | Original display palette RGB, or the native app's PHOT spectrum RGB |
| 4 | UInt32 | Unmodified decoration ARGB; GPU blends it in floating point |
| 8 | Float | Temperature in Celsius |
| 12 | UInt32 | Low 16 bits element ID; bit 16 liquid, bit 17 energy, bit 18 wall, bit 19 powered wall |

All-zero cells are empty. Wall cells use element ID `0xFFFF`, their original base/powered RGB, and 20°C as in the previous native presentation. The renderer applies the existing 0.78/0.45 checker factor and 0.2 powered-wall emission. Walls are written first; particles replace them. Actual energy particles take priority over matter independently of creation order, and later particle indices win within the same layer.

Decoration is deliberately separate from palette RGB. Preblending into eight-bit RGB would lose fractional alpha precision compared with the existing shader inputs. The C++ bridge retains the native app's ten-bin-per-channel PHOT presentation; this change does not substitute the upstream software renderer's different graphics callbacks.

The 32-byte header captures dimensions, tick, particle count, wall count, legacy-fusion state, Newtonian-gravity state, and cell stride under the same engine mutex as the cell copy. `EngineRenderSnapshot` exposes immutable `Data` and scalar header fields and is `Sendable`. Its bytes outlive subsequent engine mutations. Random access through `cell(x:y:)` supports inspection/fallback without expanding the whole grid into Swift objects.

The underlying C function accepts caller-owned output memory. A future synchronized renderer buffer pool can use it directly. The current immutable `Data` approach avoids exposing pointers into live simulation storage or sharing mutable CPU buffers with in-flight GPU work. GPU profile tables are immutable per-element data, owned by the renderer; the engine snapshot contains no artistic material classification.

## CPU extraction benchmark

Measured on the arm64 development Mac using optimized Swift (`-O`) and a Release C++ package. Each fixed scene mixes SAND, WATR, METL and PLUT, with PHOT sharing selected water cells. There are three warmups and 30 measurements per path; old/new execution order alternates. The reference path reproduces the former native particle conversion, cached profile lookup, color/decor handling, and three float4 grid writes for these controlled fixtures. Neither path advances physics.

| Active particles | Former median | Compact median | Median speedup |
| ---: | ---: | ---: | ---: |
| 0 | 0.091 ms | 0.080 ms | 1.14× |
| 20,200 | 1.922 ms | 0.123 ms | 15.68× |
| 101,000 | 9.222 ms | 0.364 ms | 25.37× |
| 222,200 | 20.189 ms | 0.691 ms | 29.24× |

These are **CPU frame-preparation measurements**, not simulation throughput, GPU timing, UI responsiveness, FPS, thermal performance, or physical-memory/RSS measurements. They describe this host and fixture; wall-heavy or fragment-heavy scenes need separate app/GPU measurements.

The immutable grid payload falls from 11,280,384 bytes (three float4 grids, 10.758 MiB) to 3,760,128 bytes (3.586 MiB), a 66.7% reduction. The previous conversion also allocated 56-byte C particle records and 136-byte Swift `EngineParticle` values per active particle. At 222,200 particles, those temporary record payloads add about 40.69 MiB during conversion, before allocator and retained-string overhead. Those arrays are absent from the new render path. The original inspection/trial API remains available where complete particle properties are needed.

Reproduce from `Native/Packages/PowderEngine`:

```sh
zsh Benchmarks/run-render-snapshot-benchmark.sh /tmp/powder-engine-perf-build \
  '../../../evidence'
```

The runner builds Release package objects and compiles the real benchmark against them. Raw medians, 90th percentiles, memory strides, counts and a consumed-output checksum are in `evidence/engine-render-snapshot-benchmark.json`. The build log is `evidence/engine-render-snapshot-release-build.log`.

## Correctness checks

The full package suite passed **29 tests with zero failures**. Five new tests cover exact ABI/layout and invalid-buffer behavior; palette/decor/PHOT/temperature fidelity; energy priority in both creation orders; real detector-wall powering and particle-over-wall presentation; immutable snapshots and unchanged COW/RNG future evolution. Existing engine tests continue covering save/load, particle coexistence, undo isolation, historical fusion options, and Newtonian gravity.

The test log is `evidence/engine-render-snapshot-tests.log`. The only initial test-fixture correction was the upstream detector identifier (`DEFAULT_WL_DTECT`); no engine behavior was changed to make the checks pass. Upstream physics sources and save/clone behavior are unchanged by this optimization.
