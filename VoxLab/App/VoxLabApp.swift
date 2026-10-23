import SwiftData
import SwiftUI

@main
struct VoxLabApp: App {
    private let dependencies: AppDependencies
    private let modelContainer: ModelContainer
    @State private var diagnostics: DiagnosticsViewModel
    @State private var navigation = AppNavigation()

    init() {
        let modelContainer = Self.makeModelContainer()
        let dependencies = AppDependencies.live(modelContext: modelContainer.mainContext)
        self.dependencies = dependencies
        self.modelContainer = modelContainer
        _diagnostics = State(initialValue: DiagnosticsViewModel(checker: dependencies.dependencyChecker))
    }

    var body: some Scene {
        WindowGroup {
            RootView(diagnostics: diagnostics, navigation: navigation)
                .environment(dependencies.jobController)
                .frame(minWidth: 820, minHeight: 560)
        }
        .modelContainer(modelContainer)
        .commands {
            CommandGroup(replacing: .newItem) {
                Button("Nouveau job") { navigation.show(.newJob) }
                    .keyboardShortcut("n")
            }
            // Les réglages sont une section de la fenêtre, pas une fenêtre séparée.
            CommandGroup(replacing: .appSettings) {
                Button("Réglages…") { navigation.show(.settings) }
                    .keyboardShortcut(",")
                Button("Diagnostics") { navigation.show(.diagnostics) }
            }
        }
    }

    /// Sans sandbox, l'emplacement par défaut (`Application Support/default.store`) est partagé
    /// avec les autres apps : la base a donc son propre fichier.
    static var storeURL: URL {
        URL.applicationSupportDirectory
            .appending(path: "VoxLab", directoryHint: .isDirectory)
            .appending(path: "VoxLab.store")
    }

    private static func makeModelContainer() -> ModelContainer {
        // L'app sert d'hôte aux tests : elle ne doit pas toucher à la vraie base.
        let isTestHost = ProcessInfo.processInfo.environment["XCTestConfigurationFilePath"] != nil
        do {
            let configuration: ModelConfiguration
            if isTestHost {
                configuration = ModelConfiguration(isStoredInMemoryOnly: true)
            } else {
                try FileManager.default.createDirectory(at: storeURL.deletingLastPathComponent(), withIntermediateDirectories: true)
                configuration = ModelConfiguration(url: storeURL)
            }
            return try ModelContainer(for: Job.self, StepRun.self, configurations: configuration)
        } catch {
            fatalError("Impossible d'ouvrir la base SwiftData : \(error)")
        }
    }
}
