import AVFoundation
import Foundation
import os

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

/// Convertit un fichier audio local en `source.wav` (44,1 kHz, stéréo, PCM 16 bits) avec ffmpeg.
nonisolated struct FileImporter: SourceImporter {
    static let supportedExtensions: Set<String> = ["mp3", "m4a", "wav", "flac", "aiff", "aif"]
    private static let logger = Logger(subsystem: "com.voxlab", category: "FileImporter")

    let runner: any ProcessRunning
    let toolPaths: @Sendable () -> ToolPaths

    @concurrent
    func importSource(
        _ source: JobSource,
        to destination: URL,
        onProgress: @escaping @Sendable (Double) -> Void
    ) async throws {
        guard case .file(let input) = source else { throw FileImportError.notAFile }
        let inputPath = input.path(percentEncoded: false)
        guard FileManager.default.fileExists(atPath: inputPath) else {
            throw FileImportError.sourceMissing(inputPath)
        }
        let ext = input.pathExtension.lowercased()
        guard Self.supportedExtensions.contains(ext) else {
            throw FileImportError.unsupportedFormat(ext)
        }

        // Écriture dans un fichier temporaire pour ne jamais laisser un source.wav tronqué.
        let partial = destination.deletingPathExtension().appendingPathExtension("partial.wav")
        try? FileManager.default.removeItem(at: partial)
        defer { try? FileManager.default.removeItem(at: partial) }

        let duration = await Self.duration(of: input)
        let request = ProcessRequest(
            executable: ToolPaths.url(for: toolPaths().ffmpeg),
            arguments: Self.arguments(input: input, output: partial),
            environment: ToolEnvironment.base,
            progressParser: duration.map { .ffmpeg(totalSeconds: $0) }
        )
        let result = try await runner.run(request) { event in
            if case .progress(let value) = event { onProgress(value) }
        }
        guard result.succeeded else {
            let details = result.stderr.split(whereSeparator: \.isNewline).suffix(5).joined(separator: "\n")
            throw FileImportError.conversionFailed(details)
        }

        if FileManager.default.fileExists(atPath: destination.path(percentEncoded: false)) {
            try FileManager.default.removeItem(at: destination)
        }
        try FileManager.default.moveItem(at: partial, to: destination)
        Self.logger.info("Import terminé : \(destination.lastPathComponent, privacy: .public)")
    }

    static func arguments(input: URL, output: URL) -> [String] {
        [
            "-hide_banner", "-nostdin", "-y",
            "-i", input.path(percentEncoded: false),
            "-vn", "-ar", "44100", "-ac", "2", "-c:a", "pcm_s16le",
            "-progress", "pipe:1", "-nostats",
            output.path(percentEncoded: false),
        ]
    }

    /// Durée en secondes, pour convertir la sortie `-progress` de ffmpeg en pourcentage.
    private static func duration(of url: URL) async -> Double? {
        guard let duration = try? await AVURLAsset(url: url).load(.duration) else { return nil }
        let seconds = duration.seconds
        return seconds.isFinite && seconds > 0 ? seconds : nil
    }
}
