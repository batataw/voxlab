import Foundation

nonisolated struct ImportStep: PipelineStep {
    let step = Step.import
    let fileImporter: any SourceImporter
    /// Import YouTube, absent tant qu'il n'est pas implémenté.
    let urlImporter: (any SourceImporter)?

    @concurrent
    func run(_ context: StepContext, onProgress: @escaping @Sendable (Double) -> Void) async throws -> StepOutput {
        let importer: any SourceImporter
        switch context.source {
        case .file:
            importer = fileImporter
        case .youtube:
            guard let urlImporter else { throw PipelineError.unsupportedSource("YouTube") }
            importer = urlImporter
        }
        let metadata = try await importer.importSource(context.source, to: context.artifact(JobArtifact.source), onProgress: onProgress)
        return StepOutput(title: metadata.title)
    }
}
