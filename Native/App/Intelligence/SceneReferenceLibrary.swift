import Foundation

/// A locally curated reading reference, not a downloaded save or executable recipe.
struct SceneReference: Identifiable, Codable, Hashable, Sendable {
    let id: String
    let title: String
    let url: URL
    let summary: String
    /// Suggested native-engine palette. Not an inventory extracted from the source save.
    let materialCodes: [String]
    let tags: [String]
    /// Explicitly separates source statements, adaptation ideas, and verification limits.
    let designNotes: [String]
}

enum SceneReferenceLibrary {
    static let provenanceNotice = "Community references are curated from official Powder Toy save descriptions and forum posts. No save was downloaded, inspected internally, or executed. Material codes are suggested adaptation palettes; design ideas are inferences, not verified reproductions. Validate against the current engine and label observed behavior separately."

    static let references: [SceneReference] = [
        reference("logic-switched-and", "Fast And Gate — baizuo", save: 1044629,
            summary: "A community AND-gate example, paired with the author's discussion of switch-based logic without temperature gates.",
            materials: ["SWCH", "PSCN", "NSCN", "METL", "SPRK"],
            tags: ["logic", "circuit", "gate", "and", "switch", "signal", "beginner"],
            notes: [
                "Source: the companion thread describes SWCH-based gates and signal-phase glitches: https://powdertoy.co.uk/Discussions/Thread/View.html?PageNum=0&Thread=15691",
                "Adaptation inference: separate two visible inputs, the gating region, and an output indicator; test every input combination over multiple ticks.",
                "Limit: timing and particle order matter. The palette is suggested, and neither this save's wiring nor its truth table was executed here."
            ]),
        reference("logic-filt-learning", "How do I start learning about FILT tech?", thread: 27293,
            summary: "Jerehmia's forum tutorial links encoding and memory demonstrations and explains representing bits with light wavelengths.",
            materials: ["FILT", "ARAY", "BRAY", "LDTC", "DTEC", "PSCN", "NSCN"],
            tags: ["logic", "computer", "memory", "rom", "ram", "binary", "optics", "filter", "signal", "advanced"],
            notes: [
                "Source: the tutorial discusses FILT modes, a carrier wavelength, and LDTC/DTEC readout; it links examples 3188001, 3188784, and 3189177.",
                "Adaptation inference: teach encode → transmit → filter → read as separate visible modules before attempting memory.",
                "Limit: exact ctype/tmp values, layering, and tick order need validation. The recommended editing script is not included or executed by the native planner."
            ]),
        reference("computer-synergy-29", "Synergy Computer (29-bit) — Synergy", save: 1761441,
            summary: "The archive describes a 29-bit computer and credits separate display and demultiplexer designs; its description also records a repair.",
            materials: ["FILT", "ARAY", "BRAY", "DTEC", "SWCH", "PSCN", "NSCN"],
            tags: ["computer", "cpu", "processor", "calculator", "program", "display", "logic", "advanced"],
            notes: [
                "Adaptation inference: split input, storage, arithmetic, and display into modules with observable test points.",
                "Limit: this is a complexity reference, not a promise to generate a working CPU. Suggested materials are not an inspected parts list; exact arithmetic and timing remain unverified."
            ]),
        reference("engine-piston", "Piston engine — spacecowboy", save: 3054235,
            summary: "The author describes a fuel tank, water cooling, and continuing work on valve timing in a piston-engine project.",
            materials: ["PSTN", "FRME", "DESL", "WATR", "SPRK", "PSCN", "NSCN"],
            tags: ["engine", "piston", "motor", "valve", "combustion", "fuel", "cooling", "machine"],
            notes: [
                "Adaptation inference: construct separate intake, ignition, actuator, exhaust, and cooling modules; test motion before adding fuel.",
                "Limit: a suggested PSTN/FRME adaptation is not an extracted mechanism. The author's timing caveat means a plausible drawing must not be labeled a working engine without repeated-cycle checks."
            ]),
        reference("heat-coal-plant", "Coal Power Plant — zKryT", save: 710437,
            summary: "An explicitly unfinished, destructible coal plant with storage and furnace controls; the author discusses insufficient cooling space in its comments.",
            materials: ["COAL", "BCOL", "FIRE", "WATR", "WTRV", "METL", "PIPE", "BRCK"],
            tags: ["coal", "furnace", "boiler", "steam", "heat", "cooling", "power", "factory", "fluid"],
            notes: [
                "Adaptation inference: separate fuel storage → furnace → water/steam path → cooling reservoir, leaving room for exhaust and inspection.",
                "Limit: this palette and chain are adaptation ideas. Do not claim a closed water cycle or generated electricity solely because a scene contains a furnace and pipes."
            ]),
        reference("reactor-feedback", "Reactor with Control Rods v3.0 — arusingh", save: 2434921,
            summary: "The creator describes a fictional-game plutonium reactor with automatically adjusting control rods.",
            materials: ["PLUT", "NEUT", "WATR", "TSNS", "PSTN", "FRME", "PSCN", "NSCN"],
            tags: ["reactor", "nuclear", "fission", "plutonium", "feedback", "sensor", "control", "automatic"],
            notes: [
                "Adaptation inference: separate the reaction region, temperature sensing, control signal, and actuator; expose an off state and compare response over time.",
                "Limit: the source names plutonium but does not establish this suggested sensor/actuator palette. Rod composition and effectiveness were not inspected; this is game logic, not real reactor engineering."
            ]),
        reference("reactor-vibranium-cycle", "Vibranium Reactor — lucas", save: 3238482,
            summary: "The author describes POLO heating VIBR, with EXOT products recycled into VIBR and GOLD/BREL supplied to the system.",
            materials: ["VIBR", "POLO", "EXOT", "GOLD", "BREC"],
            tags: ["reactor", "nuclear", "vibranium", "polonium", "exotic", "cycle", "recycling", "heat"],
            notes: [
                "Source: the description names all five materials and labels the project work in progress. BREC is the engine identifier displayed as BREL.",
                "Adaptation inference: show source → charging region → conversion → return as distinct zones and track whether material actually returns.",
                "Limit: description-level evidence does not establish conversion settings, stability, or compatibility with the pinned engine. All reactions here refer to fictional game substances."
            ]),
        reference("fluids-water-cycle", "Water cycle realistic simulation — Dogdayboy", save: 3065572,
            summary: "A community save presented by its creator as a simulation of Earth's water cycle.",
            materials: ["WATR", "WTRV", "ICEI", "METL", "STNE", "GLAS"],
            tags: ["water", "fluid", "rain", "cloud", "evaporation", "condensation", "cycle", "weather", "nature"],
            notes: [
                "Adaptation inference: reserve separate water, vapor, and cooling zones; let condensed water fall toward a catchment instead of filling every region.",
                "Limit: the archive description does not expose its heating mechanism or materials. Validate phase changes and the water budget; do not infer real climate or meteorological accuracy."
            ]),
        reference("nature-terrain-trees", "Terrain & Tree Tutorial! — Zuriel", save: 2388095,
            summary: "A terrain/tree tutorial; the author discusses using vines for irregular small-tree shapes in the page comments.",
            materials: ["STNE", "SAND", "WOOD", "VINE", "PLNT", "WATR"],
            tags: ["terrain", "tree", "forest", "landscape", "nature", "garden", "art", "tutorial"],
            notes: [
                "Adaptation inference: use a ground silhouette, varied tree heights, and intentional empty space; keep decorative texture separate from active growth experiments.",
                "Limit: only the vine technique is attributed to the author; the rest of the palette is suggested. A convincing forest silhouette does not establish ecological behavior."
            ]),
        reference("nature-forest-waterfall", "Plant World: Forest with waterfall — BenBoi041", save: 3151973,
            summary: "The save's title and description identify a plant-world forest with a waterfall; the public explanation is brief.",
            materials: ["PLNT", "VINE", "WOOD", "WATR", "STNE", "SAND"],
            tags: ["ecosystem", "terrarium", "garden", "forest", "plant", "waterfall", "habitat", "nature"],
            notes: [
                "Adaptation inference: compose a high water source, an open fall, a catchment, and planted banks; test water loss and plant spread independently.",
                "Limit: this is landscape inspiration, not evidence of a self-sustaining ecosystem, animals, or a nutrient cycle. All palette codes are suggestions; no seed or mod-only biology is assumed."
            ]),
        reference("art-one-pixel-city", "One-Pixel Challenge — Matera_the_Mad", save: 2206865,
            summary: "A city scene framed by its author as an interactive art challenge: change one BOMB particle placement and compare the outcome.",
            materials: ["BRCK", "GLAS", "WOOD", "WATR", "BOMB"],
            tags: ["art", "city", "architecture", "challenge", "experiment", "chain", "reaction", "destruction"],
            notes: [
                "Adaptation inference: give distinct structures different material responses, preserve a baseline, and change one input per trial.",
                "Limit: only BOMB is explicitly specified by the description. The suggested building palette is not the save's verified inventory, and a reaction cascade must be observed rather than promised."
            ]),
        reference("optics-photon-control", "How do lasers work and how to make one?", thread: 21308,
            summary: "Mrprocom's forum explanation decomposes a game photon beam into a source, directional enclosure, switches, and color filtering.",
            materials: ["PHOT", "PCLN", "DMND", "PSCN", "NSCN", "FILT"],
            tags: ["optics", "photon", "laser", "light", "beam", "color", "filter", "switch", "tutorial"],
            notes: [
                "Source: the post names these components and describes PSCN/NSCN control of PCLN and FILT color changes.",
                "Adaptation inference: start with a visible low-temperature beam and an explicit off state, then test one optical component at a time.",
                "Limit: enclosure thickness, source ctype, stray emission, and heat isolation require exact geometry and validation. These are game particles, not an optical engineering specification."
            ]),
        reference("space-micro-universe", "Micro Universe Simulator — agustrusher", save: 1698132,
            summary: "The author presents an evolving celestial scene with varying replays and warns that formation takes minutes and can be slow.",
            materials: ["H2", "NBLE", "CO2", "PLSM", "PHOT", "NEUT", "DMND"],
            tags: ["space", "star", "universe", "nebula", "fusion", "emergence", "generative", "art"],
            notes: [
                "Source: the companion explanation describes staged star/nebula evolution: https://powdertoy.co.uk/Discussions/Thread/View.html?Thread=19637",
                "Adaptation inference: use a small bounded initial condition, visible stages, and a time budget before scaling particle count.",
                "Limit: the palette is suggested (H2 is the engine identifier for hydrogen). Save internals and stellar behavior were not inspected; a 45-tick trial cannot validate a minutes-long emergent scene or scientific accuracy."
            ])
    ]

