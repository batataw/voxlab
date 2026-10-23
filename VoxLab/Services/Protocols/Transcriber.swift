import Foundation

nonisolated struct Transcription: Sendable, Equatable {
    /// Texte brut, un segment reconnu par ligne.
    var text: String
    /// Code langue détecté (« fr », « en »…), s'il est connu.
    var language: String?
}

/// Transcrit un fichier audio (la piste vocale isolée) en texte.
nonisolated protocol Transcriber: Sendable {
    func transcribe(
        audio: URL,
        quality: QualityMode,
        onProgress: @escaping @Sendable (Double) -> Void
    ) async throws -> Transcription
}
