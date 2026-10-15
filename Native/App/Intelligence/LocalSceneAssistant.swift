import Foundation
import PowderCore
import PowderEngine
import PowderIntelligence

/// A bounded catalog-and-layout builder. It never calls a language model.
struct LocalSceneAssistant: SceneAssistantService {
    private static let descriptorPrefix = "POWDER_LOCAL_LAYOUT_V1:"

    static func canHandle(_ turns: [SceneConversationTurn]) -> Bool {
        let users = turns.filter { $0.role == .user }
        guard !users.contains(where: { requiresComplexLayout(tokens($0.text)) }) else { return false }
        return users.contains {
            let words = tokens($0.text)
            return !mentions(words).isEmpty || words.contains(where: { ["explosive", "explosives", "explosion", "blast"].contains($0) })
                || words.contains("nuclear") || words.contains("radioactive")
        }
    }

    static func canPlan(_ proposal: SceneProposal) -> Bool {
        (try? layout(for: proposal)) != nil
    }

    func discuss(_ turns: [SceneConversationTurn], context: SceneAssistantContext) async throws -> SceneConsultation {
        try Task.checkCancellation()
        let userTurns = turns.filter { $0.role == .user }
        guard !userTurns.isEmpty, userTurns.allSatisfy({ !$0.text.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty }) else {
            throw SceneGenerationError.invalidPrompt
        }
        var request = Request()
        // Only our validated, versioned design snapshot can restore condensed
        // history. Assistant prose and community references never supply materials.
        var start = turns.startIndex
        for (index, turn) in turns.enumerated() where turn.role == .assistant && turn.text.hasPrefix("Current proposed design:") {
            if let range = turn.text.range(of: Self.descriptorPrefix),
               let data = String(turn.text[range.upperBound...]).data(using: .utf8),
               let saved = try? JSONDecoder().decode(Layout.self, from: data), (try? saved.validate()) != nil {
                request.restore(saved); start = index + 1
            }
        }
        for turn in turns.dropFirst(start) where turn.role == .user { request.read(turn.text) }
        var requestedContents = request.materials.filter { $0 != request.container }
        if request.ignite && !requestedContents.contains("FIRE") { requestedContents.append("FIRE") }
        var questions: [SceneQuestion] = []
        let incompleteRings = request.shape == .concentric && !request.concentricEnabled
        if (request.complex && !request.acceptedSimplification) || incompleteRings {
            questions.append(.init(title: "Supported local layout?", options: ["Simple material chamber", "Separate material samples"]))
        } else if request.shape == nil && !context.proposalRequested {
            questions.append(.init(title: "Container shape?", options: ["Rectangular", "Circular", "Open tank"]))
        }
        if request.concentricEnabled, request.coatingMaterial != nil, request.coatingPlacement == nil {
            questions.append(request.coatingQuestion)
        } else if request.needsNuclearChoice {
            questions.append(.init(title: "Radioactive game material?", options: ["Plutonium (PLUT)", "Uranium (URAN)", "Deuterium (DEUT)"]))
        } else if request.needsExplosiveChoice {
            questions.append(.init(title: "Explosive material?", options: ["Gunpowder (GUNP)", "Plastic explosive (PLEX)", "Diesel (DESL)"]))
        } else if request.materials.isEmpty {
            questions.append(.init(title: "Game material?", options: ["Sand (SAND)", "Water (WATR)", "Gunpowder (GUNP)", "Glass (GLAS)"]))
        } else if request.wantsContainer && request.container == nil {
            questions.append(.init(title: "Container material?", options: ["Glass (GLAS)", "Brick (BRCK)", "Metal (METL)"]))
        } else if requestedContents.count > 8 {
            questions.append(.init(title: "Choose at most eight contents?", options: [
                "Use only: " + requestedContents.prefix(8).joined(separator: ", "),
                "Use only: " + requestedContents.suffix(8).joined(separator: ", ")
            ]))
        }
        if request.style == nil && !context.proposalRequested && questions.count < 3 {
            questions.append(.init(title: "Composition?", options: ["Balanced", "Compact", "Spacious", "Layered"]))
        }
        if !questions.isEmpty {
            let explanation = (request.complex && !request.acceptedSimplification) || incompleteRings
                ? "The local builder can arrange game materials, but cannot reproduce that machine or its connections. Choose a simpler layout to continue."
                : "I can build this from the game's material catalog on this Mac. Choose the missing layout details; a preview comes before placement."
            return try SceneConsultation(reply: explanation, questions: Array(questions.prefix(3)), proposal: nil, referenceIDs: [])
                .validated(materials: EngineElement.allowedIdentifiers, references: [])
        }
        let shape = request.shape ?? (request.wantsContainer ? .rectangular : .samples)
        let container = shape.isContainer ? request.container : nil
        guard !shape.isContainer || container != nil else { throw LocalSceneError.unsupported("Choose a solid container material first.") }
        var contents = request.materials.filter { $0 != container }
        if request.emptyContainer { contents = [] }
        if request.ignite && !contents.contains("FIRE") { contents.append("FIRE") }
        var layout = Layout(shape: shape, style: request.style ?? .balanced, container: container,
                            contents: contents, simplified: request.acceptedSimplification)
        if request.concentricEnabled {
            guard let outer = request.ringMaterial, let core = request.coreMaterial else {
                throw LocalSceneError.unsupported("A concentric layout needs a named outer ring and a named center ball.")
            }
            layout.concentric = Concentric(outerRing: outer, core: core, coating: request.coatingMaterial,
                                            placement: request.coatingPlacement)
        }
        try layout.validate()
        let materialCodes = layout.materials
        let descriptor = String(decoding: try JSONEncoder().encode(layout), as: UTF8.self)
        let proposal = SceneProposal(title: "\(shape.title) · \(materialCodes.joined(separator: ", "))",
            shape: shape.title, materials: materialCodes, style: layout.style.rawValue,
            behavior: layout.concentric?.behavior ?? (request.ignite || contents.contains("FIRE") ? "Starts with explicitly requested in-game fire. Reactions follow the original game and are checked in the preview."
                : "Starts without an added ignition source. Gravity and reactions follow the original game; containment and stability are not guaranteed."),
            buildPrompt: Self.descriptorPrefix + descriptor)
        try Task.checkCancellation()
        return try SceneConsultation(reply: "The local builder will prepare this \(shape.title.lowercased()) using the selected game materials. Review the initial layout and short trial before placing it.",
            questions: [], proposal: proposal, referenceIDs: [])
            .validated(materials: EngineElement.allowedIdentifiers, references: [])
    }

