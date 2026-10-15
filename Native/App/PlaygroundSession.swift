import Foundation
import Observation
import CoreGraphics
import PowderEngine

enum BrushTool: String, CaseIterable, Identifiable, Sendable {
    case draw, erase, sample, pan
    var id: Self { self }
    var title: String { rawValue.capitalized }
    var symbol: String {
        switch self { case .draw: "paintbrush.pointed"; case .erase: "eraser"; case .sample: "eyedropper"; case .pan: "hand.draw" }
    }
}
enum WorkspaceMode: String, CaseIterable, Identifiable, Sendable {
    case build, run, inspect
    var id: Self { self }
}
struct CanvasInspection: Sendable {
    let x: Int, y: Int
    let matter: EngineParticle?
    let energy: EngineParticle?
    let pressure: Float
    let wall: EngineWallCell?
}

@MainActor @Observable
final class PlaygroundSession {
    var selectedMaterial: EngineElement = .sand
    var selectedWall: EngineWallType?
    var currentBrushName: String { selectedWall?.name ?? selectedMaterial.displayName }
    var currentBrushColor: UInt32 { selectedWall?.colorRGB ?? selectedMaterial.colorRGB }
    var brushRadius: Double = 4
    var tool: BrushTool = .draw
    var canvasZoom: Double = 1
    private(set) var mode: WorkspaceMode = .build
    private(set) var sceneTitle = StudioScene.sandAndWater.title
    private(set) var inspection: CanvasInspection?
    private(set) var isPaused = true
    var isActive = true { didSet { wake.continuation.yield() } }
    var showHeat = false { didSet { renderSettings.showHeat = showHeat } }
    var renderSettings = MetalRenderSettings()
    private(set) var rendererError: String?
    private(set) var legacyFusionEnabled = false
    private(set) var newtonianGravityEnabled = false
    private(set) var particleCount = 0
    private(set) var tick: UInt64 = 0
    private(set) var image: CGImage?
    private(set) var signs: [EngineSign] = []
    private(set) var canvasWidth = 612
    private(set) var canvasHeight = 384
    private(set) var canUndo = false
    private(set) var canRedo = false
    private(set) var isBusy = true
    /// Conservative token for accepted edits; AI previews can detect intervening user work.
    private(set) var editRevision: UInt64 = 0
    var status = "Opening experiment…"
    // Frame delivery bypasses Observation entirely, so drawing never rebuilds the sidebar.
    @ObservationIgnored let frameSource = MetalFrameSource()
    @ObservationIgnored private var worker: SimulationWorker?
    @ObservationIgnored private var pending: [SimulationCommand] = []
    @ObservationIgnored private var replies: [UUID: CheckedContinuation<Data, Error>] = [:]
    @ObservationIgnored private var wake = AsyncStream<Void>.makeStream(bufferingPolicy: .bufferingNewest(1))
    @ObservationIgnored private var runningLoop = false
    @ObservationIgnored private var isStopping = false
    @ObservationIgnored private var autosaveTask: Task<Void, Never>?
    @ObservationIgnored private var strokeActive = false
    @ObservationIgnored private var pressureSource: (any DispatchSourceMemoryPressure)?
    @ObservationIgnored private var lastStats = ContinuousClock.now
    @ObservationIgnored private let showcase: Bool
    @ObservationIgnored private let autosaveLocation: URL?

    init(showcase: Bool = ProcessInfo.processInfo.arguments.contains("--showcase"), autosaveURL: URL? = nil) {
        self.showcase = showcase
        self.autosaveLocation = autosaveURL
        let source = DispatchSource.makeMemoryPressureSource(eventMask: [.warning, .critical], queue: .main)
        source.setEventHandler { [weak self] in
            Task { @MainActor [weak self] in self?.enqueue(.trimHistory) }
        }
        source.resume()
        pressureSource = source
    }
    deinit { pressureSource?.cancel(); autosaveTask?.cancel() }

