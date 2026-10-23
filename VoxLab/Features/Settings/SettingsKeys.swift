import Foundation

/// Clés `UserDefaults` partagées entre les réglages et les services.
nonisolated enum SettingsKey {
    static let ffmpegPath = "toolPath.ffmpeg"
    static let ytDlpPath = "toolPath.ytDlp"
    static let demucsPath = "toolPath.demucs"
    static let ollamaPath = "toolPath.ollama"
    static let quality = "pipeline.quality"
}

/// Compromis vitesse / qualité appliqué à toutes les étapes.
nonisolated enum QualityMode: String, CaseIterable, Sendable {
    /// htdemucs, large-v3-turbo, Foundation Models.
    case fast
    /// htdemucs_ft, large-v3, Ollama.
    case max

    var displayName: String {
        switch self {
        case .fast: "Rapide"
        case .max: "Max"
        }
    }

    static func load(from defaults: UserDefaults = .standard) -> QualityMode {
        defaults.string(forKey: SettingsKey.quality).flatMap(QualityMode.init(rawValue:)) ?? .max
    }
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