    func plan(_ proposal: SceneProposal, context: SceneAssistantContext) async throws -> ScenePlan {
        try Task.checkCancellation()
        let layout: Layout
        do { layout = try Self.layout(for: proposal) }
        catch {
            try Task.checkCancellation()
            var parsed = Request(); parsed.read(proposal.shape + " " + proposal.buildPrompt)
            if parsed.concentricEnabled, parsed.coatingMaterial != nil, parsed.coatingPlacement == nil {
                throw LocalScenePlanningError.needsChoices(SceneConsultation(
                    reply: "The concentric materials are supported, but the coating's position needs your choice before construction.",
                    questions: [parsed.coatingQuestion], proposal: nil, referenceIDs: []))
            }
            let codes = proposal.materials.compactMap { EngineElement.named($0)?.identifier }.filter { $0 != "NONE" }
            let materials = codes.joined(separator: ", ")
            throw LocalScenePlanningError.needsChoices(SceneConsultation(
                reply: "The local builder cannot reproduce every relationship in that proposal. Choose a supported arrangement of the approved game materials; the existing canvas is unchanged.",
                questions: [.init(title: "Supported local layout?", options: [
                    "Simple material chamber (\(materials))", "Separate material samples (\(materials))"
                ])], proposal: nil, referenceIDs: []))
        }
        guard (8...612).contains(context.width), (8...384).contains(context.height) else { throw ScenePlanError.invalidDimensions }
        let width = Double(context.width - 1), height = Double(context.height - 1)
        let short = Double(min(context.width, context.height) - 1)
        let stroke = max(1, min(2, short / 60)) / Double(min(context.width, context.height))
        var commands: [SceneCommand] = []
        let span: Double = layout.style == .compact ? 0.46 : layout.style == .spacious ? 0.78 : 0.64
        var bounds = Bounds(left: 0.5 - span / 2, top: 0.18, right: 0.5 + span / 2, bottom: 0.86)
        if let concentric = layout.concentric {
            commands = try Self.concentricCommands(concentric, style: layout.style, width: context.width, height: context.height)
        } else {
        if let shell = layout.container {
            if layout.shape == .circular {
                let radius = short * (layout.style == .compact ? 0.29 : layout.style == .spacious ? 0.41 : 0.35)
                for index in 0..<64 {
                    let a = Double(index) * 2 * Double.pi / 64
                    let b = Double(index + 1) * 2 * Double.pi / 64
                    commands.append(.init(shape: .line, material: shell, role: "Hollow circular container wall",
                        x1: 0.5 + cos(a) * radius / width, y1: 0.5 + sin(a) * radius / height,
                        x2: 0.5 + cos(b) * radius / width, y2: 0.5 + sin(b) * radius / height, radius: stroke))
                }
                let inner = max(1, (radius - stroke * short - 4) / sqrt(2))
                bounds = Bounds(left: 0.5 - inner / width, top: 0.5 - inner / height,
                                right: 0.5 + inner / width, bottom: 0.5 + inner / height)
            } else {
                let b = bounds
                commands += [
                    .init(shape: .line, material: shell, role: "Left container wall", x1: b.left, y1: b.top, x2: b.left, y2: b.bottom, radius: stroke),
                    .init(shape: .line, material: shell, role: "Right container wall", x1: b.right, y1: b.top, x2: b.right, y2: b.bottom, radius: stroke),
                    .init(shape: .line, material: shell, role: "Container floor", x1: b.left, y1: b.bottom, x2: b.right, y2: b.bottom, radius: stroke)
                ]
                if layout.shape == .rectangular {
                    commands.append(.init(shape: .line, material: shell, role: "Container lid", x1: b.left, y1: b.top,
                                          x2: b.right, y2: b.top, radius: stroke))
                }
                bounds = b.inset(x: max(0.015, 4 / width), y: max(0.025, 4 / height))
            }
        }
        let count = layout.contents.count
        for (index, code) in layout.contents.enumerated() {
            try Task.checkCancellation()
            let element = try Self.element(code)
            let x1: Double, x2: Double, y1: Double, y2: Double
            if layout.shape == .wall {
                let center = bounds.left + bounds.width * Double(index + 1) / Double(count + 1)
                x1 = center - 0.008; x2 = center + 0.008; y1 = bounds.top; y2 = bounds.bottom
            } else if layout.style == .layered {
                let slice = bounds.height * 0.68 / Double(count)
                x1 = bounds.left + bounds.width * 0.1; x2 = bounds.right - bounds.width * 0.1
                y2 = bounds.bottom - Double(index) * slice; y1 = y2 - slice * 0.65
            } else {
                let slice = bounds.width / Double(max(1, count))
                x1 = bounds.left + Double(index) * slice + slice * 0.16
                x2 = bounds.left + Double(index + 1) * slice - slice * 0.16
                y1 = bounds.top + bounds.height * 0.55; y2 = bounds.bottom - bounds.height * 0.04
            }
            commands.append(.init(shape: .rectangle, material: code, role: layout.shape == .wall ? "\(code) wall" : "\(code) material sample",
                                  x1: x1, y1: y1, x2: x2, y2: y2, temperature: Double(element.defaultTemperature)))
        }
        }
        var warnings = ["Local catalog layout: component geometry is deterministic. The 45-step preview is evidence of initial behavior, not proof of a working machine."]
        if layout.simplified { warnings.append("You selected a simplified material layout; the original machine or connection pattern is not reproduced.") }
        if layout.container == "GLAS" { warnings.append("Original-game glass can break under pressure; this is not guaranteed containment.") }
        if let rings = layout.concentric {
            warnings.append("Rings describe the initial arrangement, not permanent containment. Materials retain their original game behavior.")
            if rings.coating == "URAN" { warnings.append("URAN is falling powder: its coating settles under gravity during playback rather than remaining a rigid shell.") }
            if rings.core == "FIRE" { warnings.append("The FIRE ball starts hot with the game's normal lifetime; it may decay or ignite nearby WOOD during the trial.") }
        }
        let plan = ScenePlan(title: proposal.title, explanation: "Built on this device from catalog identifiers and the approved \(layout.shape.title.lowercased()) layout; no language model was used for construction.",
            commands: commands, expectations: [proposal.behavior], warnings: warnings)
        try plan.validated(forWidth: context.width, height: context.height, allowedMaterials: EngineElement.allowedIdentifiers, maximumTemperature: 9_725)
        try Task.checkCancellation()
        return plan
    }

