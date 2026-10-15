import Foundation
import PowderEngine

/// Explicit, stable identities: a library reorder or search never changes a material's icon.
/// Names are checked against Apple's SF Symbols availability metadata for macOS 14.
enum MaterialSymbolCatalog {
    static let materials: [String: String] = [
        "ACEL": "forward.fill", "ACID": "drop.triangle", "AMTR": "minus.plus.batteryblock",
        "ANAR": "arrow.up.to.line", "ARAY": "rays", "BANG": "burst.fill",
        "BASE": "flask.fill", "BCLN": "square.on.square.dashed", "BCOL": "circle.hexagongrid.fill",
        "BGLA": "triangle.lefthalf.filled", "BHOL": "arrow.down.right.and.arrow.up.left",
        "BIZR": "drop.halffull", "BIZRG": "cloud.rainbow.half", "BIZRS": "cube.transparent",
        "BMTL": "square.split.diagonal.2x2", "BOMB": "timelapse", "BOYL": "arrow.up.and.down.righttriangle.up.righttriangle.down",
        "BRAY": "smallcircle.filled.circle", "BRCK": "rectangle.split.3x3.fill",
        "BREC": "cpu", "BRMT": "square.stack.3d.down.right", "BTRY": "battery.100percent",
        "BVBR": "waveform.path", "C5": "snowflake.circle.fill", "CAUS": "cloud.bolt.rain.fill",
        "CBNW": "bubbles.and.sparkles.fill", "HFLM": "flame", "CLNE": "square.on.square",
        "CLST": "square.grid.3x3.topleft.filled", "CNCT": "rectangle.fill",
        "CO2": "cloud.fill", "COAL": "circle.hexagonpath.fill", "CONV": "arrow.triangle.swap",
        "CRAY": "line.3.horizontal.decrease.circle", "CRMC": "cup.and.saucer.fill",
        "DCEL": "backward.fill", "DESL": "fuelpump.fill", "DEST": "burst",
        "DEUT": "drop.circle.fill", "DLAY": "clock.arrow.2.circlepath",
        "DMG": "arrow.up.left.and.arrow.down.right", "DMND": "diamond.fill",
        "DRAY": "square.on.square.squareshape.controlhandles", "DRIC": "cloud.snow.circle.fill",
        "DSTW": "drop", "DTEC": "sensor.fill", "DUST": "aqi.medium", "DYST": "microbe",
        "116": "arrow.triangle.branch", "ELEC": "minus.circle.fill", "EMBR": "sparkle",
        "EMP": "bolt.slash.circle", "ETRD": "bolt.horizontal.fill", "EXOT": "sparkles",
        "FIGH": "figure.boxing", "FILT": "camera.filters", "FIRE": "flame.fill",
        "FIRW": "fireworks", "FOG": "cloud.fog.fill", "FRAY": "arrow.up.right.circle.fill",
        "FRME": "square.dashed", "FRZW": "thermometer.snowflake", "FRZZ": "snowflake.circle",
        "FSEP": "line.diagonal", "FUSE": "line.diagonal.arrow", "FWRK": "party.popper.fill",
        "GAS": "cloud", "GBMB": "arrow.down.to.line.circle.fill", "GEL": "drop.degreesign.fill",
        "GLAS": "rectangle.on.rectangle", "GLOW": "lightbulb.fill", "GOLD": "seal.fill",
        "GOO": "oval.fill", "GPMP": "arrow.down.forward.and.arrow.up.backward.circle",
        "GRAV": "arrow.down.to.line", "GRVT": "arrow.down.circle.fill", "GUNP": "circle.grid.cross.fill",
        "H2": "h.circle", "HEAC": "heat.waves", "HSWC": "thermometer.sun.fill",
        "ICEI": "snowflake", "IGNT": "bolt.horizontal", "INSL": "rectangle.slash",
        "INST": "bolt.circle.fill", "INVIS": "eye.slash", "INWR": "cable.connector",
        "IRON": "hammer.fill", "ISOZ": "circle.hexagongrid.circle", "ISZS": "hexagon.fill",
        "LAVA": "mountain.2.fill", "LCRY": "diamond.lefthalf.filled",
        "LDTC": "viewfinder", "LIFE": "square.grid.3x3.fill", "LIGH": "bolt.fill",
        "LITH": "battery.100percent.bolt", "LNTG": "drop.degreesign", "LO2": "drop.circle",
        "LOLZ": "face.smiling", "LOVE": "heart.fill", "LRBD": "drop.keypad.rectangle.fill",
        "LSNS": "heart.text.square", "MERC": "thermometer.medium", "METL": "square.stack.3d.up.fill",
        "MORT": "tram.fill", "MWAX": "humidity.fill", "NBHL": "circle.inset.filled",
        "NBLE": "balloon.fill", "NEUT": "circle.dotted.circle", "NICE": "thermometer.snowflake.circle",
        "NITR": "drop.triangle.fill", "NONE": "eraser", "NSCN": "minus.square.fill",
        "NTCT": "thermometer.low", "NWHL": "circle", "O2": "o.circle", "OIL": "oilcan.fill",
        "PBCN": "square.stack.3d.forward.dottedline", "PCLN": "plus.square.on.square",
        "PHOT": "sun.max.fill", "PIPE": "point.topleft.down.curvedto.point.bottomright.up",
        "PLEX": "exclamationmark.triangle.fill", "PLNT": "leaf.fill", "PLSM": "sun.haze.fill",
        "PLUT": "atom", "POLO": "a.circle.fill", "PPIP": "arrow.triangle.turn.up.right.diamond.fill",
        "PQRT": "diamond.inset.filled", "PROT": "plus.circle.fill", "PRTI": "arrow.down.forward.circle",
        "PRTO": "arrow.up.backward.circle", "PSCN": "plus.square.fill", "PSNS": "gauge.with.dots.needle.50percent",
        "PSTE": "water.waves", "PSTN": "arrow.up.and.down.square.fill", "PSTS": "square.3.layers.3d",
        "PTCT": "thermometer.high", "PTNM": "seal", "PUMP": "arrow.up.and.down.circle",
        "PVOD": "power.circle.fill", "QRTZ": "diamond", "RBDM": "r.circle.fill",
        "RFGL": "refrigerator.fill", "RFRG": "refrigerator", "RIME": "cloud.snow.fill",
        "ROCK": "mountain.2", "RPEL": "arrow.up.left.and.arrow.down.right.circle",
        "RSSS": "rectangle.3.group.fill", "RSST": "rectangle.3.group", "SALT": "circle.grid.3x3.fill",
        "SAND": "hourglass.bottomhalf.filled", "SAWD": "circle.dotted", "SEED": "leaf.circle.fill",
        "SHLD1": "shield", "SHLD2": "shield.lefthalf.filled", "SHLD3": "shield.fill",
        "SHLD4": "checkmark.shield.fill", "SING": "circle.circle.fill",
        "SLCN": "square.grid.3x3.middle.filled", "SLTW": "drop.keypad.rectangle",
        "SMKE": "smoke.fill", "SNOW": "cloud.snow", "SOAP": "bubbles.and.sparkles",
        "SPAWN": "person.crop.circle.badge.plus", "SPAWN2": "person.crop.rectangle.badge.plus",
        "SPNG": "square.dotted", "SPRK": "bolt", "STKM": "figure.stand",
        "STKM2": "figure.arms.open", "STNE": "pentagon.fill", "STOR": "archivebox.fill",
        "SWCH": "switch.2", "TESC": "antenna.radiowaves.left.and.right", "THDR": "cloud.bolt.fill",
        "THRM": "flame.circle.fill", "TRON": "point.3.connected.trianglepath.dotted",
        "TSNS": "thermometer.variable.and.figure", "TTAN": "hexagon.lefthalf.filled",
        "TUNG": "lightbulb.max.fill", "URAN": "burn", "VIBR": "waveform",
        "VINE": "tree.fill", "VIRS": "microbe.fill", "VOID": "circle.slash.fill",
        "VRSG": "allergens", "VRSS": "cross.vial.fill", "VSNS": "speedometer",
        "WARP": "tornado", "WATR": "drop.fill", "WAX": "flame.circle",
        "WHOL": "arrow.up.right.and.arrow.down.left", "WIFI": "wifi",
        "WIRE": "point.3.filled.connected.trianglepath.dotted", "WOOD": "tree", "WTRV": "cloud.fog",
        "YEST": "microbe.circle.fill"
    ]

