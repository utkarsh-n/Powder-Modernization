import Foundation
import CoreGraphics
import PowderEngine
import os

/// Commands enter one ordered mailbox. The mutable C++ world never crosses back to the UI.
enum SimulationCommand: Sendable {
    case paint(x: Int, y: Int, radius: Int, tool: BrushTool, element: EngineElement, wall: EngineWallType?)
    case finishStroke, inspect(Int, Int), beginPlayback, step, undo, redo, clear
    case scene(StudioScene), generated(EngineWorld, String)
    case legacyFusion(Bool), newtonianGravity(Bool), fallback(Bool), trimHistory
    case open(URL, UUID), export(UUID), autosave, flush(UUID)
}

struct SimulationUpdate: Sendable {
    var frame: MetalFrame?
    var image: CGImage?
    var width: Int
    var height: Int
    var count: Int
    var tick: UInt64
    var title: String
    var inspection: CanvasInspection?
    var signs: [EngineSign]
    var canUndo: Bool
    var canRedo: Bool
    var legacyFusion: Bool
    var newtonianGravity: Bool
    var sampledMaterial: EngineElement?
    var status: String?
    var failed = false
    var replies: [UUID: Result<Data, Error>] = [:]
}

actor SimulationWorker {
    private var world: EngineWorld
    private struct Checkpoint { let world: EngineWorld; let title: String }
    private var undoStack: [Checkpoint] = []
    private var redoStack: [Checkpoint] = []
    private var strokePoint: (Int, Int)?
    private var strokeHasCheckpoint = false
    private var inspectedPoint: (Int, Int)?
    private var title = StudioScene.sandAndWater.title
    private var revision: UInt64 = 0
    private var dirty = false
    private var needsFrame = true
    private var fallback = false
    private var lastSave = Date()
    private var initialStatus: String? = "Choose a material and draw"
    private let showcase: Bool
    private let autosaveLocation: URL?
    private let materials = MetalMaterialTable.engineMaterials
    private let signposter = OSSignposter(subsystem: "dev.utkarsh.powder.mac", category: "Simulation")

    /// Construct on the worker executor, since initial scene creation also allocates engine memory.
    init(showcase: Bool, initialWorld: EngineWorld? = nil, autosaveURL: URL? = nil) throws {
        self.showcase = showcase
        self.autosaveLocation = autosaveURL
        world = try initialWorld ?? StudioScene.sandAndWater.makeWorld()
        if !showcase {
            do {
                let url = try autosaveLocation ?? Self.autosaveURL()
                if FileManager.default.fileExists(atPath: url.path) {
                    world = try EngineWorld.decode(Data(contentsOf: url))
                    title = "Your experiment"
                    initialStatus = "Restored your last experiment"
                }
            } catch { initialStatus = "Couldn’t restore autosave: \(error.localizedDescription)" }
        }
    }

    func process(_ commands: [SimulationCommand], advance: Bool) -> SimulationUpdate {
        assert(!Thread.isMainThread, "Simulation work must stay off the UI thread")
        var status = initialStatus
        initialStatus = nil
        var sampled: EngineElement?
        var replies: [UUID: Result<Data, Error>] = [:]
        var failed = false
        for command in commands {
            do {
                switch command {
                case let .paint(x, y, radius, tool, element, wall):
                    guard tool != .pan else { continue }
                    guard x >= 0, y >= 0, x < world.width, y < world.height else { continue }
                    if tool == .sample {
                        let material = world.particle(x: x, y: y, energy: true)?.material ?? world.particle(x: x, y: y)?.material ?? .empty
                        if material != .empty { sampled = material; status = "Sampled \(material.name)" }
                        continue
                    }
                    let previous = strokePoint ?? (x, y)
                    let prior = strokeHasCheckpoint ? nil : Checkpoint(world: world, title: title)
                    let didChange: Bool
                    do {
                        if let wall, tool == .draw {
                            didChange = try world.paintWallLine(fromX: previous.0, fromY: previous.1, toX: x, toY: y, radius: radius, wall: wall)
                        } else {
                            didChange = try world.paintLine(fromX: previous.0, fromY: previous.1, toX: x, toY: y,
                                                           radius: radius, material: element, erase: tool == .erase)
                        }
                    } catch {
                        if let prior { world = prior.world }
                        else { changed() } // An in-progress stroke still has its original undo checkpoint.
                        throw error
                    }
                    strokePoint = (x, y)
                    if didChange {
                        if let prior { appendCheckpoint(prior); strokeHasCheckpoint = true }
                        changed()
                    } else if let prior {
                        world = prior.world
                    }
                case .finishStroke: finishStroke()
                case let .inspect(x, y):
                    guard x >= 0, y >= 0, x < world.width, y < world.height else { continue }
                    inspectedPoint = (x, y)
                case .beginPlayback: checkpoint()
                case .step:
                    checkpoint()
                    try stepWorld()
                    status = "Advanced one frame"
                case .undo:
                    finishStroke()
                    guard let prior = undoStack.popLast() else { continue }
                    redoStack.append(Checkpoint(world: world, title: title))
                    world = prior.world; title = prior.title; inspectedPoint = nil
                    changed(); status = "Undone · simulation paused"
                case .redo:
                    finishStroke()
                    guard let next = redoStack.popLast() else { continue }
                    undoStack.append(Checkpoint(world: world, title: title))
                    world = next.world; title = next.title; inspectedPoint = nil
                    changed(); status = "Redone · simulation paused"
                case .clear:
                    checkpoint(); try world.clear(); title = "Untitled experiment"; inspectedPoint = nil
                    changed(); status = "Blank canvas · draw something new"
                case .scene(let scene):
                    let next = try scene.makeWorld()
                    checkpoint(); world = next; title = scene.title; inspectedPoint = nil
                    changed(); status = "Experiment loaded · press play"
                case let .generated(next, name):
                    checkpoint(); world = next; title = name; inspectedPoint = nil
                    changed(); status = "\(name) · press play to explore"
                case .legacyFusion(let enabled):
                    guard enabled != world.legacyFusionEnabled else { continue }
                    checkpoint(); try world.setLegacyFusion(enabled); changed()
                    status = enabled ? "Legacy fusion byproducts enabled" : "Original v100.1 fusion behavior"
                case .newtonianGravity(let enabled):
                    guard enabled != world.newtonianGravityEnabled else { continue }
                    checkpoint(); try world.setNewtonianGravity(enabled); changed()
                    status = enabled ? "Newtonian gravity enabled" : "Newtonian gravity disabled"
                case .fallback(let enabled): fallback = enabled; needsFrame = true
                case .trimHistory:
                    // Release historical worlds under macOS memory pressure; keep the current world intact.
                    undoStack = Array(undoStack.suffix(1)); redoStack.removeAll()
                case let .open(url, id):
                    do {
                        let access = url.startAccessingSecurityScopedResource()
                        defer { if access { url.stopAccessingSecurityScopedResource() } }
                        let values = try url.resourceValues(forKeys: [.fileSizeKey])
                        guard (values.fileSize ?? 0) <= 32 * 1024 * 1024 else { throw CocoaError(.fileReadTooLarge) }
                        let next = try EngineWorld.decode(Data(contentsOf: url))
                        checkpoint(); world = next; title = url.deletingPathExtension().lastPathComponent
                        inspectedPoint = nil; changed(); status = "Opened \(title)"
                        replies[id] = .success(Data())
                    } catch { replies[id] = .failure(error) }
                case .export(let id):
                    do { replies[id] = .success(try world.encoded()) }
                    catch { replies[id] = .failure(error) }
                case .autosave: try autosave()
                case .flush(let id):
                    do { try autosave(); replies[id] = .success(Data()) }
                    catch { replies[id] = .failure(error) }
                }
            } catch { status = error.localizedDescription; failed = true }
        }
        if advance && !failed {
            do {
                redoStack.removeAll()
                try stepWorld()
            } catch { status = error.localizedDescription; failed = true }
        }
        if dirty && Date().timeIntervalSince(lastSave) >= 5 {
            do { try autosave() }
            catch { status = "Autosave failed: \(error.localizedDescription)" }
        }
        var frame: MetalFrame?
        var image: CGImage?
        if needsFrame {
            let interval = signposter.beginInterval("Prepare render snapshot")
            do {
                let snapshot = try world.renderSnapshot()
                revision &+= 1
                frame = MetalFrame(width: snapshot.width, height: snapshot.height, revision: revision,
                                   tick: snapshot.tick, cells: snapshot.packedCells, materials: materials)
                if fallback { image = Self.fallbackImage(snapshot) }
                needsFrame = false
            } catch { status = error.localizedDescription; failed = true }
            signposter.endInterval("Prepare render snapshot", interval)
        }
        let sample = inspectedPoint.map { x, y in
            CanvasInspection(x: x, y: y, matter: world.particle(x: x, y: y), energy: world.particle(x: x, y: y, energy: true),
                             pressure: world.pressure(x: x, y: y),
                             wall: world.wall(x: x, y: y))
        }
        return SimulationUpdate(frame: frame, image: image, width: world.width, height: world.height,
            count: world.particleCount, tick: world.tick, title: title, inspection: sample, signs: world.signs(),
            canUndo: !undoStack.isEmpty, canRedo: !redoStack.isEmpty, legacyFusion: world.legacyFusionEnabled,
            newtonianGravity: world.newtonianGravityEnabled, sampledMaterial: sampled, status: status,
            failed: failed, replies: replies)
    }

    private func stepWorld() throws {
        let interval = signposter.beginInterval("Simulation step")
        defer { signposter.endInterval("Simulation step", interval) }
        try world.step(); changed()
    }
    private func changed() { dirty = true; needsFrame = true }
    private func finishStroke() { strokePoint = nil; strokeHasCheckpoint = false }
    private func checkpoint() {
        finishStroke()
        appendCheckpoint(Checkpoint(world: world, title: title))
    }
    private func appendCheckpoint(_ checkpoint: Checkpoint) {
        undoStack.append(checkpoint)
        if undoStack.count > 8 { undoStack.removeFirst() }
        redoStack.removeAll()
    }
    private func autosave() throws {
        guard dirty, !showcase else { return }
        lastSave = Date()
        let interval = signposter.beginInterval("Autosave")
        defer { signposter.endInterval("Autosave", interval) }
        let url = try autosaveLocation ?? Self.autosaveURL()
        try FileManager.default.createDirectory(at: url.deletingLastPathComponent(), withIntermediateDirectories: true)
        try world.encoded().write(to: url, options: .atomic)
        dirty = false
    }
    private static func autosaveURL() throws -> URL {
        try FileManager.default.url(for: .applicationSupportDirectory, in: .userDomainMask, appropriateFor: nil, create: true)
            .appendingPathComponent("PowderNative", isDirectory: true).appendingPathComponent("Autosave.powderlab")
    }
    private static func fallbackImage(_ snapshot: EngineRenderSnapshot) -> CGImage? {
        var pixels = [UInt8](repeating: 0, count: snapshot.width * snapshot.height * 4)
        for y in 0..<snapshot.height {
            for x in 0..<snapshot.width {
                guard let cell = snapshot.cell(x: x, y: y) else { continue }
                let i = (y * snapshot.width + x) * 4
                let alpha = Float((cell.decorationARGB >> 24) & 255) / 255
                let pattern: Float = cell.isWall ? ((x + y) % 2 == 0 ? 0.78 : 0.45) : 1
                for c in 0..<3 {
                    let shift = UInt32((2 - c) * 8)
                    let color = Float((cell.colorRGB >> shift) & 255)
                    let tint = Float((cell.decorationARGB >> shift) & 255)
                    pixels[i + c] = UInt8(max(0, min(255, (color * (1 - alpha) + tint * alpha) * pattern)))
                }
                pixels[i + 3] = 255
            }
        }
        guard let provider = CGDataProvider(data: Data(pixels) as CFData) else { return nil }
        return CGImage(width: snapshot.width, height: snapshot.height, bitsPerComponent: 8, bitsPerPixel: 32,
            bytesPerRow: snapshot.width * 4, space: CGColorSpaceCreateDeviceRGB(),
            bitmapInfo: CGBitmapInfo(rawValue: CGImageAlphaInfo.last.rawValue), provider: provider,
            decode: nil, shouldInterpolate: false, intent: .defaultIntent)
    }
}
