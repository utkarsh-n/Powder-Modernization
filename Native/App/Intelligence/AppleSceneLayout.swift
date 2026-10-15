import Foundation
import FoundationModels
import PowderCore
import PowderEngine

/// The model chooses semantic components. This compiler owns only reusable
/// geometry primitives and never examines the user's prompt or selects a scene.
@available(macOS 26.0, *)
enum AppleSceneLayout {
    static var instructions: String {
        let categories = Set(EngineElement.allCases.map(\.category)).sorted()
        let catalog = categories.map { category in
            category + ": " + EngineElement.allCases.filter { $0.category == category }
                .map(\.identifier).joined(separator: ",")
        }.joined(separator: "\n")
        return """
        Compose a small playable scene in the fictional Powder Toy videogame.
        Choose 1 to 8 components that fulfill the user's confirmed request, or zero components only
        for an explicitly empty container. Never invent an extra component to reach an item count.
        The native app lays out the chosen components.
        Preserve every requested component, including the container. If the user asks for a tank,
        chamber or vessel, set containerMaterial to its requested solid material (glass is GLAS).
        Set containerMaterial to NONE when no surrounding container is requested. A requested wall,
        floor or standalone solid is an item, not permission to surround the whole scene with a tank.
        Preserve the confirmed containerShape: rectangular is a closed rectangular chamber, circular
        is a round closed chamber, openTank has two sides and a bottom with no lid. All are hollow.
        Do not replace a requested circle with a rectangle. If unspecified, use rectangular.
        Do not add container walls as items. Items are the contents and working components.
        Preserve the confirmed composition: balanced gives even spacing, compact groups components
        closer, spacious gives smaller components more motion room, layered makes powder/liquid
        regions into wider shallow bands. Composition never changes requested materials or vertical
        relationships. If no layout style is specified, use balanced. Other artistic styles are not
        fabricated: explain any unsupported visual detail in warning and retain the requested function.
        Vertical upper means above middle, and middle means above lower. Gravity pulls toward lower.
        Preserve the user's spatial relationships: something above another item uses a higher placement.
        Choose pile for loose powders, pool for liquid, block for solids/devices, cluster for particles,
        and line for a trace. Size 1 is small, 2 medium, 3 large. Keep empty space for motion.
        connectToPrevious draws a touching trace of this item's material to the preceding item.
        Use it only when physical contact is intended; independent, falling and liquid items use false.
        Use exact element codes from the catalog. Temperature is Celsius; use null unless a special
        temperature is requested. Normal room temperature is 20, not 0.
        Leave configuration null unless the user explicitly needs advanced device or particle settings.
        State the expected game behavior, and disclose unsupported or uncertain requests.
        \(EngineKnowledge.rules)
        CATALOG:\n\(catalog)
        """
    }