    func run() async {
        guard !runningLoop else { return }
        runningLoop = true
        wake = AsyncStream<Void>.makeStream(bufferingPolicy: .bufferingNewest(1))
        defer {
            runningLoop = false; isStopping = false
            for continuation in replies.values { continuation.resume(throwing: CancellationError()) }
            replies.removeAll()
        }
        if worker == nil {
            do {
                let showcase = showcase, autosaveLocation = autosaveLocation
                worker = try await Task.detached(priority: .userInitiated) { try SimulationWorker(showcase: showcase, autosaveURL: autosaveLocation) }.value
            } catch { isBusy = false; status = error.localizedDescription; return }
        }
        guard let worker else { return }
        var iterator = wake.stream.makeAsyncIterator()
        let clock = ContinuousClock()
        var first = true
        while !Task.isCancelled {
            let start = clock.now
            let commands = pending
            pending.removeAll(keepingCapacity: true)
            let advance = isActive && !isPaused
            let update = await worker.process(commands, advance: advance)
            apply(update, forceStats: first || !commands.isEmpty || !advance)
            first = false
            let busy = pending.contains { $0.isReplacement }
            if isBusy != busy { isBusy = busy }
            if isActive && !isPaused {
                let remaining = Duration.milliseconds(33) - start.duration(to: clock.now)
                do { try await Task.sleep(for: max(remaining, .milliseconds(1))) }
                catch { break }
            } else if pending.isEmpty {
                guard await iterator.next() != nil else { break }
            }
        }
        // Window closure cancels the view task. Drain already accepted edits before saving.
        isStopping = true; isPaused = true
        finishStroke(); autosaveTask?.cancel()
        let finalCommands = pending; pending.removeAll()
        let finalUpdate = await worker.process(finalCommands + [.autosave], advance: false)
        apply(finalUpdate, forceStats: true)
    }

