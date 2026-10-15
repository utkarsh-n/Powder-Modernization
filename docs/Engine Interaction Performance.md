# Engine interaction audit — 2026-10-03

This follow-up concerns brush editing, undo history and the inspector. The earlier frame-preparation measurements in [Engine Performance](Engine%20Performance.md) remain a separate result; these changes do not alter the particle physics or Metal shader.

## Changes

The native circular brush previously crossed the Swift/C++ boundary, acquired the engine mutex and checked copy-on-write storage for every pixel visited. It now executes the same inclusive Bresenham line and circular brush traversal under one C++ call. Repeated visits are preserved deliberately: energy particles can stack, so deduplicating the brush footprint would change the original engine's behavior. Actual creation still calls the original `Simulation::create_part(-1, ...)`, with its collision rules, callbacks and random-number sequence.

A conservative preflight checks whether an ordinary particle stroke can change the world before cloning storage shared with Undo. It uses the original collision evaluator, handles SPRK's conductor/Wireworld behavior, and uses the existing spatial eraser index to find every stacked particle. A blocked stroke or an eraser over empty cells now returns `false`. Character creation callbacks may still reject a preflight candidate; this remains conservative rather than predicting those callbacks.

The worker creates a stroke's Undo checkpoint only after its first actual change. A rejected brush no longer destroys Redo, adds an empty Undo operation, marks the document dirty or prepares a redundant GPU frame. A stroke starting on an occupied cell still anchors its next line segment correctly. Requesting an already-selected gravity or fusion setting also leaves history and frames unchanged. Wall-painting tool semantics are unchanged; this optimization does not assume that repeated wall tools have no side effects.

The inspector previously enumerated and converted every wall block to find one selected cell. `EngineWorld.wall(x:y:)` now reads that one original 4 × 4 block directly, preserving its type, electrical charge and fan velocity. Bounds are checked before converting Swift integers to C coordinates.

`PlaygroundSession.editRevision` is a conservative token for accepted mutating commands. It changes immediately when an edit, replacement, Undo/Redo, step or playback-start is queued, allowing AI preview code to detect intervening user work before a worker reply arrives. Selection, inspection, sampling and export do not advance it. A rejected or failed accepted edit may still advance the token; it is a stale-preview guard, not a count of successful world changes or simulation ticks.

## Optimized measurements

On the arm64 development Mac, each path used three warmups and 30 measurements with alternating old/new order. The brush fixture draws a radius-16 line from (200, 160) to (300, 180), with the original world retained as an Undo checkpoint. The reference runs the previous Swift pixel traversal through the unchanged single-point API; both paths include copy-on-write work where an edit needs it.

| Brush operation | Former median | Current median | Median speedup |
| --- | ---: | ---: | ---: |
| Paint new metal | 6.228 ms | 3.162 ms | 1.97× |
| Draw sand over an occupied metal footprint | 6.060 ms | 0.361 ms | 16.79× |
| Erase an empty footprint | 5.780 ms | 0.134 ms | 43.20× |

Inspection measures 100 varied coordinates per sample and reports time per lookup. Full wall enumeration took 0.0105 ms with no walls, 0.2183 ms with 2,000 wall blocks, and 1.0021 ms with all 14,688 blocks occupied. Direct lookups remained below 0.001 ms in each fixture. The raw sub-microsecond numbers are retained in the JSON; the practical change is that lookup work no longer scales with the number of walls or allocates an entire wall array.

The final measurement ran after this audit's compilation and XCTest jobs completed. The earlier sample taken while those jobs were active is retained as `engine-brush-inspection-benchmark-initial.json`; it is not used in this table. These are CPU microbenchmarks of the named operations, not frame-rate or input-latency measurements.

## Verification

The full engine package passes 36 tests. Seven new tests cover the bulk brush against the prior single-pixel traversal for every enabled non-empty element; unchanged random state; blocked shared-world storage; matter/energy stacking and complete erasure; conductor and Wireworld sparks; wall blocking; extreme coordinates; and exact wall lookup across each pixel of every populated wall block.

The focused worker/session suite passes all 20 tests (15 worker, 5 session). It compiles production sources into a temporary test library and runs XCTest without starting the app. Its source hashes and results are retained in the log. The added regressions exercise Redo preservation after a rejected brush, a stroke whose first point is blocked, empty erasure and unchanged settings, and immediate edit-revision invalidation. Existing autosave, close-drain, request-ordering, cancellation/restart and immutable-frame tests remain passing.

The first headless compilation was blocked by the outer sandbox denying Xcode's Observation macro helper (`sandbox-exec: sandbox_apply: Operation not permitted`). The same production sources passed with approved sandbox escalation. The blocked build log is retained separately; this was not a code or test failure.

The extended headless run also passes 28 tests: the same 20 worker/session tests plus eight conversation-controller regressions. Those additional tests use gated test responses with real engine worlds, covering preview/apply boundaries, typed refinements, late cancellation, missing materials, equal-count edits and playback changes. They make no live model requests. Run that variant with `zsh scripts/run-worker-tests.sh /private/tmp/powder-worker-test-harness --include-ai`; its separate log is `evidence/worker-conversation-regression-tests.log`.

Evidence:

- `evidence/engine-brush-audit-tests.log`
- `evidence/worker-interaction-audit-tests.log`
- `evidence/engine-brush-inspection-release-build.log`
- `evidence/engine-brush-inspection-benchmark.json`

Reproduce from `Native`:

```sh
CLANG_MODULE_CACHE_PATH=/private/tmp/powder-audit-module-cache \
SWIFTPM_MODULECACHE_OVERRIDE=/private/tmp/powder-audit-module-cache \
swift test --package-path Packages/PowderEngine --disable-sandbox \
  --scratch-path /private/tmp/powder-audit-engine-build --jobs 8

zsh scripts/run-worker-tests.sh
zsh Packages/PowderEngine/Benchmarks/run-brush-inspection-benchmark.sh
```

These checks concern the real engine and actor/session code. They do not establish app FPS, end-to-end mouse latency, GPU performance, Intel performance or physical-memory usage, and do not include a new UI launch.