    static let walls: [String: String] = [
        "DEFAULT_WL_ERASE": "eraser.fill", "DEFAULT_WL_CNDTW": "bolt.square.fill",
        "DEFAULT_WL_EWALL": "door.sliding.left.hand.open", "DEFAULT_WL_DTECT": "sensor",
        "DEFAULT_WL_STRM": "wind", "DEFAULT_WL_FAN": "fanblades.fill",
        "DEFAULT_WL_LIQD": "pipe.and.drop.fill", "DEFAULT_WL_ABSRB": "arrow.down.to.line.compact",
        "DEFAULT_WL_WALL": "square.fill", "DEFAULT_WL_AIR": "wind.circle",
        "DEFAULT_WL_POWDR": "line.3.horizontal.decrease", "DEFAULT_WL_CNDTR": "bolt.horizontal.circle.fill",
        "DEFAULT_WL_EHOLE": "arrow.down.square.fill", "DEFAULT_WL_GAS": "cloud.drizzle",
        "DEFAULT_WL_GRVTY": "arrow.down.right.and.arrow.up.left.square",
        "DEFAULT_WL_ENRGY": "bolt.shield.fill",
        "DEFAULT_WL_NOAIR": "wind.circle.fill", "DEFAULT_WL_ERASEA": "clear.fill",
        "DEFAULT_WL_STASIS": "pause.rectangle.fill"
    ]
}

extension EngineElement {
    var paletteSymbol: String { MaterialSymbolCatalog.materials[identifier] ?? "questionmark.square.dashed" }
}

extension EngineWallType {
    var paletteSymbol: String { MaterialSymbolCatalog.walls[identifier] ?? "questionmark.square.dashed" }
}
