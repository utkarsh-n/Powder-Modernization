import SwiftUI
import PowderEngine

enum WorkspaceFocus: Hashable { case canvas, prompt }

@MainActor
struct WorkspaceView: View {
    @Bindable var session: PlaygroundSession
    let onOpen: () -> Void
    let onSave: () -> Void
    @State private var sheet: WorkspaceSheet?
    @State private var replacement: SceneReplacement?
    @State private var intelligence = SceneIntelligence()
    @State private var columns: NavigationSplitViewVisibility = .all
    @State private var inspectorPresented = false
    @AppStorage("showScenePromptBar") private var promptBarVisible = true
    @FocusState private var workspaceFocus: WorkspaceFocus?
    @State private var promptFocusRequest = 0
    @Environment(\.accessibilityReduceMotion) private var reduceMotion

    var body: some View {
        NavigationSplitView(columnVisibility: $columns) {
            MaterialPalette(session: session)
                .navigationSplitViewColumnWidth(min: 210, ideal: 250, max: 340)
        } detail: {
            SimulationCanvas(session: session, onInteraction: { if workspaceFocus != .canvas { workspaceFocus = .canvas } })
                .frame(maxWidth: .infinity, maxHeight: .infinity)
                .background(PowderTheme.canvas)
                .accessibilityLabel("Experiment canvas")
                .focusable(interactions: .edit).focused($workspaceFocus, equals: .canvas)
                .focusEffectDisabled()
                .overlay(alignment: .bottom) {
                    if promptBarVisible {
                        ScenePromptBar(intelligence: intelligence, session: session,
                            focus: $workspaceFocus, focusRequest: promptFocusRequest,
                            onSettings: { workspaceFocus = .canvas; sheet = .intelligence },
                            onInspect: { workspaceFocus = .canvas; sheet = .plan },
                            onDismiss: hidePromptBar)
                            .frame(maxWidth: 640)
                            .padding(.horizontal, 16).padding(.bottom, 16)
                            .transition(.move(edge: .bottom).combined(with: .opacity))
                    }
                }
                .animation(reduceMotion ? nil : .easeInOut(duration: 0.18), value: promptBarVisible)
                .navigationTitle(session.sceneTitle)
                .navigationSubtitle(session.isPaused ? "Paused" : "Running")
                .toolbar { workspaceToolbar }
                .inspector(isPresented: $inspectorPresented) {
                    inspector
                        .inspectorColumnWidth(min: 250, ideal: 285, max: 390)
                }
        }
        .navigationSplitViewStyle(.balanced)
        .focusedSceneValue(\.powderWorkspace, commands)
        .sheet(item: $sheet) { destination in
            switch destination {
            case .intelligence: IntelligenceSettings(intelligence: intelligence)
            case .plan: ScenePlanInspector(intelligence: intelligence)
            }
        }
        .task { intelligence.refreshCredentialState() }
        .onChange(of: session.mode) { _, mode in
            if mode == .inspect { inspectorPresented = true }
        }
        .confirmationDialog(replacement?.title ?? "Replace the experiment?", isPresented: Binding(
            get: { replacement != nil }, set: { if !$0 { replacement = nil } }
        ), titleVisibility: .visible, presenting: replacement) { action in
            Button(action.buttonTitle, role: .destructive) {
                switch action {
                case .clear: session.clear()
                case .scene(let scene): session.loadScene(scene)
                }
                replacement = nil
            }
            Button("Cancel", role: .cancel) { replacement = nil }
        } message: { _ in
            Text("This replaces the current experiment. Undo can restore it.")
        }
    }

