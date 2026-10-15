import AppKit
import SwiftUI

@MainActor
struct WorkspaceCommandActions {
    let session: PlaygroundSession
    let open: () -> Void
    let save: () -> Void
    let new: () -> Void
    let loadScene: (StudioScene) -> Void
    let showGenerator: () -> Void
    let toggleGenerator: () -> Void
    let isPromptBarVisible: Bool
    let showSettings: () -> Void
    let showPlan: () -> Void
    let toggleInspector: () -> Void
    let toggleSidebar: () -> Void
    let hasPlan: Bool
    let promptIsFocused: Bool
    var isEditingText: Bool { promptIsFocused || textEditor != nil }

    // Keep normal text-field editing in the responder chain; canvas history is independent.
    var textEditor: NSTextView? { NSApp.keyWindow?.firstResponder as? NSTextView }
    var canUndo: Bool { textEditor?.undoManager?.canUndo ?? session.canUndo }
    var canRedo: Bool { textEditor?.undoManager?.canRedo ?? session.canRedo }
    func undo() {
        if let textEditor { textEditor.undoManager?.undo() }
        else { session.undo() }
    }
    func redo() {
        if let textEditor { textEditor.undoManager?.redo() }
        else { session.redo() }
    }
}

private struct WorkspaceCommandKey: FocusedValueKey {
    typealias Value = WorkspaceCommandActions
}

extension FocusedValues {
    var powderWorkspace: WorkspaceCommandActions? {
        get { self[WorkspaceCommandKey.self] }
        set { self[WorkspaceCommandKey.self] = newValue }
    }
}

@MainActor
struct PowderCommands: Commands {
    @FocusedValue(\.powderWorkspace) private var workspace

    var body: some Commands {
        CommandGroup(replacing: .newItem) {
            Button("New Experiment") { workspace?.new() }
                .keyboardShortcut("n").disabled(workspace == nil)
            Button("Open Experiment…") { workspace?.open() }
                .keyboardShortcut("o").disabled(workspace == nil)
            Menu("Open Example") {
                ForEach(StudioScene.allCases) { scene in
                    Button(scene.title) { workspace?.loadScene(scene) }
                }
            }.disabled(workspace == nil)
        }
        CommandGroup(replacing: .saveItem) {
            Button("Save Experiment…") { workspace?.save() }
                .keyboardShortcut("s").disabled(workspace == nil)
        }
        CommandGroup(replacing: .undoRedo) {
            Button("Undo") { workspace?.undo() }
                .keyboardShortcut("z").disabled(!(workspace?.canUndo ?? false))
            Button("Redo") { workspace?.redo() }
                .keyboardShortcut("z", modifiers: [.command, .shift]).disabled(!(workspace?.canRedo ?? false))
        }
        CommandGroup(replacing: .appSettings) {
            Button("Intelligence Settings…") { workspace?.showSettings() }
                .keyboardShortcut(",").disabled(workspace == nil)
        }
        CommandGroup(after: .sidebar) {
            Button("Toggle Materials Sidebar") { workspace?.toggleSidebar() }
                .keyboardShortcut("s", modifiers: [.command, .control]).disabled(workspace == nil)
            Button("Toggle Inspector") { workspace?.toggleInspector() }
                .keyboardShortcut("i", modifiers: [.command, .option]).disabled(workspace == nil)
            Button(workspace?.isPromptBarVisible == true ? "Hide Prompt Bar" : "Show Prompt Bar") { workspace?.toggleGenerator() }
                .keyboardShortcut("p", modifiers: [.command, .option]).disabled(workspace == nil)
            Divider()
            if let workspace {
                Toggle("Temperature View", isOn: Binding(get: { workspace.session.showHeat }, set: { workspace.session.showHeat = $0 }))
                    .keyboardShortcut("t", modifiers: [.command, .shift])
                Button("Fit Canvas to Window") { workspace.session.canvasZoom = 1 }
                    .keyboardShortcut("0")
            }
        }
        CommandMenu("Simulation") {
            Button(workspace?.session.isPaused == false ? "Pause" : "Play") { workspace?.session.togglePlayback() }
                .keyboardShortcut(" ", modifiers: [])
                .disabled(workspace == nil || workspace?.isEditingText == true)
            Button("Step Forward") { workspace?.session.step() }
                .keyboardShortcut(.rightArrow).disabled(workspace?.session.isPaused != true || workspace?.isEditingText == true)
            Divider()
            ForEach(WorkspaceMode.allCases) { mode in
                Button(mode.rawValue.capitalized) { workspace?.session.setMode(mode) }
                    .disabled(workspace == nil)
            }
            Divider()
            if let workspace {
                Toggle("Newtonian Gravity", isOn: Binding(get: { workspace.session.newtonianGravityEnabled }, set: workspace.session.setNewtonianGravity))
                Toggle("Legacy Fusion Effects", isOn: Binding(get: { workspace.session.legacyFusionEnabled }, set: workspace.session.setLegacyFusion))
            }
        }
        CommandMenu("Intelligence") {
            Button("Generate Scene…") { workspace?.showGenerator() }
                .keyboardShortcut("g", modifiers: [.command, .shift]).disabled(workspace == nil)
            Button("Generated Scene Details…") { workspace?.showPlan() }
                .disabled(workspace?.hasPlan != true)
        }
    }
}
