import Foundation
import os

nonisolated enum YtDlpError: LocalizedError, Equatable {
    case notAYouTubeURL
    case downloadFailed(String)
    case outputMissing

    var errorDescription: String? {
        switch self {
        case .notAYouTubeURL:
            "Cette source n'est pas une URL YouTube."
        case .downloadFailed(let details):
            "Le téléchargement yt-dlp a échoué.\n\(details)"
        case .outputMissing:
            "yt-dlp s'est terminé sans produire de fichier audio."
        }
    }
}

/// Télécharge la meilleure piste audio d'une vidéo YouTube avec yt-dlp,
/// puis la convertit en `source.wav` avec ffmpeg.
nonisolated struct YtDlpImporter: SourceImporter {
    private static let logger = Logger(subsystem: "com.voxlab", category: "YtDlp")
    /// Préfixe des lignes où yt-dlp écrit le titre (`--print before_dl:…`).
    static let titleMarker = "VOXLAB_TITLE="
    /// Part de la progression attribuée au téléchargement (le reste à la conversion).
    private static let downloadShare = 0.85

    let runner: any ProcessRunning
    let toolPaths: @Sendable () -> ToolPaths
    let converter: AudioConverter

    init(runner: any ProcessRunning, toolPaths: @escaping @Sendable () -> ToolPaths) {
        self.runner = runner
        self.toolPaths = toolPaths
        converter = AudioConverter(runner: runner, toolPaths: toolPaths)
    }

    @concurrent
    func importSource(
        _ source: JobSource,
        to destination: URL,
        onProgress: @escaping @Sendable (Double) -> Void
    ) async throws -> SourceMetadata {
        guard case .youtube(let url) = source else { throw YtDlpError.notAYouTubeURL }
        let directory = destination.deletingLastPathComponent()
        let downloadDirectory = directory.appending(path: "download_tmp", directoryHint: .isDirectory)
        try? FileManager.default.removeItem(at: downloadDirectory)
        try FileManager.default.createDirectory(at: downloadDirectory, withIntermediateDirectories: true)
        defer { try? FileManager.default.removeItem(at: downloadDirectory) }

        let request = ProcessRequest(
            executable: ToolPaths.url(for: toolPaths().ytDlp),
            arguments: Self.arguments(url: url, downloadDirectory: downloadDirectory),
            environment: ToolEnvironment.base,
            timeout: .seconds(30 * 60),
            progressParser: .ytDlp
        )
        let result = try await runner.run(request) { event in
            if case .progress(let value) = event { onProgress(value * Self.downloadShare) }
        }
        guard result.succeeded else {
            let details = result.stderr.split(whereSeparator: \.isNewline).suffix(5).joined(separator: "\n")
            throw YtDlpError.downloadFailed(details)
        }
        let title = Self.title(in: result.stdout)

        let files = (try? FileManager.default.contentsOfDirectory(at: downloadDirectory, includingPropertiesForKeys: nil)) ?? []
        guard let audio = files.first(where: { $0.lastPathComponent.hasPrefix("download.") && !$0.pathExtension.hasSuffix("part") }) else {
            throw YtDlpError.outputMissing
        }
        Self.logger.info("Téléchargé : \(audio.lastPathComponent, privacy: .public)")

        try await converter.convert(audio, to: destination) { value in
            onProgress(Self.downloadShare + value * (1 - Self.downloadShare))
        }
        return SourceMetadata(title: title)
    }

    static func arguments(url: URL, downloadDirectory: URL) -> [String] {
        [
            "--no-playlist",
            // m4a d'abord : AVFoundation en lit la durée, d'où une progression de conversion fluide.
            "-f", "bestaudio[ext=m4a]/bestaudio/best",
            // --print rend yt-dlp silencieux : --progress et --newline rétablissent une ligne par mise à jour.
            "--print", "before_dl:\(titleMarker)%(title)s",
            "--progress", "--newline",
            "-o", downloadDirectory.appending(path: "download.%(ext)s").path(percentEncoded: false),
            url.absoluteString,
        ]
    }

    static func title(in stdout: String) -> String? {
        stdout.split(whereSeparator: \.isNewline)
            .first { $0.hasPrefix(titleMarker) }
            .map { String($0.dropFirst(titleMarker.count)).trimmingCharacters(in: .whitespaces) }
            .flatMap { $0.isEmpty ? nil : $0 }
    }
}

/// Validation des URL YouTube saisies par l'utilisateur.
nonisolated enum YouTubeURL {
    private static let hosts: Set<String> = ["youtube.com", "www.youtube.com", "m.youtube.com", "music.youtube.com", "youtu.be"]

    static func parse(_ string: String) -> URL? {
        let trimmed = string.trimmingCharacters(in: .whitespacesAndNewlines)
        guard let url = URL(string: trimmed),
              let scheme = url.scheme?.lowercased(), scheme == "https" || scheme == "http",
              let host = url.host()?.lowercased(), hosts.contains(host)
        else { return nil }
        return url
    }
}
