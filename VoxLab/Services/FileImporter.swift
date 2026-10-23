import Foundation

nonisolated enum FileImportError: LocalizedError, Equatable {
    case notAFile
    case sourceMissing(String)
    case unsupportedFormat(String)
    case conversionFailed(String)

    var errorDescription: String? {
        switch self {
        case .notAFile:
            "Cette source n'est pas un fichier local."
        case .sourceMissing(let path):
            "Fichier source introuvable : \(path)"
        case .unsupportedFormat(let ext):
            "Format non pris en charge : .\(ext) (formats acceptés : \(FileImporter.supportedExtensions.sorted().joined(separator: ", ")))."
        case .conversionFailed(let details):
            "La conversion ffmpeg a échoué.\n\(details)"
        }
    }
}

/// Convertit un fichier audio local en `source.wav` (44,1 kHz, stéréo).
nonisolated struct FileImporter: SourceImporter {
    static let supportedExtensions: Set<String> = ["mp3", "m4a", "wav", "flac", "aiff", "aif"]

    let converter: AudioConverter

    init(runner: any ProcessRunning, toolPaths: @escaping @Sendable () -> ToolPaths) {
        converter = AudioConverter(runner: runner, toolPaths: toolPaths)
    }

    @concurrent
    func importSource(
        _ source: JobSource,
        to destination: URL,
        onProgress: @escaping @Sendable (Double) -> Void
    ) async throws -> SourceMetadata {
        guard case .file(let input) = source else { throw FileImportError.notAFile }
        let inputPath = input.path(percentEncoded: false)
        guard FileManager.default.fileExists(atPath: inputPath) else {
            throw FileImportError.sourceMissing(inputPath)
        }
        let ext = input.pathExtension.lowercased()
        guard Self.supportedExtensions.contains(ext) else {
            throw FileImportError.unsupportedFormat(ext)
        }
        try await converter.convert(input, to: destination, onProgress: onProgress)
        return SourceMetadata()
    }
}