    private static func layout(for proposal: SceneProposal) throws -> Layout {
        let layout: Layout
        if proposal.buildPrompt.hasPrefix(descriptorPrefix) {
            let text = String(proposal.buildPrompt.dropFirst(descriptorPrefix.count))
            guard text.utf8.count < 4_096 else { throw SceneGenerationError.invalidResponse }
            layout = try JSONDecoder().decode(Layout.self, from: Data(text.utf8))
            guard Shape.read(tokens(proposal.shape)) == layout.shape, Style.read(tokens(proposal.style)) == layout.style else {
                throw LocalSceneError.unsupported("The saved local layout disagrees with the reviewed shape or composition. Discuss the revised design first.")
            }
        } else {
            let words = tokens(proposal.shape + " " + proposal.buildPrompt)
            guard !requiresComplexLayout(words), let shape = Shape.read(tokens(proposal.shape)) ?? Shape.read(words),
                  let style = Style.read(tokens(proposal.style)) else {
                throw LocalSceneError.unsupported("This proposal needs relationships or styling the local builder cannot reproduce. Discuss a simple chamber, wall, or separate samples before building.")
            }
            let codes = try proposal.materials.map { try element($0).identifier }
            var parsed = Request(); parsed.read(proposal.shape + " " + proposal.buildPrompt)
            let solids = codes.filter { (EngineElement.named($0)?.properties ?? 0) & 0x04 != 0 }
            let shell = shape.isContainer ? (parsed.container ?? (solids.count == 1 ? solids.first : nil)) : nil
            if parsed.concentricEnabled {
                guard let outer = parsed.ringMaterial, let core = parsed.coreMaterial else {
                    throw LocalSceneError.unsupported("Specify the outer ring and central ball materials.")
                }
                var rings = Layout(shape: .concentric, style: style, container: outer,
                                   contents: codes.filter { $0 != outer }, simplified: false)
                rings.concentric = Concentric(outerRing: outer, core: core, coating: parsed.coatingMaterial, placement: parsed.coatingPlacement)
                layout = rings
            } else {
                layout = Layout(shape: shape, style: style, container: shell, contents: codes.filter { $0 != shell }, simplified: false)
            }
        }
        try layout.validate()
        let expected = try Set(proposal.materials.map { try element($0).identifier })
        guard Set(layout.materials) == expected else { throw LocalSceneError.unsupported("The local layout does not preserve every approved material. Discuss the revised design first.") }
        return layout
    }

