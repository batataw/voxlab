import Foundation
import SwiftData

/// Un traitement complet : une source audio et les textes produits par le pipeline.
@Model
final class Job {
    @Attribute(.unique) var id: UUID
    var createdAt: Date
    var title: String
    var sourceKindRaw: String
    /// Chemin du fichier d'origine ou URL YouTube.
    var sourceReference: String
    /// Code langue BCP-47 (« fr », « en »…).
    var targetLanguage: String
    var detectedLanguage: String?

    // Les textes sont dupliqués ici (en plus des fichiers) pour l'affichage et la recherche.
    var rawTranscript: String?
    var correctedTranscript: String?
    var translation: String?
    /// Vrai quand le texte corrigé a été modifié à la main après la traduction.
    var isTranslationStale: Bool

    @Relationship(deleteRule: .cascade, inverse: \StepRun.job)
    var stepRuns: [StepRun]

    init(
        id: UUID = UUID(),
        title: String,
        sourceKind: SourceKind,
        sourceReference: String,
        targetLanguage: String,
        createdAt: Date = .now
    ) {
        self.id = id
        self.createdAt = createdAt
        self.title = title
        self.sourceKindRaw = sourceKind.rawValue
        self.sourceReference = sourceReference
        self.targetLanguage = targetLanguage
        self.isTranslationStale = false
        self.stepRuns = Step.allCases.map(StepRun.init(step:))
    }

    var sourceKind: SourceKind {
        SourceKind(rawValue: sourceKindRaw) ?? .file
    }

    /// Étapes triées dans l'ordre du pipeline.
    var orderedStepRuns: [StepRun] {
        stepRuns.sorted { $0.step.order < $1.step.order }
    }

    func stepRun(for step: Step) -> StepRun? {
        stepRuns.first { $0.step == step }
    }

    /// Statut global affiché dans l'historique.
    var overallStatus: StepStatus {
        let statuses = stepRuns.map(\.status)
        if statuses.contains(.running) { return .running }
        if statuses.contains(.failed) { return .failed }
        if statuses.contains(.cancelled) { return .cancelled }
        if !statuses.isEmpty, statuses.allSatisfy({ $0 == .done }) { return .done }
        return .pending
    }

    /// Première étape non terminée : point de reprise du pipeline.
    var resumeStep: Step? {
        orderedStepRuns.first { $0.status != .done }?.step
    }
}