    /// Bounded, local lexical retrieval; no network, model call, save load, or scene mutation.
    /// Ties use stable IDs, so results do not depend on Set iteration or catalog order.
    static func relevantReferences(for text: String, limit: Int = 3) -> [SceneReference] {
        guard limit > 0 else { return [] }
        let query = tokens(String(text.prefix(8_192))).subtracting(stopWords)
        guard !query.isEmpty else { return [] }
        let expanded = synonymGroups.reduce(into: query) { result, group in
            if !group.isDisjoint(with: query) { result.formUnion(group) }
        }
        return index.compactMap { entry -> (SceneReference, Int)? in
            let exact = query.intersection(entry.title).count * 6
                + query.intersection(entry.tags).count * 7
                + query.intersection(entry.materials).count * 10
                + query.intersection(entry.summary).count * 2
            let related = expanded.subtracting(query).intersection(entry.tags).count * 3
            let score = exact + related
            return score > 0 ? (entry.reference, score) : nil
        }.sorted {
            $0.1 != $1.1 ? $0.1 > $1.1 : $0.0.id < $1.0.id
        }.prefix(min(limit, references.count)).map(\.0)
    }

    private struct SearchEntry: Sendable {
        let reference: SceneReference
        let title: Set<String>
        let tags: Set<String>
        let materials: Set<String>
        let summary: Set<String>
    }

