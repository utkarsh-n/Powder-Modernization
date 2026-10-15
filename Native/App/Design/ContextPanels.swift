import Foundation
import SwiftUI
import PowderEngine

@MainActor
struct RunContextPanel: View {
    @Bindable var session: PlaygroundSession

    var body: some View {
        Form {
            Section("Experiment") {
                Text(session.sceneTitle).font(.headline)
                LabeledContent("State", value: session.isPaused ? "Paused" : "Running")
                LabeledContent("Particles", value: session.particleCount.formatted())
                LabeledContent("Step", value: session.tick.formatted())
                LabeledContent("Canvas", value: "\(session.canvasWidth) × \(session.canvasHeight)")
            }
            Section("Simulation") {
                Toggle("Newtonian gravity", isOn: Binding(get: { session.newtonianGravityEnabled }, set: session.setNewtonianGravity))
                Toggle("Legacy fusion effects", isOn: Binding(get: { session.legacyFusionEnabled }, set: session.setLegacyFusion))
                Text("Build and Inspect pause the simulation. Use Step to follow a reaction one frame at a time.")
                    .font(.caption).foregroundStyle(.secondary)
            }
            Section("Current material") {
                HStack(spacing: 8) {
                    CurrentBrushSwatch(session: session, size: 18)
                    Text(session.currentBrushName)
                }
                Text(session.selectedWall?.summary ?? session.selectedMaterial.summary)
                    .font(.caption).foregroundStyle(.secondary)
                if session.selectedWall == nil {
                    LabeledContent("Element code", value: session.selectedMaterial.identifier)
                    LabeledContent("Category", value: session.selectedMaterial.category)
                }
            }
            Section("Status") {
                Text(session.status).font(.caption).foregroundStyle(.secondary).textSelection(.enabled)
            }
        }
        .formStyle(.grouped).controlSize(.small)
        .navigationTitle("Experiment Inspector")
    }
}

@MainActor
struct InspectContextPanel: View {
    let session: PlaygroundSession
    let intelligence: SceneIntelligence
    let onPlan: () -> Void

    var body: some View {
        Form {
            if let sample = session.inspection {
                Section("Selected cell") {
                    LabeledContent("Position", value: "\(sample.x), \(sample.y)")
                    LabeledContent("Air pressure", value: format(sample.pressure))
                }
                if let matter = sample.matter { particleSection(matter, layer: "Matter") }
                if let energy = sample.energy { particleSection(energy, layer: "Energy") }
                if let wall = sample.wall {
                    Section("Wall") {
                        Text(wall.type.name).font(.headline)
                        Text(wall.type.summary).font(.caption).foregroundStyle(.secondary)
                        LabeledContent("Powered", value: wall.isPowered ? "Yes" : "No")
                        if wall.fanVelocityX != 0 || wall.fanVelocityY != 0 {
                            LabeledContent("Fan velocity", value: "\(format(wall.fanVelocityX)), \(format(wall.fanVelocityY))")
                        }
                    }
                }
                if sample.matter == nil && sample.energy == nil && sample.wall == nil {
                    Section {
                        Text("Empty space").font(.headline)
                        Text("No particle or wall occupies this cell.").font(.caption).foregroundStyle(.secondary)
                    }
                }
            } else {
                Section("Particle inspector") {
                    Label("No selection", systemImage: "scope").font(.headline)
                    Text("Click a particle on the canvas to inspect its temperature, motion, and surrounding pressure.")
                        .foregroundStyle(.secondary)
                }
            }
            if let plan = intelligence.lastPlan, plan.title == session.sceneTitle {
                if let trial = intelligence.trial {
                    Section("Observed · initial 45 steps") { Text(trial.summary).font(.caption) }
                }
                Section("Model expectation") {
                    ForEach(Array(plan.expectations.prefix(2).enumerated()), id: \.offset) { _, expectation in
                        Text(expectation).font(.caption).foregroundStyle(.secondary)
                    }
                    Button("Construction and Checks…", action: onPlan)
                }
            }
        }
        .formStyle(.grouped).controlSize(.small).textSelection(.enabled)
        .navigationTitle("Particle Inspector")
    }

    private func particleSection(_ particle: EngineParticle, layer: String) -> some View {
        Section(layer) {
            HStack(spacing: 8) {
                MaterialSymbol(symbol: particle.material.paletteSymbol, color: particle.material.colorRGB, size: 18)
                Text(particle.material.displayName).font(.headline)
            }
            Text(particle.material.summary).font(.caption).foregroundStyle(.secondary)
            LabeledContent("Element code", value: particle.material.identifier)
            LabeledContent("Temperature", value: "\(format(particle.temperature)) °C")
            LabeledContent("Velocity X", value: format(particle.velocityX))
            LabeledContent("Velocity Y", value: format(particle.velocityY))
            LabeledContent("Life", value: particle.life.formatted())
            if particle.ctype != 0 { LabeledContent("Ctype", value: particle.ctype.formatted()) }
        }
    }
    private func format(_ number: Float) -> String { number.formatted(.number.precision(.fractionLength(1))) }
}
