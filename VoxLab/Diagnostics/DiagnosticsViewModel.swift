import Foundation
import Observation

@MainActor
@Observable
final class DiagnosticsViewModel {
    private(set) var reports: [DependencyReport] = []
    private(set) var isChecking = false

    private let checker: any DependencyChecking
    private let loadSettings: () -> DiagnosticsSettings

    init(checker: any DependencyChecking, loadSettings: @escaping () -> DiagnosticsSettings = { DiagnosticsSettings.load() }) {
        self.checker = checker
        self.loadSettings = loadSettings
    }

    /// Dépendances obligatoires absentes ou en échec.
    var missingRequired: [DependencyReport] {
        reports.filter { $0.dependency.isRequired && !$0.state.isAvailable }
    }

    var hasCheckedOnce: Bool { !reports.isEmpty }

    func refresh() async {
        guard !isChecking else { return }
        isChecking = true
        defer { isChecking = false }
        reports = await checker.checkAll(settings: loadSettings())
    }
}
