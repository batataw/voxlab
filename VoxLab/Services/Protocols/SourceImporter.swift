import Foundation

/// Produit `source.wav` (44,1 kHz, stéréo) à partir d'une source audio.
nonisolated protocol SourceImporter: Sendable {
    func importSource(
        _ source: JobSource,
        to destination: URL,
        onProgress: @escaping @Sendable (Double) -> Void
    ) async throws
}