    static func compile(_ draft: AppleSceneDraft, width: Int, height: Int) throws -> ScenePlan {
        guard (8...612).contains(width), (8...384).contains(height) else { throw ScenePlanError.invalidDimensions }
        guard (0...8).contains(draft.items.count) else { throw ScenePlanError.invalidCommandCount }
        guard !draft.items.isEmpty || optionalCode(draft.containerMaterial) != nil else {
            throw LayoutError.invalid("An empty scene needs a real container. Include the requested component or choose its container material.")
        }
        let container = try containerGeometry(draft, width: width, height: height)
        var commands = container.commands
        var previous: Bounds?
        for (index, item) in draft.items.enumerated() {
            try Task.checkCancellation()
            let material = try resolve(item.material, index: index)
            guard material != .empty else {
                throw LayoutError.invalid("Items must contain particles. The compiler already provides empty space.")
            }
            guard (1...3).contains(item.size) else { throw ScenePlanError.invalidValue(index, "size") }
            if item.connectToPrevious && (item.shape == .pile || item.shape == .pool) {
                throw LayoutError.invalid("Loose piles and liquid pools need motion space. Set connectToPrevious to false for \(item.role).")
            }
            guard !item.connectToPrevious || previous != nil else {
                throw LayoutError.invalid("The first component has nothing to connect to. Set connectToPrevious to false.")
            }
            let temperature = item.temperature ?? Double(material.defaultTemperature)
            let bounds = bounds(for: item, index: index, items: draft.items,
                                area: container.area, composition: draft.composition)
            if item.connectToPrevious, let previous {
                let vertical = abs(bounds.y - previous.y) > abs(bounds.x - previous.x)
                let direction = vertical ? (bounds.y >= previous.y ? 1.0 : -1.0)
                                         : (bounds.x >= previous.x ? 1.0 : -1.0)
                // Start one raster cell outside the preceding shape so its material
                // remains intact while the new trace physically touches it.
                let startX = vertical ? previous.x : previous.x + direction * (previous.halfWidth + 1 / Double(width - 1))
                let startY = vertical ? previous.y + direction * (previous.halfHeight + 1 / Double(height - 1)) : previous.y
                let finishX = vertical ? bounds.x : bounds.x - direction * bounds.halfWidth
                let finishY = vertical ? bounds.y - direction * bounds.halfHeight : bounds.y
                let elbowX = vertical ? startX : finishX
                let elbowY = vertical ? finishY : startY
                for segment in [(startX, startY, elbowX, elbowY), (elbowX, elbowY, finishX, finishY)] {
                    var command = SceneCommand(shape: .line, material: material.identifier, role: "Connection: \(item.role)",
                        x1: segment.0, y1: segment.1, x2: segment.2, y2: segment.3,
                        radius: 0, temperature: temperature)
                    try applyProperties(item, to: &command, index: index)
                    commands.append(command)
                }
            }
            var command = SceneCommand(shape: .rectangle, material: material.identifier, role: item.role,
                x1: bounds.x - bounds.halfWidth, y1: bounds.y - bounds.halfHeight,
                x2: bounds.x + bounds.halfWidth, y2: bounds.y + bounds.halfHeight,
                temperature: temperature)
            switch item.shape {
            case .pile:
                command.shape = .scatter
                command.density = 0.65
            case .pool, .block: break
            case .cluster:
                command.shape = .circle
                command.x1 = bounds.x; command.y1 = bounds.y
                command.x2 = 0; command.y2 = 0
                command.radius = min(bounds.halfWidth * Double(width - 1), bounds.halfHeight * Double(height - 1)) /
                    Double(min(width, height))
            case .line:
                command.shape = .line
                command.y1 = bounds.y; command.y2 = bounds.y
                command.radius = 0
            }
            try applyProperties(item, to: &command, index: index)
            commands.append(command)
            // Connections use actual geometry bounds rather than a square footprint
            // around a thin line or a circular cluster.
            var connectorBounds = bounds
            if item.shape == .line { connectorBounds.halfHeight = 0 }
            if item.shape == .cluster {
                connectorBounds.halfWidth = command.radius * Double(min(width, height)) / Double(width - 1)
                connectorBounds.halfHeight = command.radius * Double(min(width, height)) / Double(height - 1)
            }
            previous = connectorBounds
        }
        var warnings = draft.warning.isEmpty ? [] : [draft.warning]
        warnings.append("On-device scenes use bounded geometric layouts. Complex machinery and finer artistic detail may need Cloud or manual editing; the predicted reaction is not guaranteed.")
        return try ScenePlan(title: draft.title, explanation: draft.explanation, commands: commands,
            expectations: [draft.expectedBehavior], warnings: warnings)
            .validated(forWidth: width, height: height, allowedMaterials: EngineElement.allowedIdentifiers,
                       maximumTemperature: 9_725)
    }

    static func review(_ plan: ScenePlan) throws {
        try Task.checkCancellation()
        let world = try EngineScenes.makeWorld(plan)
        let particles = world.particles()
        let present = Set(particles.map { $0.material.identifier })
        for material in Set(plan.commands.map(\.material)) where material != "NONE" && !present.contains(material) {
            throw LayoutError.invalid("\(material) did not produce particles. It may require another element or a configured device.")
        }
        let matterCells = Set(particles.filter { !$0.material.isEnergy }.map {
            Int($0.y.rounded()) * world.width + Int($0.x.rounded())
        })
        guard Double(matterCells.count) < Double(world.width * world.height) * 0.55 else {
            throw LayoutError.invalid("The composition is too crowded to leave useful motion space. Use fewer or smaller items.")
        }
        try Task.checkCancellation()
    }

    private struct Bounds {
        var x: Double, y: Double, halfWidth: Double, halfHeight: Double
    }

    private struct PlacementArea {
        var left: Double, right: Double, top: Double, bottom: Double
        var width: Double { right - left }
        var height: Double { bottom - top }
    }

