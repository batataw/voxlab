import Foundation

/// Clés `UserDefaults` partagées entre les réglages et les services.
nonisolated enum SettingsKey {
    static let ffmpegPath = "toolPath.ffmpeg"
    static let ytDlpPath = "toolPath.ytDlp"
    static let demucsPath = "toolPath.demucs"
    static let ollamaPath = "toolPath.ollama"
}

/// Chemins des binaires externes, configurables dans Réglages.
nonisolated struct ToolPaths: Sendable, Equatable {
    var ffmpeg: String
    var ytDlp: String
    var demucs: String
    var ollama: String

    static let defaults = ToolPaths(
        ffmpeg: "/opt/homebrew/bin/ffmpeg",
        ytDlp: "/opt/homebrew/bin/yt-dlp",
        demucs: "~/.voxlab/venv/bin/demucs",
        ollama: "/opt/homebrew/bin/ollama"
    )

    static func load(from defaults: UserDefaults = .standard) -> ToolPaths {
        let fallback = ToolPaths.defaults
        return ToolPaths(
            ffmpeg: defaults.string(forKey: SettingsKey.ffmpegPath) ?? fallback.ffmpeg,
            ytDlp: defaults.string(forKey: SettingsKey.ytDlpPath) ?? fallback.ytDlp,
            demucs: defaults.string(forKey: SettingsKey.demucsPath) ?? fallback.demucs,
            ollama: defaults.string(forKey: SettingsKey.ollamaPath) ?? fallback.ollama
        )
    }

    /// Résout `~` en dossier personnel.
    static func url(for path: String) -> URL {
        URL(filePath: (path as NSString).expandingTildeInPath)
    }
}
