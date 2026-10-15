# Upstream elements and an optional legacy fusion mode

The supplied app's missing features in the native prototype are **prototype omissions**. The upstream release still includes its nuclear and exotic particle types. Historical source does show specific changes to fusion side effects; the evidence does not establish a broad removal of nuclear elements or one universal “pre-nerf” release.

## Pinned source and inventory

- Official repository: [The-Powder-Toy/The-Powder-Toy](https://github.com/The-Powder-Toy/The-Powder-Toy).
- Baseline tag: [v100.1.400](https://github.com/The-Powder-Toy/The-Powder-Toy/releases/tag/v100.1.400).
- Exact peeled commit: [`d768aeb89acad986bd252d7e904bf44bb374545f`](https://github.com/The-Powder-Toy/The-Powder-Toy/tree/d768aeb89acad986bd252d7e904bf44bb374545f), committed August 7, 2026; release published August 8.
- Supplied DMG SHA-256: `b4189170bfca65171c1774bd4f5eedc644e9861c07a52e570d282440e6d6e64e`, matching the official release asset.
- Retrieved source: [reference repository](../reference/The-Powder-Toy-source/) and [tag archive](../reference/upstream-v100.1.400.tar.gz). The reference checkout's moving HEAD must not substitute for this pinned baseline.
- License metadata: the repository [LICENSE](../reference/LICENSE) contains GNU GPL version 3; the historical source headers explicitly say version 3 or later. Preserve license and attribution notices with any reused or modified source.

The pinned archive contains **195 element implementation files, all with `Enabled = 1`; 175 have `MenuVisible = 1` and 20 have `MenuVisible = 0`**. These are source-field counts, not 195 distinct buttons or 195 ordinary materials: the inventory includes `NONE` (erase), hidden states and support particles. The [complete 195-row inventory](../evidence/upstream-v100.1.400-elements.tsv) records identifiers, visibility, categories and descriptions.

`PLUT`, `URAN`, `NEUT`, `DEUT`, `POLO`, `PROT`, `SING`, `AMTR`, `ISOZ` and `ISZS` are present, enabled and visible in this release. Tag `47.3`, commit [`9d71597df9cf51808181166f668424f52f6dde21`](https://github.com/The-Powder-Toy/The-Powder-Toy/tree/9d71597df9cf51808181166f668424f52f6dde21), already contained `PLUT`, `URAN`, `NEUT`, `DEUT`, `SING` and `AMTR` on April 10, 2011. Protons arrived later in [`f1145f31f52f1089fed4c7f390f5384f040b4771`](https://github.com/The-Powder-Toy/The-Powder-Toy/commit/f1145f31f52f1089fed4c7f390f5384f040b4771), September 1, 2013. Choosing the whole 2012 engine would therefore lose later elements.

## Verified reaction changes

| Change | What the actual diff establishes |
| --- | --- |
| [`81771d86728e3ee16d8f1a6c91471b62efa9e9c8`](https://github.com/The-Powder-Toy/The-Powder-Toy/commit/81771d86728e3ee16d8f1a6c91471b62efa9e9c8), June 23, 2012 | Removed an active chance of creating `SING` as an oxygen-fusion side product in `src/elements/O2.c`. A second removed line in `co2.c` was already commented out. It did **not** remove the `SING` element. |
| [`dd73a7244f49de54ccd35a7cf1fdafd1a557e505`](https://github.com/The-Powder-Toy/The-Powder-Toy/commit/dd73a7244f49de54ccd35a7cf1fdafd1a557e505), October 20, 2013 | Added a photon-temperature condition to the existing low-pressure photon/hydrogen reaction in `Simulation.cpp`, reducing proton creation during fusion. It did **not** remove `PROT`. |
| [`41cc0a398a5e29bcfdb0b13603b6aa67a310a3a9`](https://github.com/The-Powder-Toy/The-Powder-Toy/commit/41cc0a398a5e29bcfdb0b13603b6aa67a310a3a9), committed January 7, 2014 | Replaced pressure/temperature guards with a photon `tmp` flag check. Hydrogen, noble-gas and oxygen fusion began marking emitted photons with that flag, preventing that pathway for fusion photons. |

The parent commits are respectively `29aab750e5d29eea87ea5698ca997820670c035d`, `b4761e47ddac23f7a52b714e2e0631dda1708a79`, and `4b28cdb6bad96950397150bc98eeb4cef3d431db`.

Exact [2012 diff](../evidence/upstream-history/81771d86.diff), [2013 diff](../evidence/upstream-history/dd73a724.diff), [2014 diff](../evidence/upstream-history/41cc0a39.diff), and [parent/changed excerpts](../evidence/upstream-history/parent-and-changed-snippets.txt) were extracted from Git objects, not a wiki. The excerpts include O2/H2/NBLE and the conversion code in `Simulation.cpp`. `NEUT.cpp` and `PROT.cpp` have identical parent/child blob IDs for the 2013 and 2014 changes; they were not directly changed by those commits. `PROT` did not yet exist at the 2012 change.

## Bounded integration

Use the pinned v100.1.400 core and all 195 implementations as the integration baseline beneath the native interface. Add an explicitly named **Legacy fusion side effects** option for the two identified historical behaviors. This preserves the modern element catalog and bug fixes. It is a targeted compatibility feature, not a claim to reproduce an entire old release.

1. Introduce a separate per-simulation boolean, defaulting off. Do not repurpose upstream `legacy_enable`, which controls a broader existing legacy-physics mode. Expose the new setting through the native bridge and UI; changing it must not recreate or clear the scene.
2. In pinned `src/simulation/elements/O2.cpp`, after the existing oxygen-fusion event succeeds, optionally restore its historical singularity side-product chance. Keep modern coordinate checks, particle-allocation failure handling, temperature bounds and RNG. Do not re-enable the already-commented CO2 line or replace the modern fusion trigger conditions.
3. In pinned `src/simulation/Simulation.cpp`, add the historical low-pressure photon-on-hydrogen pathway behind the new flag. Modern mode retains the existing `tmp`-flag exclusion. Legacy mode also permits flagged fusion photons below pressure 45 without the later temperature suppression. Existing unflagged-photon reactions remain unchanged, including at higher pressures. This deliberately restores the removed side effect without reverting unrelated modern collision behavior.
4. Leave fusion-photon tagging in H2/NBLE/O2 intact. The optional conversion guard can ignore it in legacy mode, while current mode and existing saves retain their normal semantics. No direct NEUT/PROT element edits are required for these two restorations.
5. Preserve the setting in new app documents. If extending upstream saves, use an explicitly named optional field with a default of false, carry it through load/save/snapshot/undo, and explain that an unmodified upstream reader will not apply the custom behavior. Do not silently claim exact cross-version playback compatibility.
6. Add paired tests: identical modern-mode reference outcomes; legacy oxygen fusion can create a singularity; flagged fusion photons remain excluded in modern mode and use the historical eligibility in legacy mode; both modes respect particle limits and edge bounds; setting persistence and undo round-trip correctly.

The local O2 patch deliberately corrects the historical `parts[i].life` assignment: the newly spawned singularity receives a lifespan of 50–74 ticks, and the source broken metal retains its normal lifetime. Byproduct temperature uses the modern engine's `MAX_TEMP` instead of the historical out-of-range 15000. The restored singularity chance is 2/5 after a successful current oxygen-fusion event. In modern mode the optional branch consumes no random numbers. This is a bounded restoration of selected side effects, not an exact 2012 replay.

The implementation is in [vendored O2](../Native/Packages/PowderEngine/Sources/CBridge/Upstream/simulation/elements/O2.cpp) and the [photon/hydrogen collision guard](../Native/Packages/PowderEngine/Sources/CBridge/Upstream/simulation/Simulation.cpp). H2, PHOT, NEUT and PROT implementations remain unchanged for this feature. The [headless regression harness](../scripts/check-legacy-fusion.cpp) uses the C ABI for world/settings/painting/save lifecycle and direct production reaction dispatch for controlled fusion and collision conditions; it contains no substitute reaction implementation. These are fictional sandbox reactions, with no claim of physical fidelity.

## Verified local behavior

The [regression log](../evidence/legacy-fusion-tests.log) records a successful run against the compiled production engine. Across 256 identical seeds, both modes triggered 51 oxygen-fusion events; the legacy option produced 20 singularities and modern mode produced none. The tests cover singularity temperature/lifespan, the corrected source-particle lifetime, photon pressure boundaries, unchanged unflagged-photon reactions, all four active-grid corners, a full 235008-particle pool, independent clone settings, and OPS round trips with the option both off and on.

The runner also compiles the unmodified pinned-release O2 implementation and links a separate reference executable. Modern-mode particle state, pressure and RNG match that reference across the same 256 seeds (fingerprint `f0e27add85a3bc3b`). Reproduce after building the macOS package with `python3 scripts/run-legacy-fusion-check.py /tmp/powder-engine-build`. These checks isolate the actual reaction routines with controlled gravity/pressure; they do not establish user-interface behavior or the accuracy of the gravity solver.
