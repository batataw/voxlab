import AVFoundation
import Foundation
import os

/// Conversion ffmpeg vers le format de travail du pipeline : WAV 44,1 kHz, stéréo, PCM 16 bits.
/// Écrit d'abord un fichier temporaire pour ne jamais laisser un `source.wav` tronqué.
nonisolated struct AudioConverter: Sendable {
    private static let logger = Logger(subsystem: "com.voxlab", category: "AudioConverter")

    let runner: any ProcessRunning
    let toolPaths: @Sendable () -> ToolPaths

    func convert(_ input: URL, to destination: URL, onProgress: @escaping @Sendable (Double) -> Void) async throws {
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
        // Sans durée connue (webm, opus…), ffmpeg ne donne pas de pourcentage : on signale la fin.
        onProgress(1)
        Self.logger.info("Conversion terminée : \(destination.lastPathComponent, privacy: .public)")
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
