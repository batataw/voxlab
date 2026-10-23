import Foundation

/// Corrige une transcription brute (orthographe, mots mal reconnus, ponctuation).
nonisolated protocol TranscriptCorrector: Sendable {
    func correct(
        _ text: String,
        language: String?,
        quality: QualityMode,
        onProgress: @escaping @Sendable (Double) -> Void
    ) async throws -> String
}