    private struct Layout: Codable {
        let shape: Shape
        let style: Style
        let container: String?
        let contents: [String]
        let simplified: Bool
        var concentric: Concentric? = nil
        var materials: [String] { (container.map { [$0] } ?? []) + contents }
        func validate() throws {
            guard contents.count <= 8, !materials.isEmpty, Set(materials).count == materials.count else {
                throw LocalSceneError.unsupported("Choose one to eight material samples, optionally inside one solid container.")
            }
            for code in materials { _ = try LocalSceneAssistant.element(code) }
            if let rings = concentric {
                guard shape == .concentric, container == rings.outerRing,
                      Set(materials) == Set([rings.outerRing, rings.core] + (rings.coating.map { [$0] } ?? [])),
                      rings.coating == nil || rings.placement != nil else {
                    throw LocalSceneError.unsupported("Confirm the named rings, center material and coating position before building.")
                }
            } else if shape == .concentric { throw SceneGenerationError.invalidResponse }
            if shape.isContainer {
                guard let container, try LocalSceneAssistant.element(container).properties & 0x04 != 0 else {
                    throw LocalSceneError.unsupported("A chamber needs an explicitly selected solid container material.")
                }
            } else if container != nil { throw SceneGenerationError.invalidResponse }
        }
    }

    private enum CoatingPlacement: String, Codable {
        case aroundCore, outsideOuter
    }
    private struct Concentric: Codable {
        let outerRing: String
        let core: String
        let coating: String?
        let placement: CoatingPlacement?
        var behavior: String {
            let coatingDescription = coating.map { " \($0) forms a ring \(placement == .outsideOuter ? "outside the \(outerRing) ring" : "around the \(core) ball")." } ?? ""
            return "\(outerRing) outer ring with a \(core) center ball.\(coatingDescription) "
                + (core == "FIRE" ? "FIRE starts hot and has its normal game lifetime. " : "Materials start at their normal game temperatures. ")
                + "Powders settle; the rings are an initial arrangement."
        }
    }

