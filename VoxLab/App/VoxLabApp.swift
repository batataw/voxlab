import SwiftData
import SwiftUI

@main
struct VoxLabApp: App {
    private let dependencies: AppDependencies
    private let modelContainer: ModelContainer
    @State private var diagnostics: DiagnosticsViewModel

    init() {
        let modelContainer = Self.makeModelContainer()
        let dependencies = AppDependencies.live(modelContext: modelContainer.mainContext)
        self.dependencies = dependencies
        self.modelContainer = modelContainer
        _diagnostics = State(initialValue: DiagnosticsViewModel(checker: dependencies.dependencyChecker))
    }

    var body: some Scene {
        WindowGroup {
            RootView(diagnostics: diagnostics)
                .environment(dependencies.jobController)
        }
        .modelContainer(modelContainer)
        .commands {
            CommandGroup(replacing: .newItem) {
                Button("Nouveau job…") {
                    NotificationCenter.default.post(name: .showNewJob, object: nil)
                }
                .keyboardShortcut("n")
            }
            CommandGroup(after: .appSettings) {
                Button("Diagnostic des dépendances…") {
                    NotificationCenter.default.post(name: .showDiagnostics, object: nil)
                }
            }
        }

        Settings {
            SettingsView()
        }
    }

    private static func makeModelContainer() -> ModelContainer {
        do {
            return try ModelContainer(for: Job.self, StepRun.self)
        } catch {
            fatalError("Impossible d'ouvrir la base SwiftData : \(error)")
        }
    }
}

extension Notification.Name {
    static let showDiagnostics = Notification.Name("VoxLab.showDiagnostics")
    static let showNewJob = Notification.Name("VoxLab.showNewJob")
}
