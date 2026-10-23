import Foundation

/// Étapes du pipeline, dans l'ordre d'exécution.
nonisolated enum Step: String, Codable, CaseIterable, Sendable, Identifiable {
    case `import`
    case separate
    case transcribe
    case correct
    case translate

    var id: String { rawValue }

    /// Position dans le pipeline (0 = Import).
    var order: Int { Step.allCases.firstIndex(of: self)! }

    var displayName: String {
        switch self {
        case .import: "Import"
        case .separate: "Isolation voix"
        case .transcribe: "Transcription"
        case .correct: "Correction"
        case .translate: "Traduction"
        }
    }

    var systemImage: String {
        switch self {
        case .import: "square.and.arrow.down"
        case .separate: "waveform.path"
        case .transcribe: "text.bubble"
        case .correct: "text.badge.checkmark"
        case .translate: "globe"
        }
    }
}

nonisolated enum StepStatus: String, Codable, CaseIterable, Sendable {
    case pending
    case running
    case done
    case failed
    case cancelled

    var displayName: String {
        switch self {
        case .pending: "En attente"
        case .running: "En cours"
        case .done: "Terminé"
        case .failed: "Échec"
        case .cancelled: "Annulé"
        }
    }
}

/// Origine de l'audio d'un job.
nonisolated enum SourceKind: String, Codable, Sendable {
    case file
    case youtube
}