    private static func concentricCommands(_ rings: Concentric, style: Style, width: Int, height: Int) throws -> [SceneCommand] {
        guard min(width, height) >= 64 else { throw LocalSceneError.unsupported("Concentric rings need a canvas at least 64 cells across to preserve the separate layers.") }
        let w = Double(width - 1), h = Double(height - 1), short = Double(min(width, height) - 1)
        let outerRadius = short * (style == .compact ? 0.25 : style == .spacious ? 0.37 : 0.32)
        let strokePixels = max(1, min(2, short / 60))
        let coreRadius = max(1, outerRadius * 0.25)
        func ring(_ material: String, _ radius: Double, _ role: String) throws -> [SceneCommand] {
            let temperature = Double(try element(material).defaultTemperature)
            // Two 48-segment rings and a core stay below ScenePlan's 128-command limit.
            return (0..<48).map { index in
                let a = Double(index) * 2 * Double.pi / 48, b = Double(index + 1) * 2 * Double.pi / 48
                return .init(shape: .line, material: material, role: role,
                    x1: 0.5 + cos(a) * radius / w, y1: 0.5 + sin(a) * radius / h,
                    x2: 0.5 + cos(b) * radius / w, y2: 0.5 + sin(b) * radius / h,
                    radius: strokePixels / Double(min(width, height)), temperature: temperature)
            }
        }
        var commands = try ring(rings.outerRing, outerRadius, "Outer \(rings.outerRing) ring")
        if let coating = rings.coating {
            let radius = rings.placement == .outsideOuter ? outerRadius + max(5, short * 0.04) : coreRadius + strokePixels + 1
            commands += try ring(coating, radius, rings.placement == .outsideOuter
                ? "\(coating) coating outside outer ring" : "\(coating) coating around center ball")
        }
        commands.append(.init(shape: .circle, material: rings.core, role: "Central \(rings.core) ball", x1: 0.5, y1: 0.5,
                              radius: coreRadius / Double(min(width, height)), temperature: Double(try element(rings.core).defaultTemperature)))
        return commands
    }

