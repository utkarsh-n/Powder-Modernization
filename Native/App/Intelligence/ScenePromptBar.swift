import SwiftUI
import PowderCore
import PowderEngine
import PowderIntelligence

@MainActor
struct ScenePromptBar: View {
    @Bindable var intelligence: SceneIntelligence
    let session: PlaygroundSession
    let focus: FocusState<WorkspaceFocus?>.Binding
    let focusRequest: Int
    let onSettings: () -> Void
    let onInspect: () -> Void
    let onDismiss: () -> Void

    var body: some View {
        VStack(alignment: .leading, spacing: 10) {
            SceneConversationPanel(intelligence: intelligence, session: session,
                onEdit: { focus.wrappedValue = .prompt })
            HStack(alignment: .top, spacing: 10) {
                Image(systemName: "sparkles")
                    .font(.body).foregroundStyle(.secondary)
                    .padding(.top, 7).accessibilityHidden(true)
                TextField(intelligence.messages.isEmpty ? "What would you like to make?" : "Reply or refine the design…", text: $intelligence.prompt, axis: .vertical)
                    .textFieldStyle(.plain).font(.body).lineLimit(1...3)
                    .padding(.vertical, 6)
                    .focused(focus, equals: .prompt).accessibilityLabel("Message the scene assistant")
                    .accessibilityIdentifier("scenePromptField")
                    .onExitCommand { focus.wrappedValue = .canvas }
                if intelligence.isGenerating {
                    Button(action: intelligence.cancel) {
                        Image(systemName: "stop.fill").frame(width: 18, height: 18)
                    }
                    .buttonStyle(.bordered).buttonBorderShape(.circle)
                    .help("Stop the assistant").accessibilityLabel("Stop assistant")
                } else {
                    Button(action: generate) {
                        Image(systemName: "arrow.up").fontWeight(.semibold).frame(width: 18, height: 18)
                    }
                    .buttonStyle(.bordered).buttonBorderShape(.circle)
                    .keyboardShortcut(.return, modifiers: .command)
                    .help("Send message (⌘Return)").accessibilityLabel("Send message")
                    .accessibilityIdentifier("sendSceneMessage")
                    .disabled(intelligence.prompt.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty)
                }
                Button(action: onDismiss) {
                    Image(systemName: "xmark").font(.caption.weight(.medium))
                        .frame(width: 24, height: 28)
                }
                .buttonStyle(.borderless).foregroundStyle(.secondary)
                .help("Hide prompt bar (⌥⌘P)").accessibilityLabel("Hide prompt bar")
                .accessibilityIdentifier("hidePromptBar")
            }
            HStack(spacing: 10) {
                Picker("Provider", selection: $intelligence.provider) {
                    ForEach(SceneProvider.allCases) { Text($0.title).tag($0) }
                }
                .labelsHidden().pickerStyle(.menu).fixedSize()
                .disabled(intelligence.isGenerating)
                Button(action: onSettings) { Image(systemName: "gearshape") }
                    .buttonStyle(.borderless).foregroundStyle(.secondary)
                    .help("Intelligence settings").accessibilityLabel("Intelligence settings")
                if intelligence.displayedPlan != nil {
                    Button(action: onInspect) { Image(systemName: "list.bullet.rectangle") }
                        .buttonStyle(.borderless).foregroundStyle(.secondary)
                        .help("Generated scene details").accessibilityLabel("Generated scene details")
                }
                Spacer(minLength: 0)
                if let source = intelligence.executionLabel {
                    Text(source).font(.caption2).foregroundStyle(.secondary)
                        .accessibilityIdentifier("sceneExecutionSource")
                }
                if focus.wrappedValue == .prompt && !intelligence.isGenerating {
                    Text("⌘Return to send").font(.caption2).foregroundStyle(.tertiary)
                        .lineLimit(1).allowsTightening(true)
                }
            }
            .controlSize(.small)
            if let error = intelligence.errorMessage {
                HStack(alignment: .top, spacing: 8) {
                    Label(error, systemImage: "exclamationmark.triangle")
                        .font(.caption).lineLimit(4).textSelection(.enabled).help(error)
                    Spacer(minLength: 0)
                    Button(intelligence.prompt.isEmpty ? "Retry" : "Send changes") { intelligence.retry(in: session) }
                        .controlSize(.small).disabled(intelligence.isGenerating)
                    Button(action: intelligence.dismissError) { Image(systemName: "xmark") }
                        .buttonStyle(.borderless).help("Dismiss generation error")
                        .accessibilityLabel("Dismiss generation error")
                }
            } else if !intelligence.stage.isEmpty {
                HStack(alignment: .top, spacing: 8) {
                    if intelligence.isGenerating { ProgressView().controlSize(.mini) }
                    Text(intelligence.stage).font(.caption).foregroundStyle(.secondary).lineLimit(2)
                    if intelligence.phase == .idle && intelligence.questions.isEmpty && !intelligence.messages.isEmpty {
                        Button(intelligence.prompt.isEmpty ? "Try again" : "Send changes") { intelligence.retry(in: session) }.controlSize(.small)
                    }
                }
            } else {
                Text("Discuss the design. Preview it. Confirm when it feels right.")
                    .font(.caption).foregroundStyle(.tertiary)
            }
        }
        .padding(12)
        .background {
            RoundedRectangle(cornerRadius: 18, style: .continuous)
                .fill(.regularMaterial)
        }
        .overlay {
            RoundedRectangle(cornerRadius: 18, style: .continuous)
                .strokeBorder(.primary.opacity(0.08), lineWidth: 0.5)
                .allowsHitTesting(false)
        }
        .shadow(color: .black.opacity(0.22), radius: 16, y: 6)
        .accessibilityElement(children: .contain)
        .accessibilityLabel("Scene prompt bar")
        .accessibilityIdentifier("scenePromptBar")
        // An explicit request focuses both an existing bar and one being recreated after dismissal.
        .task(id: focusRequest) { focus.wrappedValue = focusRequest == 0 ? .canvas : .prompt }
    }

