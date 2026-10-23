import Foundation

/// Traduit un texte ligne à ligne, en conservant sa structure.
nonisolated protocol Translator: Sendable {
    func translate(
        _ text: String,
        from source: String?,
        to target: String,
        quality: QualityMode,
        onProgress: @escaping @Sendable (Double) -> Void
    ) async throws -> String
}
