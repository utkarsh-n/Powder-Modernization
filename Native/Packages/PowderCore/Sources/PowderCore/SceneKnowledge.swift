import Foundation

/// Grounding supplied to scene generators. This describes the native engine only.
public enum SceneKnowledge {
    public static var catalogText: String {
        let materials = Material.allCases.map { material in
            "- \(material.identifier): \(material.supportedInteractionSummary) Suggested initial temperature: \(Int(material.paintTemperature)) C."
        }.joined(separator: "\n")
        return """
        Create a runnable experiment for this native cellular sandbox using ONLY the catalog below.
        The catalog is the complete supported material set, not the original Powder Toy's element library.
        \(materials)

        Scene geometry contract:
        Coordinates x/y are normalized 0...1, with (0,0) at the top left and gravity downward.
        rectangle fills inclusive corners (x1,y1) through (x2,y2); both corners must be ordered.
        line joins both endpoints. radius controls thickness; radius 0 means one cell.
        circle uses (x1,y1) as center. radius is a fraction of the SHORTER canvas dimension, up to 0.25.
        scatter fills an ordered rectangle probabilistically with density 0...1; use for loose grains.
        density is ignored for the other shapes. Set unused numeric fields to 0.
        temperature is always required and is degrees Celsius, -273...5000. Use each material's suggested value.
        Commands execute in order and REPLACE earlier particles. Use empty to carve channels intentionally.
        Every command needs a short role explaining its function. Use at most 128 commands, preferably under 40.
        Overlap structural joints deliberately so connected components actually touch at different canvas sizes.
        Leave room for motion; contain liquids using walls; separate triggers from fuels when ignition should be delayed.

        Interaction chains and design guidance:
        Heat + ice -> water. Heat + water -> steam. Cooling steam -> water.
        Water touching fire quenches it and creates steam/smoke; water touching lava creates steam/stone.
        Fire or hot lava + wood/oil -> combustion -> heat/fire -> smoke. Acid dissolves sand, wood, and stone.
        Battery -> touching wire/metal/saltwater -> electrical pulse -> touching fuse -> connected burning fuse -> explosive charge.
        These electrical/fuse connections must touch orthogonally; diagonal contact alone is insufficient.
        Spark/fire -> thermite -> sustained heat -> lava. Water + seed -> plant; plant + water -> more plant.
        Salt + water -> saltwater -> conductive liquid. Explosions heat and displace neighbors; blast heat can ignite nearby charges.
        Do not invent a chemical reaction based solely on a material's name. These are simplified local rules, not realistic engineering.

        Requirements for the response:
        Return only a version 1 ScenePlan matching the supplied JSON schema. Do not output code, scripts, URLs or file paths.
        Explain the causal chain and list observable expectations. Use warnings for requested effects the engine cannot reproduce.
        A scene title or visual arrangement does not make an unsupported machine physically functional.
        No arbitrary chemistry, real fluid dynamics, accurate thermodynamics, general mechanical joints, nuclear simulation,
        online saves, Lua scripts, or original .cps/.stm compatibility should be claimed.
        If a request needs unsupported behavior, create the closest supported experiment and disclose that limitation.

        Example requests: “a lava stream meeting a pool”, “a layered sand and water container”,
        “a campfire beneath a boiler”, “a growing terrarium”, “a battery igniting a fuse”.
        Fixtures included with the app are authored examples and must never be described as AI-generated results.
        """
    }
}