    private static let index = references.map {
        SearchEntry(reference: $0, title: tokens($0.title), tags: tokens($0.tags.joined(separator: " ")),
                    materials: tokens($0.materialCodes.joined(separator: " ")), summary: tokens($0.summary))
    }

    private static func tokens(_ text: String) -> Set<String> {
        let folded = text.folding(options: [.caseInsensitive, .diacriticInsensitive], locale: Locale(identifier: "en_US_POSIX"))
        return Set(folded.lowercased().split(whereSeparator: { !$0.isLetter && !$0.isNumber }).map(String.init))
    }

    private static let stopWords: Set<String> = [
        "a", "an", "and", "are", "as", "at", "be", "by", "can", "could", "do", "for", "from", "has", "have",
        "i", "in", "into", "is", "it", "like", "make", "me", "my", "of", "on", "or", "please", "some", "that",
        "the", "their", "this", "to", "use", "using", "want", "with", "would", "you", "your", "build", "create",
        "scene", "design", "project", "reference", "references", "example", "examples", "powder", "toy"
    ]

    private static let synonymGroups: [Set<String>] = [
        ["logic", "circuit", "circuits", "gate", "gates", "electronics", "electronic", "wiring"],
        ["computer", "computers", "cpu", "processor", "calculator", "computing"],
        ["memory", "ram", "rom", "binary", "bits"],
        ["engine", "engines", "motor", "motors", "piston", "pistons", "valve", "valves", "car"],
        ["coal", "furnace", "furnaces", "boiler", "boilers", "steam", "wtrv"],
        ["reactor", "reactors", "nuclear", "fission", "plutonium", "plut", "uranium", "uran"],
        ["vibranium", "vibr", "polonium", "polo", "exot", "brec", "brel", "recycling"],
        ["water", "watr", "fluid", "fluids", "liquid", "liquids", "rain", "rainfall", "cloud", "clouds", "weather"],
        ["ecosystem", "ecosystems", "terrarium", "terrariums", "garden", "gardens", "habitat", "aquarium"],
        ["forest", "forests", "tree", "trees", "plant", "plants", "plnt", "vine", "vines", "wood", "nature"],
        ["terrain", "landscape", "landscapes", "mountain", "mountains", "geology"],
        ["art", "artwork", "pixelart", "decor", "decoration", "aesthetic"],
        ["city", "cities", "town", "building", "buildings", "architecture", "skyscraper", "skyline"],
        ["optics", "photon", "photons", "phot", "laser", "lasers", "light", "beam", "beams"],
        ["space", "star", "stars", "universe", "cosmos", "nebula", "nebulae", "fusion"],
        ["feedback", "sensor", "sensors", "tsns", "automatic", "automation", "thermostat"],
        ["challenge", "puzzle", "experiment", "experiments", "cascade", "chain", "reaction"]
    ]

    private static func reference(_ id: String, _ title: String, save: Int? = nil, thread: Int? = nil,
                                  summary: String, materials: [String], tags: [String], notes: [String]) -> SceneReference {
        // IDs and routes are authored constants, never remote input.
        let path = save.map { "Browse/View.html?ID=\($0)" }
            ?? "Discussions/Thread/View.html?Thread=\(thread!)"
        return SceneReference(id: id, title: title, url: URL(string: "https://powdertoy.co.uk/\(path)")!,
                              summary: summary, materialCodes: materials, tags: tags, designNotes: notes)
    }
}