    private func generate() {
        focus.wrappedValue = .canvas
        intelligence.send(in: session)
    }
}

@MainActor
struct IntelligenceSettings: View {
    @Bindable var intelligence: SceneIntelligence
    @Environment(\.dismiss) private var dismiss
    @State private var key = ""
    @State private var message: String?

    var body: some View {
        NavigationStack {
            Form {
                Section("On this device") {
                    Label(AppleScenePlanner.availabilityDescription, systemImage: "apple.intelligence")
                    Text("Uses Apple Intelligence when useful, with a built-in scene builder for supported material layouts. If the model declines, is unavailable, or fails, the built-in builder continues with concrete choices. Prompts stay on your device.")
                        .font(.caption).foregroundStyle(.secondary)
                }
                Section("Built-in scene builder") {
                    Label("Always available · no model or API key", systemImage: "square.stack.3d.up")
                    Text("Supports the game’s material catalog, including explosive and energy elements, in simple containers and layouts. Select Built-in to use it directly. Unknown or complex requests need explicit layout choices; they are not silently turned into unrelated scenes.")
                        .font(.caption).foregroundStyle(.secondary)
                }
                Section("Cloud · OpenAI") {
                    if let error = intelligence.credentialError {
                        Text(error).font(.caption).foregroundStyle(.red)
                    }
                    TextField("Model ID", text: $intelligence.modelID)
                        .autocorrectionDisabled()
                    SecureField(intelligence.hasCloudKey ? "Replace saved API key" : "API key", text: $key)
                        .autocorrectionDisabled()
                        .onSubmit(save)
                    HStack {
                        Button("Save key", action: save).disabled(key.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty)
                        Spacer()
                        if intelligence.hasCloudKey {
                            Label("Saved in Keychain", systemImage: "checkmark.shield").font(.caption)
                            Button("Remove", role: .destructive) {
                                do { try intelligence.removeKey(); message = "Key removed." }
                                catch { message = error.localizedDescription }
                            }
                        }
                    }
                    Text("Cloud discussion and generation send your recent conversation, relevant reference summaries and supported simulation rules to OpenAI. API usage is billed to your account. Keys are stored in this device's Keychain.")
                        .font(.caption).foregroundStyle(.secondary)
                }
                Section("How scenes are built") {
                    Text("The assistant discusses missing choices, prepares a preview and simulates 45 steps. A built-in fallback keeps supported scene generation available when a model cannot help. Confirm the preview to place its initial state on the canvas. Press Play to run it; Undo restores your previous experiment.")
                        .font(.callout)
                    Text("The full upstream element library is available; complex machine layouts can still require adjustment. Inspect shows the plan's expectations separately from observed reactions.")
                        .font(.caption).foregroundStyle(.secondary)
                }
                if let message { Section { Text(message).font(.callout) } }
            }
            .formStyle(.grouped)
            .navigationTitle("Intelligence")
            .toolbar { ToolbarItem(placement: .confirmationAction) { Button("Done") { dismiss() } } }
        }
        .frame(width: 550, height: 620)
        .onAppear { intelligence.refreshCredentialState() }
    }

    private func save() {
        do { try intelligence.saveKey(key); key = ""; message = "API key saved securely." }
        catch { message = error.localizedDescription }
    }
}

@MainActor
struct ScenePlanInspector: View {
    let intelligence: SceneIntelligence
    @Environment(\.dismiss) private var dismiss

    var body: some View {
        NavigationStack {
            List {
                if let plan = intelligence.displayedPlan {
                    Section(plan.title) {
                        Text(plan.explanation)
                        Text("Materials: " + Set(plan.commands.filter { $0.material != "NONE" }.map(\.material)).sorted().joined(separator: ", "))
                            .font(.caption).foregroundStyle(.secondary)
                    }
                    if let trial = intelligence.displayedTrial {
                        Section("Observed · 45 simulation steps") {
                            Text(trial.summary)
                            Text("This short check detects initial changes; it does not prove every expected behavior.")
                                .font(.caption).foregroundStyle(.secondary)
                        }
                    }
                    Section("Expected game behavior") {
                        ForEach(Array(plan.expectations.enumerated()), id: \.offset) { _, item in Text(item) }
                    }
                    let warnings = plan.warnings + (intelligence.displayedTrial?.warnings ?? [])
                    if !warnings.isEmpty {
                        Section("Limitations and checks") {
                            ForEach(Array(warnings.enumerated()), id: \.offset) { _, item in
                                Label(item, systemImage: "exclamationmark.triangle").foregroundStyle(.orange)
                            }
                        }
                    }
                    Section("Construction sequence") {
                        ForEach(Array(plan.commands.enumerated()), id: \.offset) { index, command in
                            HStack(alignment: .top) {
                                Text("\(index + 1)").font(.caption.monospacedDigit()).foregroundStyle(.secondary)
                                VStack(alignment: .leading, spacing: 4) {
                                    Text(command.role).font(.subheadline.weight(.medium))
                                    Text("\(command.material.capitalized) · \(command.shape.rawValue)")
                                        .font(.caption).foregroundStyle(.secondary)
                                }
                            }
                        }
                    }
                } else { Text("Generate a scene to inspect its construction.") }
            }
            .navigationTitle("Scene plan")
            .toolbar { ToolbarItem(placement: .confirmationAction) { Button("Done") { dismiss() } } }
        }
        .frame(width: 600, height: 680)
    }
}