    private enum Shape: String, Codable {
        case rectangular, circular, openTank, wall, samples, concentric
        var isContainer: Bool { self == .rectangular || self == .circular || self == .openTank || self == .concentric }
        var title: String {
            switch self { case .rectangular: "Rectangular chamber"; case .circular: "Circular chamber"; case .openTank: "Open tank"; case .wall: "Vertical wall"; case .samples: "Separate material samples"; case .concentric: "Concentric circular rings" }
        }
        static func read(_ words: [String]) -> Self? {
            if contains(words, ["separate", "material", "samples"]) || contains(words, ["no", "container"]) { return .samples }
            if words.contains("concentric") { return .concentric }
            if words.contains("wall") && !words.contains(where: { ["inside", "containing", "contain", "filled", "enclose", "enclosed", "container"].contains($0) }) { return .wall }
            var result: Self?
            for (index, word) in words.enumerated() {
                let preceding = Array(words[max(0, index - 2)..<index])
                if preceding == ["instead", "of"] || preceding.last == "not" || preceding.last == "no" { continue }
                if ["circular", "circle", "round", "ring"].contains(word) { result = .circular }
                if ["rectangular", "rectangle", "square"].contains(word) { result = .rectangular }
                if word == "tank", preceding.last == "open" { result = .openTank }
            }
            return result
        }
    }
    private enum Style: String, Codable {
        case balanced, compact, spacious, layered
        static func read(_ words: [String]) -> Self? { words.reversed().compactMap(Self.init(rawValue:)).first }
    }
    private struct Bounds {
        let left: Double, top: Double, right: Double, bottom: Double
        var width: Double { right - left }; var height: Double { bottom - top }
        func inset(x: Double, y: Double) -> Self { Self(left: left + x, top: top + y, right: right - x, bottom: bottom - y) }
    }

    private struct Request {
        var materials: [String] = []
        var container: String?
        var shape: Shape?
        var style: Style?
        var wantsContainer = false
        var needsExplosiveChoice = false
        var needsNuclearChoice = false
        var emptyContainer = false
        var ignite = false
        var complex = false
        var acceptedSimplification = false
        var ringMaterial: String?
        var coreMaterial: String?
        var coatingMaterial: String?
        var coatingPlacement: CoatingPlacement?
        var concentricEnabled: Bool { ringMaterial != nil && coreMaterial != nil }
        var coatingQuestion: SceneQuestion {
            let label = LocalSceneAssistant.readableMaterial(coatingMaterial ?? "Coating").capitalized
            return .init(title: "\(label) placement?", options: [
                "Around the \(LocalSceneAssistant.readableMaterial(coreMaterial ?? "center")) ball",
                "Outside the \(LocalSceneAssistant.readableMaterial(ringMaterial ?? "outer")) ring"
            ])
        }

        mutating func restore(_ layout: Layout) {
            materials = layout.materials; container = layout.container; shape = layout.shape; style = layout.style
            wantsContainer = layout.shape.isContainer; emptyContainer = layout.contents.isEmpty
            ignite = false; acceptedSimplification = layout.simplified
            ringMaterial = layout.concentric?.outerRing; coreMaterial = layout.concentric?.core
            coatingMaterial = layout.concentric?.coating; coatingPlacement = layout.concentric?.placement
        }

