import SwiftUI
import UniformTypeIdentifiers
import PowderEngine

@main
struct PowderApp: App {
    @NSApplicationDelegateAdaptor(PowderApplicationDelegate.self) private var appDelegate
    var body: some Scene {
        Window("Powder", id: "experiment") {
            AppContentView()
                .frame(minWidth: 840, minHeight: 560)
        }
        .defaultSize(width: 1180, height: 780)
        .windowToolbarStyle(.unified)
        .commands { PowderCommands() }
    }
}

struct AppContentView: View {
    @State private var session = PlaygroundSession()
    @State private var importing = false
    @State private var exporting = false
    @State private var exportDocument = ExperimentDocument()
    @State private var errorMessage: String?
    @Environment(\.scenePhase) private var scenePhase

    var body: some View {
        WorkspaceView(session: session, onOpen: { importing = true }, onSave: { Task { await export() } })
            .task {
                PowderApplicationDelegate.session = session
                await session.run()
            }
            .onChange(of: scenePhase) { _, phase in
                session.isActive = phase == .active
                if phase != .active { session.finishStroke(); session.autosave() }
            }
            .fileImporter(isPresented: $importing, allowedContentTypes: [.powderExperiment,
                UTType(filenameExtension: "cps") ?? .data, UTType(filenameExtension: "stm") ?? .data]) { result in
                Task {
                    do { try await session.open(try result.get()) }
                    catch { errorMessage = error.localizedDescription }
                }
            }
            .fileExporter(isPresented: $exporting, document: exportDocument,
                          contentType: .powderExperiment, defaultFilename: "Experiment.powderlab") { result in
                switch result {
                case .success: session.status = "Experiment saved"
                case .failure(let error): errorMessage = error.localizedDescription
                }
            }
            .onOpenURL { url in
                Task {
                    do { try await session.open(url) }
                    catch { errorMessage = error.localizedDescription }
                }
            }
            .alert("Couldn’t open or save experiment", isPresented: Binding(
                get: { errorMessage != nil }, set: { if !$0 { errorMessage = nil } }
            )) { Button("OK", role: .cancel) { errorMessage = nil } }
            message: { Text(errorMessage ?? "Unknown error") }
    }

    private func export() async {
        do {
            exportDocument = ExperimentDocument(data: try await session.exportData())
            exporting = true
        } catch { errorMessage = error.localizedDescription }
    }
}

extension UTType {
    static let powderExperiment = UTType(exportedAs: "dev.utkarsh.powder.document", conformingTo: .json)
}

struct ExperimentDocument: FileDocument {
    static var readableContentTypes: [UTType] { [.powderExperiment] }
    var data: Data
    init(data: Data = Data()) { self.data = data }
    init(configuration: ReadConfiguration) throws {
        guard let data = configuration.file.regularFileContents else {
            throw CocoaError(.fileReadCorruptFile)
        }
        _ = try EngineWorld.decode(data)
        self.data = data
    }
    func fileWrapper(configuration: WriteConfiguration) throws -> FileWrapper {
        FileWrapper(regularFileWithContents: data)
    }
}
