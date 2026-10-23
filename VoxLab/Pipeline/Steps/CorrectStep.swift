import Foundation

nonisolated struct CorrectStep: PipelineStep {
    let step = Step.correct
    let corrector: any TranscriptCorrector

    @concurrent
    func run(_ context: StepContext, onProgress: @escaping @Sendable (Double) -> Void) async throws -> StepOutput {
        // Le fichier fait foi : il reflète aussi les éditions manuelles du texte brut.
        let raw = try String(contentsOf: context.artifact(JobArtifact.rawTranscript), encoding: .utf8)
        let corrected = try await corrector.correct(raw, language: context.detectedLanguage, quality: context.quality, onProgress: onProgress)
        try corrected.write(to: context.artifact(JobArtifact.correctedTranscript), atomically: true, encoding: .utf8)
        return StepOutput(text: corrected)
    }
}