    private static func containerGeometry(_ draft: AppleSceneDraft, width: Int, height: Int) throws
        -> (commands: [SceneCommand], area: PlacementArea) {
        guard let code = optionalCode(draft.containerMaterial) else {
            return ([], PlacementArea(left: 0.12, right: 0.88, top: 0.11, bottom: 0.89))
        }
        let material = try resolve(code, index: 0)
        guard material.properties & 0x04 != 0 else {
            throw LayoutError.invalid("A container must use a solid element; \(code) is not solid.")
        }
        let temperature = Double(material.defaultTemperature)
        if draft.containerShape == .circular {
            // ScenePlan caps a filled circle's radius at 0.25. A bounded closed
            // polyline gives a larger hollow vessel without painting a filled disk
            // or weakening that validation limit. Pixel-space radii keep it round.
            let shortSide = Double(min(width, height))
            let radius = Double(min(width - 1, height - 1)) * 0.40
            let thickness = max(1, (shortSide * 0.008).rounded())
            let centerX = Double(width - 1) * 0.5, centerY = Double(height - 1) * 0.51
            let segments = 64
            let commands = (0..<segments).map { index in
                let first = Double(index) * 2 * Double.pi / Double(segments)
                let next = Double(index + 1) * 2 * Double.pi / Double(segments)
                return SceneCommand(shape: .line, material: material.identifier, role: "Circular container wall",
                    x1: (centerX + cos(first) * radius) / Double(width - 1),
                    y1: (centerY + sin(first) * radius) / Double(height - 1),
                    x2: (centerX + cos(next) * radius) / Double(width - 1),
                    y2: (centerY + sin(next) * radius) / Double(height - 1),
                    radius: thickness / shortSide, temperature: temperature)
            }
            // Contents and orthogonal connections fit the inscribed rectangle.
            // Leave extra raster space so rounding cannot overwrite the ring.
            let half = max(0.5, radius - thickness - 3) / sqrt(2)
            return (commands, PlacementArea(left: (centerX - half) / Double(width - 1),
                right: (centerX + half) / Double(width - 1), top: (centerY - half) / Double(height - 1),
                bottom: (centerY + half) / Double(height - 1)))
        }
        let left = 0.10, right = 0.90, top = 0.08, bottom = 0.94
        let thickness = max(1, (Double(min(width, height)) * 0.014).rounded())
        let dx = thickness / Double(width - 1), dy = thickness / Double(height - 1)
        var commands: [SceneCommand] = [
            .init(shape: .rectangle, material: material.identifier, role: "Container left wall",
                  x1: left, y1: top, x2: left + dx, y2: bottom, temperature: temperature),
            .init(shape: .rectangle, material: material.identifier, role: "Container right wall",
                  x1: right - dx, y1: top, x2: right, y2: bottom, temperature: temperature),
            .init(shape: .rectangle, material: material.identifier, role: "Container floor",
                  x1: left, y1: bottom - dy, x2: right, y2: bottom, temperature: temperature)
        ]
        if draft.containerShape == .rectangular {
            commands.append(.init(shape: .rectangle, material: material.identifier, role: "Container lid",
                x1: left, y1: top, x2: right, y2: top + dy, temperature: temperature))
        }
        return (commands, PlacementArea(left: max(0.14, left + dx * 2),
            right: min(0.86, right - dx * 2), top: max(0.15, top + dy * 2),
            bottom: min(0.87, bottom - dy * 2)))
    }

    private static func bounds(for item: AppleSceneItem, index: Int, items: [AppleSceneItem],
                               area: PlacementArea, composition: AppleComposition) -> Bounds {
        let peers = items.indices.filter { items[$0].vertical == item.vertical }.sorted {
            let first = items[$0].horizontal.order, second = items[$1].horizontal.order
            return first == second ? $0 < $1 : first < second
        }
        let rank = peers.firstIndex(of: index) ?? 0
        let span = area.width * (composition == .compact ? 0.72 : 1)
        let left = (area.left + area.right - span) / 2
        let x = peers.count == 1 ? left + span * [0.2, 0.5, 0.8][item.horizontal.order]
            : left + span * (Double(rank) + 0.5) / Double(peers.count)
        let rowGap = composition == .compact ? 0.22 : composition == .spacious ? 0.40 : 0.36
        let row = item.vertical == .upper ? 0.5 - rowGap : item.vertical == .middle ? 0.5 : 0.5 + rowGap
        let y = area.top + area.height * row
        let styleScale = composition == .compact ? 0.9 : composition == .spacious ? 0.8 : 1
        let scale = [0.06, 0.10, 0.145][item.size - 1] * min(area.width, area.height) * styleScale
        let layered = composition == .layered
        let requestedHalfWidth = scale * (item.shape == .pool ? (layered ? 2.8 : 2) : item.shape == .pile ? (layered ? 2.1 : 1.5) : 1)
        let halfWidth = min(requestedHalfWidth, span * 0.39 / Double(peers.count), x - area.left, area.right - x)
        let requestedHalfHeight = scale * (item.shape == .pile ? (layered ? 0.30 : 0.45) : item.shape == .pool ? (layered ? 0.38 : 0.55) : 0.75)
        let halfHeight = min(requestedHalfHeight, area.height * rowGap * 0.42, y - area.top, area.bottom - y)
        return Bounds(x: x, y: y, halfWidth: halfWidth, halfHeight: halfHeight)
    }

