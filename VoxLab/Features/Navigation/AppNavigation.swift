import Foundation
import Observation
import SwiftUI

/// Sections de la barre latérale.
enum AppSection: String, CaseIterable, Identifiable, Hashable {
    case newJob
    case history
    case diagnostics
    case settings

    var id: String { rawValue }

    var title: String {
        switch self {
        case .newJob: "Nouveau"
        case .history: "Historique"
        case .diagnostics: "Diagnostics"
        case .settings: "Réglages"
        }
    }

    var systemImage: String {
        switch self {
        case .newJob: "plus"
        case .history: "list.bullet"
        case .diagnostics: "stethoscope"
        case .settings: "gearshape.fill"
        }
    }

    var color: Color {
        switch self {
        case .newJob: .orange
        case .history: .red
        case .diagnostics: .green
        case .settings: .gray
        }
    }

    /// Sections du haut ; Réglages est épinglé en bas.
    static let main: [AppSection] = [.newJob, .history, .diagnostics]
}

/// État de navigation partagé : section affichée et pile de l'Historique.
@MainActor
@Observable
final class AppNavigation {
    var section: AppSection = .history
    var historyPath: [UUID] = []

    /// Ouvre le détail d'un job dans l'Historique.
    func showJob(_ id: UUID) {
        section = .history
        historyPath = [id]
    }

    func show(_ section: AppSection) {
        self.section = section
    }
}