    private func apply(_ update: SimulationUpdate, forceStats: Bool) {
        if let frame = update.frame { frameSource.submit(frame) }
        if let image = update.image { self.image = image }
        if forceStats || lastStats.duration(to: .now) >= .milliseconds(200) {
            particleCount = update.count; tick = update.tick; inspection = update.inspection
            if signs != update.signs { signs = update.signs }
            lastStats = .now
        }
        if canvasWidth != update.width { canvasWidth = update.width }
        if canvasHeight != update.height { canvasHeight = update.height }
        if sceneTitle != update.title { sceneTitle = update.title }
        if canUndo != update.canUndo { canUndo = update.canUndo }
        if canRedo != update.canRedo { canRedo = update.canRedo }
        if legacyFusionEnabled != update.legacyFusion { legacyFusionEnabled = update.legacyFusion }
        if newtonianGravityEnabled != update.newtonianGravity { newtonianGravityEnabled = update.newtonianGravity }
        if let sampled = update.sampledMaterial { selectedWall = nil; selectedMaterial = sampled }
        if let message = update.status { status = message }
        if update.failed { isPaused = true }
        for (id, result) in update.replies { replies.removeValue(forKey: id)?.resume(with: result) }
    }
    private func enqueue(_ command: SimulationCommand) {
        pending.append(command)
        if command.mutatesWorld {
            editRevision &+= 1
            // A single delayed wake saves paused edits without restoring an idle polling loop.
            autosaveTask?.cancel()
            autosaveTask = Task { [weak self] in
                do { try await Task.sleep(for: .seconds(5)) }
                catch { return }
                self?.autosave()
            }
        }
        wake.continuation.yield()
    }
    func select(_ material: EngineElement) {
        finishStroke(); selectedWall = nil; selectedMaterial = material; tool = .draw; status = material.summary
    }
    func selectWall(_ wall: EngineWallType) {
        finishStroke(); selectedWall = wall; tool = .draw; status = wall.summary
    }
    func setMode(_ value: WorkspaceMode) {
        finishStroke(); mode = value
        if value != .run { isPaused = true; autosave() }
        status = value == .inspect ? "Select a particle to inspect its live properties" : (value == .build ? "Choose a material and draw" : "Press Play to run your experiment")
        wake.continuation.yield()
    }
    func inspect(x: Int, y: Int) { enqueue(.inspect(x, y)) }
    func togglePlayback() {
        finishStroke()
        if isPaused { mode = .run; enqueue(.beginPlayback) }
        isPaused.toggle()
        status = isPaused ? "Simulation paused" : "Simulation running"
        if isPaused { autosave() }
        wake.continuation.yield()
    }
    func step() { finishStroke(); isPaused = true; enqueue(.step) }
    func paint(x: Int, y: Int) {
        guard !isBusy else { return }
        if mode == .inspect { inspect(x: x, y: y); return }
        guard mode == .build, tool != .pan, x >= 0, y >= 0, x < canvasWidth, y < canvasHeight else { return }
        strokeActive = true
        enqueue(.paint(x: x, y: y, radius: Int(brushRadius), tool: tool, element: selectedMaterial, wall: selectedWall))
    }
    func finishStroke() {
        guard strokeActive else { return }
        strokeActive = false; enqueue(.finishStroke)
    }
    func undo() { finishStroke(); isPaused = true; enqueue(.undo) }
    func redo() { finishStroke(); isPaused = true; enqueue(.redo) }
    private func prepareReplacement() {
        finishStroke(); isPaused = true; mode = .build; inspection = nil; canvasZoom = 1; isBusy = true
    }
    func clear() { prepareReplacement(); enqueue(.clear); autosave() }
    func loadDemo() { loadScene(.sandAndWater) }
    func loadScene(_ scene: StudioScene) { prepareReplacement(); enqueue(.scene(scene)); autosave() }
    func applyGeneratedWorld(_ candidate: EngineWorld, title: String) {
        prepareReplacement(); enqueue(.generated(candidate, title)); autosave()
    }
    func useFallbackRenderer(_ reason: String) {
        guard rendererError == nil else { return }
        rendererError = reason; enqueue(.fallback(true))
    }
    func setLegacyFusion(_ enabled: Bool) { finishStroke(); isPaused = true; enqueue(.legacyFusion(enabled)); autosave() }
    func setNewtonianGravity(_ enabled: Bool) { finishStroke(); isPaused = true; enqueue(.newtonianGravity(enabled)); autosave() }
    func open(_ url: URL) async throws {
        prepareReplacement()
        _ = try await request { .open(url, $0) }
        autosave()
    }
    func exportData() async throws -> Data { try await request { .export($0) } }
    func saveBeforeClosing() async throws {
        finishStroke(); isPaused = true; isActive = false
        if (!runningLoop || isStopping), let worker {
            let commands = pending; pending.removeAll()
            let id = UUID()
            let update = await worker.process(commands + [.flush(id)], advance: false)
            _ = try update.replies[id]?.get()
        } else { _ = try await request { .flush($0) } }
    }
    func autosave() { autosaveTask?.cancel(); autosaveTask = nil; enqueue(.autosave) }
    private func request(_ command: (UUID) -> SimulationCommand) async throws -> Data {
        guard runningLoop, !isStopping else { throw CocoaError(.userCancelled) }
        return try await withCheckedThrowingContinuation { continuation in
            let id = UUID(); replies[id] = continuation; enqueue(command(id))
        }
    }
}

private extension SimulationCommand {
    var mutatesWorld: Bool {
        switch self {
        case .paint(_, _, _, let tool, _, _): tool == .draw || tool == .erase
        case .beginPlayback, .step, .undo, .redo, .clear, .scene, .generated, .legacyFusion, .newtonianGravity, .open: true
        default: false
        }
    }
    var isReplacement: Bool {
        switch self { case .clear, .scene, .generated, .open: true; default: false }
    }
}
