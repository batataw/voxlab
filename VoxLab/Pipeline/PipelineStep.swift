import Foundation

/// Données nécessaires à une étape, figées au moment où elle démarre.
nonisolated struct StepContext: Sendable {
    var jobID: UUID
    var directory: URL
    var source: JobSource
    var targetLanguage: String
    var detectedLanguage: String?
    var quality: QualityMode

    func artifact(_ name: String) -> URL {
        directory.appending(path: name)
    }
}

/// Ce qu'une étape renvoie en plus des fichiers qu'elle écrit dans le dossier du job.
nonisolated struct StepOutput: Sendable, Equatable {
    /// Texte produit, copié dans SwiftData (transcription, correction, traduction).
    var text: String?
    var detectedLanguage: String?
}

nonisolated protocol PipelineStep: Sendable {
    var step: Step { get }
    func run(_ context: StepContext, onProgress: @escaping @Sendable (Double) -> Void) async throws -> StepOutput
}

nonisolated enum PipelineError: LocalizedError, Equatable {
    case unsupportedSource(String)

    var errorDescription: String? {
        switch self {
        case .unsupportedSource(let kind):
            "Ce type de source n'est pas encore pris en charge : \(kind)."
        }
    }
}
