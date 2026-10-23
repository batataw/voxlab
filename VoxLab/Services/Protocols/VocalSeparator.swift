import Foundation

/// Isole la voix d'un fichier audio et écrit le résultat dans `output`.
nonisolated protocol VocalSeparator: Sendable {
    func separate(
        input: URL,
        output: URL,
        quality: QualityMode,
        onProgress: @escaping @Sendable (Double) -> Void
    ) async throws
}
