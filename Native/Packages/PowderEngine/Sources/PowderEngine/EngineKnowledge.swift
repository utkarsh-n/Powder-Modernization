import Foundation

public enum EngineKnowledge {
    public static let rules = """
    This is the original The Powder Toy v100.1.400 videogame engine, a fictional particle sandbox.
    Matter and energy use separate occupancy layers. NEUT, PHOT, ELEC and PROT can share cells with matter.
    PLUT reacts with NEUT through the original fission rules. DEUT is a liquid with neutron interactions;
    its life property stores its concentration. URAN heats under pressure; it is not the same as PLUT.
    POLO emits neutrons. PHOT carries a wavelength mask and refracts through GLAS. PROT has its original
    interactions, including DEUT and high-energy collisions. HYGN/NBLE/CO2/O2 have the engine's staged fusion rules.
    BTRY energizes nearby ordinary conductors such as METL. Conducting particles temporarily become SPRK.
    Use METL/PSCN/NSCN for conventional circuits. WIRE is Wireworld cellular automaton, not ordinary wire.
    SPRK touching FUSE starts its slow burn to PLSM. BTRY→METL→FUSE is a useful activation chain.
    INSL interrupts conduction and heat transfer. DMND is a strong containment material. GLAS may break under pressure.
    SEED on SAND with WATR grows a tree at suitable temperatures. PLNT stores growth state in its original fields.
    Clone/detector devices may require ctype to identify the relevant element. Leave life/tmp/tmp2 at default
    unless the original element needs a specific setting; these properties have different meanings per element.
    The particles simulate game rules, not real-world nuclear or chemical engineering.
    """

    public static func instructions(width: Int, height: Int, compact: Bool) -> String {
        let catalog: String
        if compact {
            let categories = Set(EngineElement.allCases.map(\.category)).sorted()
            catalog = categories.map { category in
                category + ": " + EngineElement.allCases.filter { $0.category == category }.map(\.identifier).joined(separator: ",")
            }.joined(separator: "\n")
        } else {
            catalog = EngineElement.allCases.map {
                "\($0.identifier): \($0.summary) Default temperature \(Int($0.defaultTemperature)) C."
            }.joined(separator: "\n")
        }
        return """
        Design a playable 2D videogame experiment on a \(width)x\(height) canvas. Use only exact element codes below.
        Return a ScenePlan with \(compact ? "6 to 12" : "6 to 64") ordered geometric commands, structures first, triggers last.
        x increases right, y increases down; coordinates are normalized0...1. Keep shapes at least0.02 from canvas edges.
        Start with empty space. Chambers must be HOLLOW: outer DMND/GLAS/BRCK rectangle then inner NONE rectangle.
        Subsequent commands overwrite the same particle layer. NONE erases both matter and energy.
        Rectangle/scatter corners are ordered. Circle center is x1,y1. Line endpoints must share exact coordinates
        with adjoining components. Thin line radius0.003...0.008 works. Radius is relative to the shorter canvas side.
        Unused coordinates/radius/density are0. Scatter density0.2...0.8. Ordinary temperature20C,
        ICEI -20C, FIRE650C, WTRV140C, LAVA1400C, PLSM5000C. Never exceed9725C.
        Keep conductors short; physics evolves frame by frame. Leave visible space for motion.
        Optional ctype is an element code. life,tmp,tmp2 are element-specific integers; velocityX/Y are cells per tick;
        pressure is a local air-cell value from-256 to256. Use null for unused particle properties.
        Explain expected causal behavior, and disclose anything unsupported. Return data, never code or external actions.
        \(rules)
        CATALOG:\n\(catalog)
        """
    }
}
