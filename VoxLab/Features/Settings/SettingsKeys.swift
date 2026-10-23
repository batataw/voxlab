import Foundation

/// Clés `UserDefaults` partagées entre les réglages et les services.
nonisolated enum SettingsKey {
    static let ffmpegPath = "toolPath.ffmpeg"
    static let ytDlpPath = "toolPath.ytDlp"
    static let demucsPath = "toolPath.demucs"
    static let quality = "pipeline.quality"
    static let llmProvider = "llm.provider"
    static let llmServerURL = "llm.server.baseURL"
    static let llmServerModel = "llm.server.model"
}

/// Provider LLM utilisé pour la correction (et, plus tard, la traduction via LLM).
nonisolated enum LLMProviderChoice: String, CaseIterable, Sendable {
    /// Foundation Models en mode Rapide, serveur local en mode Max.
    case automatic
    case foundationModels
    case localServer

    var displayName: String {
        switch self {
        case .automatic: "Selon la qualité"
        case .foundationModels: "Apple Foundation Models"
        case .localServer: "Serveur local (LM Studio, Ollama…)"
        }
    }

    func resolved(for quality: QualityMode) -> LLMProviderChoice {
        guard self == .automatic else { return self }
        return quality == .max ? .localServer : .foundationModels
    }
}

/// Serveur local compatible avec l'API OpenAI.
nonisolated struct LLMServerSettings: Sendable, Equatable {
    var baseURL: String
    var model: String

    static let defaults = LLMServerSettings(
        baseURL: "http://localhost:1234/v1",
        model: "mistralai/mistral-small-3.2"
    )

    static func load(from defaults: UserDefaults = .standard) -> LLMServerSettings {
        LLMServerSettings(
            baseURL: defaults.string(forKey: SettingsKey.llmServerURL) ?? Self.defaults.baseURL,
            model: defaults.string(forKey: SettingsKey.llmServerModel) ?? Self.defaults.model
        )
    }
}

nonisolated extension LLMProviderChoice {
    static func load(from defaults: UserDefaults = .standard) -> LLMProviderChoice {
        defaults.string(forKey: SettingsKey.llmProvider).flatMap(LLMProviderChoice.init(rawValue:)) ?? .automatic
    }
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

    static let defaults = ToolPaths(
        ffmpeg: "/opt/homebrew/bin/ffmpeg",
        ytDlp: "/opt/homebrew/bin/yt-dlp",
        demucs: "~/.voxlab/venv/bin/demucs"
    )

    static func load(from defaults: UserDefaults = .standard) -> ToolPaths {
        let fallback = ToolPaths.defaults
        return ToolPaths(
            ffmpeg: defaults.string(forKey: SettingsKey.ffmpegPath) ?? fallback.ffmpeg,
            ytDlp: defaults.string(forKey: SettingsKey.ytDlpPath) ?? fallback.ytDlp,
            demucs: defaults.string(forKey: SettingsKey.demucsPath) ?? fallback.demucs
        )
    }

    /// Résout `~` en dossier personnel.
    static func url(for path: String) -> URL {
        URL(filePath: (path as NSString).expandingTildeInPath)
    }
}
