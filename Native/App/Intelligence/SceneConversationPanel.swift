import SwiftUI
import PowderEngine
import PowderIntelligence

@MainActor
struct SceneConversationPanel: View {
    @Bindable var intelligence: SceneIntelligence
    let session: PlaygroundSession
    let onEdit: () -> Void
    @State private var showHistory = false
    @State private var showReferences = false
    @Environment(\.accessibilityReduceMotion) private var reduceMotion

    var body: some View {
        if !intelligence.messages.isEmpty {
            VStack(alignment: .leading, spacing: 10) {
                HStack {
                    Text("Scene assistant").font(.subheadline.weight(.semibold))
                    Spacer()
                    Button { intelligence.isExpanded.toggle() } label: {
                        Image(systemName: intelligence.isExpanded ? "chevron.down" : "chevron.up")
                    }.accessibilityLabel(intelligence.isExpanded ? "Collapse conversation" : "Expand conversation")
                    Button { intelligence.newConversation(); onEdit() } label: { Image(systemName: "square.and.pencil") }
                        .help("Start a new conversation").accessibilityLabel("New conversation")
                }.buttonStyle(.borderless).controlSize(.small)
                if intelligence.isExpanded {
                    ScrollView {
                        VStack(alignment: .leading, spacing: 12) {
                            if let user = intelligence.messages.last(where: { $0.role == .user }) {
                                Text(user.text).font(.caption).foregroundStyle(.secondary).lineLimit(3)
                            }
                            if let response = intelligence.consultation {
                                Text(response.reply).font(.callout).textSelection(.enabled)
                            } else if intelligence.phase == .placed, let message = intelligence.messages.last {
                                Text(message.text).font(.callout)
                            }
                            questionChoices
                            if let proposal = intelligence.proposal { review(proposal) }
                            referenceLinks
                            if intelligence.messages.count > 2 {
                                DisclosureGroup("Conversation", isExpanded: $showHistory) {
                                    ForEach(intelligence.messages) { message in
                                        VStack(alignment: .leading, spacing: 3) {
                                            Text(message.role == .user ? "You" : "Assistant").font(.caption2.weight(.semibold)).foregroundStyle(.secondary)
                                            Text(message.text).font(.caption).textSelection(.enabled)
                                        }.frame(maxWidth: .infinity, alignment: .leading).padding(.vertical, 4)
                                    }
                                }.font(.caption)
                            }
                        }.frame(maxWidth: .infinity, alignment: .leading).padding(.trailing, 4)
                    }
                    .frame(maxHeight: 250).fixedSize(horizontal: false, vertical: true)
                    .accessibilityIdentifier("sceneConversation")
                }
                if intelligence.phase == .ready {
                    HStack(spacing: 12) {
                        Text(intelligence.canvasChanged(session) ? "The canvas has changed since this preview." : "Preview only · your canvas is unchanged")
                            .font(.caption).foregroundStyle(.secondary)
                        Spacer(minLength: 0)
                        Button("Confirm scene") { intelligence.confirm(into: session) }
                            .buttonStyle(.borderedProminent).controlSize(.small)
                            .disabled(session.isBusy || !intelligence.prompt.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty)
                            .accessibilityIdentifier("confirmScene")
                            .help(intelligence.prompt.isEmpty ? "Replace the canvas with this preview as one undoable edit" : "Send or clear your draft changes before confirming")
                    }
                }
                Divider()
            }
            .animation(reduceMotion ? nil : .easeInOut(duration: 0.16), value: intelligence.isExpanded)
            .confirmationDialog("Replace the changed canvas?", isPresented: $intelligence.needsReplacementConfirmation, titleVisibility: .visible) {
                Button("Replace with preview") { intelligence.confirm(into: session, replaceChangedCanvas: true) }
                Button("Keep current canvas", role: .cancel) {}
            } message: {
                Text("You edited or ran the experiment while this design was being prepared. Replacing it is undoable.")
            }
        }
    }

    @ViewBuilder private var questionChoices: some View {
        if !intelligence.questions.isEmpty {
            VStack(alignment: .leading, spacing: 10) {
                ForEach(intelligence.questions) { question in
                    VStack(alignment: .leading, spacing: 4) {
                        Text(question.title).font(.caption.weight(.medium))
                        Picker(question.title, selection: Binding(get: { intelligence.answers[question.title] ?? question.options[0] },
                                                                  set: { intelligence.answers[question.title] = $0 })) {
                            ForEach(question.options, id: \.self) { Text($0).tag($0) }
                        }.labelsHidden().pickerStyle(.menu).controlSize(.small)
                    }
                }
                HStack {
                    Button("Use these choices") { intelligence.answerQuestions(in: session) }
                        .buttonStyle(.bordered).controlSize(.small).disabled(!intelligence.canAnswer || intelligence.isGenerating)
                        .accessibilityIdentifier("answerDesignQuestions")
                    Text("First options are suggested defaults").font(.caption2).foregroundStyle(.secondary)
                }
            }
        }
    }

    private func review(_ proposal: SceneProposal) -> some View {
        VStack(alignment: .leading, spacing: 8) {
            HStack(alignment: .top, spacing: 12) {
                if let image = intelligence.previewImage {
                    VStack(alignment: .leading, spacing: 4) {
                        Image(decorative: image, scale: 1).resizable().interpolation(.none).scaledToFit()
                            .frame(width: 140, height: 88).clipShape(RoundedRectangle(cornerRadius: 6))
                        Text("Initial layout").font(.caption2).foregroundStyle(.secondary)
                    }.accessibilityLabel("Preview of the initial scene layout")
                }
                VStack(alignment: .leading, spacing: 4) {
                    Text(proposal.title).font(.subheadline.weight(.semibold))
                    Text(proposal.shape + " · " + proposal.style).font(.caption).foregroundStyle(.secondary)
                    Text(proposal.materials.compactMap { EngineElement.named($0)?.displayName }.joined(separator: ", ")).font(.caption)
                }.frame(maxWidth: .infinity, alignment: .leading)
            }
            Text(proposal.behavior).font(.caption).foregroundStyle(.secondary)
            if let trial = intelligence.pendingTrial {
                Label(trial.summary, systemImage: "checkmark.circle").font(.caption)
                Text("This short trial checks initial behavior; it does not prove the entire design works.")
                    .font(.caption2).foregroundStyle(.secondary)
            }
            let warnings = (intelligence.pendingPlan?.warnings ?? []) + (intelligence.pendingTrial?.warnings ?? [])
            ForEach(Array(warnings.enumerated()), id: \.offset) { _, warning in
                Label(warning, systemImage: "info.circle").font(.caption2).foregroundStyle(.secondary)
            }
        }
    }

    @ViewBuilder private var referenceLinks: some View {
        if !intelligence.references.isEmpty {
            DisclosureGroup("Community design references", isExpanded: $showReferences) {
                VStack(alignment: .leading, spacing: 8) {
                    ForEach(intelligence.references) { reference in
                        Link(destination: reference.url) { Label(reference.title, systemImage: "arrow.up.right.square") }
                        Text(reference.summary).font(.caption2).foregroundStyle(.secondary)
                    }
                    Text("Inspired by archive descriptions. These saves have not been run or reproduced here.")
                        .font(.caption2).foregroundStyle(.secondary)
                }.padding(.top, 6)
            }.font(.caption)
        }
    }
}
