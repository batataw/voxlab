import Foundation

nonisolated struct TranslateStep: PipelineStep {
    let step = Step.translate
    let translator: any Translator

    @concurrent
    func run(_ context: StepContext, onProgress: @escaping @Sendable (Double) -> Void) async throws -> StepOutput {
        // Le fichier fait foi : il reflète aussi les éditions manuelles du texte corrigé.
        let corrected = try String(contentsOf: context.artifact(JobArtifact.correctedTranscript), encoding: .utf8)
        let translation = try await translator.translate(
            corrected,
            from: context.detectedLanguage,
            to: context.targetLanguage,
            quality: context.quality,
            onProgress: onProgress
        )
        try translation.write(to: context.artifact(JobArtifact.translation(language: context.targetLanguage)), atomically: true, encoding: .utf8)
        return StepOutput(text: translation)
    }
}
