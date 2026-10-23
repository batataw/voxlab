import Foundation

nonisolated struct SeparateStep: PipelineStep {
    let step = Step.separate
    let separator: any VocalSeparator

    @concurrent
    func run(_ context: StepContext, onProgress: @escaping @Sendable (Double) -> Void) async throws -> StepOutput {
        try await separator.separate(
            input: context.artifact(JobArtifact.source),
            output: context.artifact(JobArtifact.vocals),
            quality: context.quality,
            onProgress: onProgress
        )
        return StepOutput()
    }
}