    @ToolbarContentBuilder
    private var workspaceToolbar: some ToolbarContent {
        ToolbarItemGroup(placement: .navigation) {
            Button(action: session.togglePlayback) {
                Label(session.isPaused ? "Play" : "Pause", systemImage: session.isPaused ? "play.fill" : "pause.fill")
            }
            .help(session.isPaused ? "Run experiment (Space)" : "Pause experiment (Space)")
            .accessibilityIdentifier("playback")
            Button(action: session.step) { Label("Step", systemImage: "forward.frame") }
                .disabled(!session.isPaused).help("Advance one simulation step (⌘→)")
        }
        ToolbarItem(placement: .principal) {
            Picker("Workspace mode", selection: Binding(get: { session.mode }, set: session.setMode)) {
                Text("Build").tag(WorkspaceMode.build)
                Text("Run").tag(WorkspaceMode.run)
                Text("Inspect").tag(WorkspaceMode.inspect)
            }
            .pickerStyle(.segmented).labelsHidden().frame(width: 205)
            .help("Build draws materials. Run plays the scene. Inspect samples particle properties.")
        }
        ToolbarItemGroup(placement: .primaryAction) {
            Button(action: showPromptBar) {
                Label("Scene Prompt", systemImage: "sparkles")
            }
            .help("Show and focus the prompt bar (⇧⌘G)")
            .accessibilityIdentifier("showPromptBar")
            canvasMenu
            Button { inspectorPresented.toggle() } label: {
                Label("Inspector", systemImage: "sidebar.right")
            }
            .help(inspectorPresented ? "Hide inspector (⌥⌘I)" : "Show inspector (⌥⌘I)")
            .accessibilityIdentifier("toggleInspector")
        }
    }

    @ViewBuilder
    private var inspector: some View {
        if session.mode == .inspect {
            InspectContextPanel(session: session, intelligence: intelligence, onPlan: { sheet = .plan })
        } else {
            RunContextPanel(session: session)
        }
    }

    private var canvasMenu: some View {
        Menu {
            Toggle("Temperature View", isOn: $session.showHeat)
            Picker("Zoom", selection: $session.canvasZoom) {
                Text("Fit to Window").tag(1.0)
                Text("200%").tag(2.0)
                Text("400%").tag(4.0)
            }
            Divider()
            Toggle("Cinematic Lighting", isOn: $session.renderSettings.cinematic)
            Picker("Render Quality", selection: $session.renderSettings.quality) {
                ForEach(MetalRenderQuality.allCases) { quality in Text(quality.title).tag(quality) }
            }
            Button("Soft Glow") { session.renderSettings.bloomStrength = 0.4 }
            Button("Vivid Glow") { session.renderSettings.bloomStrength = 1.1 }
            if let error = session.rendererError { Text("Renderer fallback: \(error)") }
        } label: { Label("Canvas Appearance", systemImage: "slider.horizontal.3") }
        .help("Canvas appearance and zoom")
    }

    private func showPromptBar() {
        promptBarVisible = true
        promptFocusRequest &+= 1
        workspaceFocus = .prompt
    }

    private func hidePromptBar() {
        workspaceFocus = .canvas
        promptBarVisible = false
    }

    private func togglePromptBar() {
        if promptBarVisible { hidePromptBar() } else { showPromptBar() }
    }

    private var commands: WorkspaceCommandActions {
        WorkspaceCommandActions(session: session, open: onOpen, save: onSave,
            new: { replacement = .clear },
            loadScene: { replacement = .scene($0) },
            showGenerator: showPromptBar,
            toggleGenerator: togglePromptBar, isPromptBarVisible: promptBarVisible,
            showSettings: { workspaceFocus = .canvas; sheet = .intelligence },
            showPlan: { sheet = .plan },
            toggleInspector: { inspectorPresented.toggle() },
            toggleSidebar: { columns = columns == .detailOnly ? .all : .detailOnly },
            hasPlan: intelligence.displayedPlan != nil, promptIsFocused: workspaceFocus == .prompt)
    }
}

private enum WorkspaceSheet: String, Identifiable {
    case intelligence, plan
    var id: String { rawValue }
}
private enum SceneReplacement {
    case clear, scene(StudioScene)
    var title: String {
        switch self { case .clear: "Start a new experiment?"; case .scene(let scene): "Load \(scene.title)?" }
    }
    var buttonTitle: String { if case .clear = self { "New Experiment" } else { "Load Experiment" } }
}