        mutating func read(_ text: String) {
            let words = tokens(text)
            let found = mentions(words)
            if let selected = Shape.read(words) { shape = selected; wantsContainer = selected.isContainer }
            if let selected = Style.read(words) { style = selected }
            if words.contains(where: { ["container", "vessel", "chamber", "tank", "inside", "containing", "enclosed"].contains($0) }), shape != .wall, shape != .samples { wantsContainer = true }
            if requiresComplexLayout(words) { complex = true }
            if contains(words, ["simple", "material", "chamber"]) { acceptedSimplification = true; shape = .rectangular; wantsContainer = true }
            if contains(words, ["separate", "material", "samples"]) { acceptedSimplification = true; shape = .samples; wantsContainer = false }
            if words.contains("empty") && wantsContainer { emptyContainer = true }
            let explicitExplosive = found.contains { ["GUNP", "PLEX", "DESL", "NITR", "BOMB", "C5"].contains($0.code) }
            if words.contains(where: { ["explosive", "explosives", "explosion", "blast"].contains($0) }) { needsExplosiveChoice = !explicitExplosive }
            if explicitExplosive { needsExplosiveChoice = false }
            if words.contains("nuclear") || words.contains("radioactive") { needsNuclearChoice = true }
            if found.contains(where: { ["PLUT", "URAN", "DEUT", "POLO"].contains($0.code) }) { needsNuclearChoice = false }
            let only = words.contains("only") || (words.contains("instead") && !words.contains("of"))
            if only && !found.isEmpty { materials = materials.filter { $0 == container }; ignite = false }
            let replaceIndex = words.firstIndex(of: "replace")
            let withIndex = words.firstIndex(of: "with")
            let oldContainer = container
            var removedContainer = false
            var negating = false
            var previousEnd = 0
            var added: [String] = []
            for mention in found {
                let preceding = Array(words[max(0, mention.start - 2)..<mention.start])
                let between = Array(words[previousEnd..<mention.start]); previousEnd = mention.end
                if between.contains(where: { ["no", "not", "without", "remove", "omit", "exclude"].contains($0) }) { negating = true }
                else if between.contains(where: { ["add", "use", "with", "plus", "but", "instead"].contains($0) }) { negating = false }
                if preceding == ["instead", "of"] { negating = true }
                let removed = negating
                    || (replaceIndex != nil && withIndex != nil && mention.start > replaceIndex! && mention.start < withIndex!)
                if removed {
                    materials.removeAll { $0 == mention.code }
                    if oldContainer == mention.code { container = nil; removedContainer = true }
                    continue
                }
                if !materials.contains(mention.code) { materials.append(mention.code) }
                added.append(mention.code)
                let following = words.dropFirst(mention.end).first
                if (EngineElement.named(mention.code)?.properties ?? 0) & 0x04 != 0,
                   following.map({ ["wall", "container", "tank", "chamber", "vessel"].contains($0) }) == true
                    || preceding == ["container", "material"] {
                    container = mention.code
                }
            }
            if removedContainer && (replaceIndex != nil || words.contains("instead")) {
                container = added.first { (EngineElement.named($0)?.properties ?? 0) & 0x04 != 0 }
            }
            if !found.isEmpty && found.contains(where: { $0.code != container }) { emptyContainer = false }
            if words.contains(where: { ["ignite", "ignited", "ignition", "fire"].contains($0) }) {
                let negative = words.contains { ["no", "not", "never", "without", "don", "dont", "remove", "omit", "exclude"].contains($0) }
                if negative { ignite = false; materials.removeAll { $0 == "FIRE" } }
                else if words.contains("ignite") || words.contains("ignited") || words.contains("ignition") { ignite = true }
            }
            if contains(words, ["simple", "material", "chamber"]) || contains(words, ["separate", "material", "samples"]) {
                ringMaterial = nil; coreMaterial = nil; coatingMaterial = nil; coatingPlacement = nil
                return
            }
            // Explicit role grammar only: "ring of WOOD", "WOOD ring", "ball of
            // FIRE", "FIRE ball", and a named wrapped/coated material.
            for mention in found where materials.contains(mention.code) {
                let before = Array(words[max(0, mention.start - 3)..<mention.start])
                let after = words.dropFirst(mention.end).first
                if before.suffix(2) == ["ring", "of"] || after == "ring" { ringMaterial = mention.code }
                if before.suffix(2) == ["ball", "of"] || after == "ball" { coreMaterial = mention.code }
                if before.contains(where: { ["wrapped", "coated", "coating"].contains($0) }) || after == "coating" {
                    if coatingMaterial != mention.code { coatingPlacement = nil }
                    coatingMaterial = mention.code
                }
            }
            for (index, word) in words.enumerated() {
                let following = words.dropFirst(index + 1).prefix(5)
                if word == "around", following.contains("ball") { coatingPlacement = .aroundCore }
                if word == "outside", following.contains("ring") { coatingPlacement = .outsideOuter }
            }
            if let ringMaterial, !materials.contains(ringMaterial) { self.ringMaterial = container }
            if let coreMaterial, !materials.contains(coreMaterial) { self.coreMaterial = nil }
            if let coatingMaterial, !materials.contains(coatingMaterial) { self.coatingMaterial = nil; coatingPlacement = nil }
            if concentricEnabled {
                if let selected = Shape.read(words), selected != .circular && selected != .concentric { complex = true }
                shape = .concentric; container = ringMaterial; wantsContainer = true
            }
        }
    }