    private static func resolve(_ name: String, index: Int) throws -> EngineElement {
        guard let material = EngineElement.named(name.trimmingCharacters(in: .whitespacesAndNewlines)) else {
            throw ScenePlanError.unknownMaterial(index, name)
        }
        return material
    }

    private static func applyProperties(_ item: AppleSceneItem, to command: inout SceneCommand, index: Int) throws {
        guard let configuration = item.configuration else { return }
        if let ctype = optionalCode(configuration.ctype) { command.ctype = try resolve(ctype, index: index).identifier }
        command.life = configuration.life; command.tmp = configuration.tmp; command.tmp2 = configuration.tmp2
    }

    private static func optionalCode(_ value: String?) -> String? {
        guard let code = value?.trimmingCharacters(in: .whitespacesAndNewlines),
              !["", "NULL", "NIL", "NONE"].contains(code.uppercased()) else { return nil }
        return code
    }

    private enum LayoutError: LocalizedError {
        case invalid(String)
        var errorDescription: String? { if case .invalid(let message) = self { message } else { nil } }
    }
}

@available(macOS 26.0, *)
@Generable
struct AppleSceneDraft {
    @Guide(description: "Required element code for the requested tank or chamber: glass is GLAS. Use NONE only when no container was requested")
    var containerMaterial: String
    @Guide(description: "Short scene name") var title: String
    @Guide(description: "One sentence including every requested component and its relative position") var explanation: String
    @Guide(description: "Only requested contents and working components, in causal order; 1 to 8 normally, zero only for an explicitly empty container; no filler or container walls", .count(0...8))
    var items: [AppleSceneItem]
    @Guide(description: "One sentence of expected game behavior") var expectedBehavior: String
    @Guide(description: "Unsupported or uncertain aspects, or empty string") var warning: String
    @Guide(description: "Confirmed surrounding container geometry: rectangular closed chamber, circular closed chamber, or openTank with no lid; ignored when containerMaterial is NONE")
    var containerShape: AppleContainerShape = .rectangular
    @Guide(description: "Confirmed layout style: balanced, compact, spacious, or layered; preserve component relationships and materials")
    var composition: AppleComposition = .balanced
}

@available(macOS 26.0, *)
@Generable
enum AppleContainerShape { case rectangular, circular, openTank }

@available(macOS 26.0, *)
@Generable
enum AppleComposition { case balanced, compact, spacious, layered }

@available(macOS 26.0, *)
@Generable
enum AppleVertical { case upper, middle, lower }

@available(macOS 26.0, *)
@Generable
enum AppleHorizontal {
    case left, center, right
    var order: Int { switch self { case .left: 0; case .center: 1; case .right: 2 } }
}

@available(macOS 26.0, *)
@Generable
enum ApplePrimitive { case pile, pool, block, line, cluster }

@available(macOS 26.0, *)
@Generable
struct AppleSceneItem {
    @Guide(description: "Exact uppercase element code from the catalog") var material: String
    @Guide(description: "Short functional purpose") var role: String
    var vertical: AppleVertical
    var horizontal: AppleHorizontal
    var shape: ApplePrimitive
    @Guide(description: "1 small, 2 medium, 3 large", .range(1...3)) var size: Int
    @Guide(description: "Celsius, or null to use the element's original default") var temperature: Double?
    @Guide(description: "False for independent, falling or liquid items. True only for a solid trace or trigger intended to touch the previous component")
    var connectToPrevious: Bool
    @Guide(description: "Null unless the user explicitly requested advanced particle or device settings")
    var configuration: AppleParticleConfiguration?
}

@available(macOS 26.0, *)
@Generable
struct AppleParticleConfiguration {
    var ctype: String?
    var life: Int?
    var tmp: Int?
    var tmp2: Int?
}
