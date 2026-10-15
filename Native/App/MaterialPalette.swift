import SwiftUI
import PowderEngine

@MainActor
struct MaterialPalette: View {
    @Bindable var session: PlaygroundSession
    @State private var query = ""
    @State private var scope: LibraryScope = .everyday

    private var materials: [EngineElement] {
        let search = query.trimmingCharacters(in: .whitespacesAndNewlines)
        return EngineElement.allCases.filter { material in
            guard material != .empty else { return false }
            if !search.isEmpty {
                return "\(material.displayName) \(material.identifier) \(material.name) \(material.summary) \(material.category)"
                    .localizedCaseInsensitiveContains(search)
            }
            return scope.includes(material)
        }.sorted { $0.displayName.localizedStandardCompare($1.displayName) == .orderedAscending }
    }

    private var walls: [EngineWallType] {
        let search = query.trimmingCharacters(in: .whitespacesAndNewlines)
        guard scope == .walls || !search.isEmpty else { return [] }
        return EngineWallType.all.filter {
            search.isEmpty || "\($0.name) \($0.identifier) \($0.summary) walls".localizedCaseInsensitiveContains(search)
        }
    }

    private var selection: Binding<String?> {
        Binding(get: {
            if let wall = session.selectedWall { return "wall:\(wall.identifier)" }
            return "material:\(session.selectedMaterial.identifier)"
        }, set: { value in
            guard let value else { return }
            if let material = EngineElement.allCases.first(where: { "material:\($0.identifier)" == value }) {
                session.setMode(.build)
                session.select(material)
            } else if let wall = EngineWallType.all.first(where: { "wall:\($0.identifier)" == value }) {
                session.setMode(.build)
                session.selectWall(wall)
            }
        })
    }

    var body: some View {
        VStack(spacing: 0) {
            HStack {
                Picker("Library", selection: $scope) {
                    ForEach(LibraryScope.allCases) { item in Text(item.title).tag(item) }
                }
                .labelsHidden().pickerStyle(.menu)
                Spacer(minLength: 0)
            }
            .padding(.horizontal, 12).padding(.vertical, 6)
            List(selection: selection) {
                if !walls.isEmpty {
                    Section("Walls") {
                        ForEach(walls) { wall in
                            HStack(spacing: 8) {
                                MaterialSymbol(symbol: wall.paletteSymbol, color: wall.colorRGB)
                                Text(wall.name).lineLimit(1)
                                Spacer(minLength: 4)
                            }
                            .tag("wall:\(wall.identifier)")
                            .help(wall.summary)
                            .accessibilityLabel("\(wall.name). \(wall.summary)")
                        }
                    }
                }
                if !materials.isEmpty {
                    Section(query.isEmpty ? "Materials" : "Matching materials") {
                        ForEach(materials) { material in
                            HStack(spacing: 8) {
                                MaterialSymbol(symbol: material.paletteSymbol, color: material.colorRGB)
                                Text(material.displayName).lineLimit(1)
                                Spacer(minLength: 4)
                                Text(material.identifier).font(.system(size: 10, design: .monospaced))
                                    .foregroundStyle(.secondary)
                            }
                            .tag("material:\(material.identifier)")
                            .help(material.summary)
                            .accessibilityLabel("\(material.displayName), \(material.identifier). \(material.summary)")
                        }
                    }
                }
            }
            .listStyle(.sidebar)
            .overlay {
                if materials.isEmpty && walls.isEmpty {
                    ContentUnavailableView.search(text: query)
                }
            }
            Divider()
            brushControls.padding(12)
        }
        .searchable(text: $query, placement: .sidebar, prompt: "Find a material or code")
        .navigationTitle("Materials")
    }

    private var brushControls: some View {
        VStack(alignment: .leading, spacing: 10) {
            HStack(spacing: 7) {
                CurrentBrushSwatch(session: session, size: 16)
                Text(session.currentBrushName).font(.headline).lineLimit(1)
            }
            Text(session.selectedWall?.summary ?? session.selectedMaterial.summary)
                .font(.caption).foregroundStyle(.secondary).lineLimit(3)
                .frame(maxWidth: .infinity, alignment: .leading)
            Picker("Tool", selection: $session.tool) {
                ForEach(BrushTool.allCases) { tool in
                    Image(systemName: tool.symbol).tag(tool).help(tool.title)
                        .accessibilityLabel(tool.title)
                }
            }
            .pickerStyle(.segmented).labelsHidden()
            .onChange(of: session.tool) { _, _ in
                if session.mode != .build { session.setMode(.build) }
            }
            HStack(spacing: 8) {
                Text("Size").foregroundStyle(.secondary)
                Slider(value: $session.brushRadius, in: 1...16, step: 1)
                    .accessibilityLabel("Brush radius")
                Text("\(Int(session.brushRadius))").monospacedDigit().frame(width: 20, alignment: .trailing)
            }
            .font(.caption)
            .disabled(session.tool == .sample || session.tool == .pan)
        }
        .controlSize(.small)
    }
}

private enum LibraryScope: String, CaseIterable, Identifiable {
    case everyday, all, fluids, energy, walls
    var id: Self { self }
    var title: String {
        switch self {
        case .everyday: "Everyday materials"
        case .all: "All \(EngineElement.allCases.count - 1) materials"
        case .fluids: "Liquids and gases"
        case .energy: "Energy and radioactive"
        case .walls: "All \(EngineWallType.all.count) walls"
        }
    }
    func includes(_ material: EngineElement) -> Bool {
        switch self {
        case .everyday: MaterialScope.everydayCodes.contains(material.identifier)
        case .all: true
        case .fluids: MaterialScope.fluids.includes(material)
        case .energy: MaterialScope.energy.includes(material)
        case .walls: false
        }
    }
}
