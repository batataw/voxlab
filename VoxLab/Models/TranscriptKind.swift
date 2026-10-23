import Foundation

/// Les trois textes d'un job, affichés dans des onglets.
nonisolated enum TranscriptKind: String, CaseIterable, Sendable, Identifiable {
    case raw
    case corrected
    case translated

    var id: String { rawValue }

    var displayName: String {
        switch self {
        case .raw: "Brut"
        case .corrected: "Corrigé"
        case .translated: "Traduit"
        }
    }

    /// Étape qui produit ce texte.
    var producingStep: Step {
        switch self {
        case .raw: .transcribe
        case .corrected: .correct
        case .translated: .translate
        }
    }
}

extension Job {
    func text(_ kind: TranscriptKind) -> String? {
        switch kind {
        case .raw: rawTranscript
        case .corrected: correctedTranscript
        case .translated: translation
        }
    }

    func artifactName(for kind: TranscriptKind) -> String {
        switch kind {
        case .raw: JobArtifact.rawTranscript
        case .corrected: JobArtifact.correctedTranscript
        case .translated: JobArtifact.translation(language: targetLanguage)
        }
    }
}