    private struct Mention { let code: String; let start: Int; let end: Int }
    private static let aliases: [String: String] = {
        var result: [String: String] = [:]
        for element in EngineElement.allCases where element != .empty {
            result[tokens(element.identifier).joined(separator: " ")] = element.identifier
            result[tokens(element.name).joined(separator: " ")] = element.identifier
        }
        let common = ["glass": "GLAS", "water": "WATR", "gunpowder": "GUNP", "explosive powder": "GUNP",
                      "plastic explosive": "PLEX", "c4": "PLEX", "c 4": "PLEX", "diesel": "DESL", "nitroglycerin": "NITR",
                      "metal": "METL", "brick": "BRCK", "diamond": "DMND", "stone": "STNE", "wood": "WOOD",
                      "sand": "SAND", "oil": "OIL", "plant": "PLNT", "plants": "PLNT", "salt": "SALT",
                      "salt water": "SLTW", "saltwater": "SLTW", "steam": "WTRV", "water vapor": "WTRV",
                      "ice": "ICEI", "fire": "FIRE", "smoke": "SMKE", "acid": "ACID", "lava": "LAVA",
                      "plutonium": "PLUT", "uranium": "URAN", "neutron": "NEUT", "neutrons": "NEUT",
                      "battery": "BTRY", "wire": "METL"]
        for (alias, code) in common where EngineElement.named(code) != nil { result[alias] = code }
        return result
    }()
    private static func mentions(_ words: [String]) -> [Mention] {
        var result: [Mention] = []; var index = 0
        while index < words.count {
            var found = false
            for length in stride(from: min(3, words.count - index), through: 1, by: -1) {
                if let code = aliases[words[index..<(index + length)].joined(separator: " ")] {
                    result.append(Mention(code: code, start: index, end: index + length)); index += length; found = true; break
                }
            }
            if !found { index += 1 }
        }
        return result
    }
    private static func tokens(_ text: String) -> [String] {
        text.lowercased().replacingOccurrences(of: "[^a-z0-9]+", with: " ", options: .regularExpression).split(separator: " ").map(String.init)
    }
    private static func readableMaterial(_ code: String) -> String {
        ["WOOD": "wood", "FIRE": "fire", "URAN": "uranium", "GLAS": "glass", "METL": "metal", "WATR": "water", "SAND": "sand"] [code]
            ?? code.lowercased()
    }
    private static func contains(_ words: [String], _ phrase: [String]) -> Bool {
        guard words.count >= phrase.count else { return false }
        return (0...(words.count - phrase.count)).contains { Array(words[$0..<($0 + phrase.count)]) == phrase }
    }
    private static func requiresComplexLayout(_ words: [String]) -> Bool {
        words.contains { ["reactor", "computer", "circuit", "wired", "connected", "detector", "piston", "laser", "engine", "touching", "above", "below", "horizontal", "hexagonal", "triangular", "spiral", "heart"].contains($0) }
    }
    private static func element(_ code: String) throws -> EngineElement {
        guard let value = EngineElement.named(code), value != .empty else { throw LocalSceneError.unsupported("Choose a supported game material instead of \(code).") }
        return value
    }
}

enum LocalSceneError: Error, LocalizedError {
    case unsupported(String)
    var errorDescription: String? { switch self { case .unsupported(let message): message } }
}

enum LocalScenePlanningError: Error {
    case needsChoices(SceneConsultation)
}
