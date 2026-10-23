import Foundation

/// Informations dérivées affichées par les cartes de job, et recherche dans l'historique.
extension Job {
    /// Étape en cours d'exécution, s'il y en a une.
    var runningStep: StepRun? {
        orderedStepRuns.first { $0.status == .running }
    }

    /// Somme des durées des étapes exécutées.
    var totalDuration: TimeInterval? {
        let durations = stepRuns.compactMap(\.duration)
        return durations.isEmpty ? nil : durations.reduce(0, +)
    }

    /// Nombre de lignes non vides de la transcription brute.
    var transcriptLineCount: Int? {
        rawTranscript.map { text in
            text.split(whereSeparator: \.isNewline).count
        }
    }

    /// Libellé de statut des cartes : l'étape en cours et sa progression pendant un traitement.
    var statusLabel: String {
        if let running = runningStep {
            return "\(running.step.displayName) \(Int((running.progress * 100).rounded())) %"
        }
        if overallStatus == .failed, let failed = orderedStepRuns.first(where: { $0.status == .failed }) {
            return "Échec : \(failed.step.displayName.lowercased())"
        }
        return overallStatus.displayName
    }

    /// Vrai si la recherche apparaît dans le titre ou l'un des trois textes (casse et accents ignorés).
    func matches(_ query: String) -> Bool {
        let query = query.trimmingCharacters(in: .whitespacesAndNewlines)
        guard !query.isEmpty else { return true }
        return [title, rawTranscript, correctedTranscript, translation]
            .compactMap { $0 }
            .contains { $0.localizedStandardContains(query) }
    }
}
