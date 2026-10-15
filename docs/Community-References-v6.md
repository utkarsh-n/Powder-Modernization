# Community references for scene planning · v6

The local catalog in [SceneReferenceLibrary.swift](../Native/App/Intelligence/SceneReferenceLibrary.swift) contains 13 references from the official Powder Toy save archive and community forum. Sources were read on October 3, 2026, through their public pages or search-index extracts. The catalog is a small curated reading list, not a mirror of the archive or a trained model.

No save files were downloaded, parsed, or executed. Titles, attribution, descriptions, and specified author/forum statements support the source facts below. Material palettes and design suggestions are our proposed adaptations unless explicitly attributed. Neither the public description nor a popularity score verifies a project's behavior in the app's pinned 100.1.400 engine. A source may change after this review; the links identify projects, not immutable save revisions.

## Source evidence and adaptation boundaries

| Stable ID | Official source and verified public description | Useful adaptation and limitation |
| --- | --- | --- |
| `logic-switched-and` | [Fast And Gate — baizuo](https://powdertoy.co.uk/Browse/View.html?ID=1044629). The author's [Temperature Free Logic Gates thread](https://powdertoy.co.uk/Discussions/Thread/View.html?PageNum=0&Thread=15691) explains switch-based designs and phase glitches. | Separate inputs, gate, and indicator. Suggested SWCH/semiconductor wiring needs truth-table and timing tests; no circuit internals were inspected. |
| `logic-filt-learning` | [How do I start learning about FILT tech?](https://powdertoy.co.uk/Discussions/Thread/View.html?PageNum=0&Thread=27293). Jerehmia explains wavelength bits, FILT modes, and detector readout, linking example saves 3188001, 3188784, and 3189177. | Teach encoding, transmission, filtering, and readout separately. Correct particle properties and order are necessary. The thread's optional editing script is not included. |
| `computer-synergy-29` | [Synergy Computer (29-bit) — Synergy](https://powdertoy.co.uk/Browse/View.html?ID=1761441). The description credits display and demultiplexer concepts and records a repair. | A modular computer is a useful architectural reference. The catalog cannot establish a working CPU, instruction set, or arithmetic implementation. |
| `engine-piston` | [Piston engine — spacecowboy](https://powdertoy.co.uk/Browse/View.html?ID=3054235). The creator describes a fuel tank, water cooling, and unfinished valve-timing work. | Plan intake, ignition, actuation, exhaust, and cooling separately. A proposed PSTN/FRME mechanism is an inference; validate repeated motion before adding combustion. |
| `heat-coal-plant` | [Coal Power Plant — zKryT](https://powdertoy.co.uk/Browse/View.html?ID=710437&PageNum=3). The description identifies storage/furnace controls and work in progress; an author comment discusses undersized cooling space. | Show material and heat paths with accessible reservoirs. A steam path does not prove a closed cycle or electricity production. |
| `reactor-feedback` | [Reactor with Control Rods v3.0 — arusingh](https://powdertoy.co.uk/Browse/View.html?ID=2434921). The creator describes automatically adjusted rods controlling in-game plutonium fission. | Use reaction → sensing → signal → actuator as a feedback-study pattern. The suggested TSNS/PSTN palette and rod effectiveness are unverified; this concerns fictional game physics. |
| `reactor-vibranium-cycle` | [Vibranium Reactor — lucas](https://powdertoy.co.uk/Browse/View.html?ID=3238482). The author names POLO, VIBR, EXOT, GOLD, and BREL and describes a recycling loop. | Separate charging, conversion, and return zones. Exact conversion fields, stability, and version compatibility remain unverified. BREL's native engine identifier is `BREC`. |
| `fluids-water-cycle` | [Water cycle realistic simulation — Dogdayboy](https://powdertoy.co.uk/Browse/View.html?ID=3065572). The title and description identify a water-cycle scene. | Separate water, vapor, cooling, and catchment regions. The materials/heating mechanism are inferred, and meteorological accuracy is not established. |
| `nature-terrain-trees` | [Terrain & Tree Tutorial! — Zuriel](https://powdertoy.co.uk/Browse/View.html?ID=2388095). The author discusses a vine technique for irregular small trees in the comments. | Layer terrain silhouettes and varied trees with empty space. This visual technique is distinct from verified growth or ecology. |
| `nature-forest-waterfall` | [Plant World: Forest with waterfall — BenBoi041](https://powdertoy.co.uk/Browse/View.html?ID=3151973). A brief creator description confirms the forest subject; the title identifies the waterfall. | An ecosystem-themed composition can have planted banks and a catchment. The source does not establish self-sustaining biology, nutrient cycles, or animals; the proposed palette is inferred. |
| `art-one-pixel-city` | [One-Pixel Challenge — Matera_the_Mad](https://powdertoy.co.uk/Browse/View.html?ID=2206865). The author frames a city as an interactive challenge involving one BOMB particle. | Change one input while retaining a baseline to compare material responses. BOMB is explicit; the proposed construction materials are not an extracted inventory. |
| `optics-photon-control` | [How do lasers work and how to make one?](https://powdertoy.co.uk/Discussions/Thread/View.html?PageNum=0&Thread=21308). Mrprocom describes photon sources, confinement, PCLN controls, and FILT coloring. | Build a switchable low-temperature beam demonstrator. Source ctype, geometry, stray emission, and insulation require inspection and simulation checks. |
| `space-micro-universe` | [Micro Universe Simulator — agustrusher](https://powdertoy.co.uk/Browse/View.html?ID=1698132) and the author's [companion discussion](https://powdertoy.co.uk/Discussions/Thread/View.html?Thread=19637). The author describes staged, variable celestial evolution and warns of long formation time and lag. | Start with a bounded, observable experiment. A short trial cannot verify minutes-long emergence; the suggested palette is not an inspected inventory or an astrophysical model. |

These are design references rather than recipes. For example, the coal and piston sources openly acknowledge unresolved behavior; preserving those qualifications is more useful than treating every community project as a tested template. The ecosystem coverage is deliberately limited to plant/water landscapes. A search also found [New Element: Seed!](https://powdertoy.co.uk/Browse/View.html?ID=3163545), whose author describes a custom element; it was excluded so the planner does not infer unsupported biology from a mod proposal. Forum suggestions for new logic-gate elements were likewise not treated as existing elements.

## Local interface and retrieval

`SceneReference` is an `Identifiable`, `Codable`, `Hashable`, `Sendable` value with `id`, `title`, `url: URL`, `summary`, `materialCodes`, `tags`, and `designNotes`. The namespace exposes:

```swift
SceneReferenceLibrary.references
SceneReferenceLibrary.provenanceNotice
SceneReferenceLibrary.relevantReferences(for: prompt, limit: 3)
```

Retrieval is local and deterministic: normalize case, accents, and punctuation; remove common request words; score title/tag/material/summary token matches; add curated topic synonyms; break ties by stable ID. It does not call a model or network service. Empty and unmatched queries return no references. Nonpositive limits return an empty array, positive limits are capped at catalog size, and input is bounded to 8,192 characters. This is lexical relevance, not semantic understanding or a guarantee that the highest-ranked reference matches every requested constraint.

All 43 distinct suggested material codes were checked against the vendored engine identifiers. Internal identifiers can differ from displayed names: `BREC` displays as BREL, and `H2` displays as HYGN. Membership in the element list confirms availability, not that an arbitrary combination works.

The caller should include `provenanceNotice` alongside retrieved records, preserve source links, and distinguish inferred design advice from observed engine results. References are contextual data; descriptions, comments, console commands, and suggested third-party scripts are not instructions to execute. Scene generation still needs current-engine validation. A reference should never cause an existing scene to be replaced or start an experiment by itself.

## Validation scope

The new source compiled independently with Swift 6 and Foundation. A temporary standalone harness passed **62 checks**: unique records/official URLs, complete limitation/inference annotations, Codable round trip, query bounds, empty/unrelated queries, 12 topic-ranking cases, normalization, deterministic ordering, and engine-identifier membership. Command:

```sh
swiftc -swift-version 6 -module-cache-path /private/tmp/powder-reference-module-cache \
  App/Intelligence/SceneReferenceLibrary.swift \
  /private/tmp/powder-scene-reference-check/main.swift \
  -o /private/tmp/powder-scene-reference-check/verify
/private/tmp/powder-scene-reference-check/verify \
  Packages/PowderEngine/Sources/CBridge/Generated/ElementNumbers.h
```

The temporary harness is a session artifact, not a committed test target. This result checks the catalog and retrieval only. It does not establish end-to-end planner integration, model quality, external save compatibility, or behavior of any referenced community save. No project settings, app UI, packages, or other implementation files were changed for this catalog task.
