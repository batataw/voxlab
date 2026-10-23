import Foundation

nonisolated struct TranscribeStep: PipelineStep {
    let step = Step.transcribe
    let transcriber: any Transcriber

    @concurrent
    func run(_ context: StepContext, onProgress: @escaping @Sendable (Double) -> Void) async throws -> StepOutput {
        let transcription = try await transcriber.transcribe(
            audio: context.artifact(JobArtifact.vocals),
            quality: context.quality,
            onProgress: onProgress
        )
        try transcription.text.write(to: context.artifact(JobArtifact.rawTranscript), atomically: true, encoding: .utf8)
        return StepOutput(text: transcription.text, detectedLanguage: transcription.language)
    }
}
