import Foundation
import FoundationModels
import os

/// Outils et services externes dont dépend le pipeline.
nonisolated enum Dependency: String, CaseIterable, Sendable, Identifiable {
    case ffmpeg
    case ytDlp
    case demucs
    case foundationModels
    case llmServer

    var id: String { rawValue }

    var displayName: String {
        switch self {
        case .ffmpeg: "ffmpeg"
        case .ytDlp: "yt-dlp"
        case .demucs: "Demucs"
        case .foundationModels: "Apple Foundation Models"
        case .llmServer: "Serveur LLM local"
        }
    }

    /// Les deux providers LLM sont interchangeables : aucun n'est bloquant seul.
    var isRequired: Bool {
        switch self {
        case .ffmpeg, .ytDlp, .demucs: true
        case .foundationModels, .llmServer: false
        }
    }

    var installHint: String {
        switch self {
        case .ffmpeg: "brew install ffmpeg"
        case .ytDlp: "brew install yt-dlp"
        case .demucs: "uv venv --python 3.11 ~/.voxlab/venv && uv pip install --python ~/.voxlab/venv/bin/python demucs \"torch<2.9\" \"torchaudio<2.9\""
        case .foundationModels: "Activer Apple Intelligence dans Réglages Système"
        case .llmServer: "Lancer LM Studio et activer son serveur local"
        }
    }

    /// Chemin du binaire, pour les dépendances qui en sont un.
    func path(in paths: ToolPaths) -> String? {
        switch self {
        case .ffmpeg: paths.ffmpeg
        case .ytDlp: paths.ytDlp
        case .demucs: paths.demucs
        case .foundationModels, .llmServer: nil
        }
    }

    /// Arguments d'un appel rapide qui prouve que le binaire fonctionne.
    fileprivate var probeArguments: [String] {
        switch self {
        case .ffmpeg: ["-version"]
        case .ytDlp: ["--version"]
        // Demucs n'a pas d'option de version ; `--help` charge torch, donc c'est un vrai test.
        case .demucs: ["--help"]
        case .foundationModels, .llmServer: []
        }
    }

    fileprivate var probeTimeout: Duration {
        self == .demucs ? .seconds(60) : .seconds(15)
    }
}

nonisolated enum DependencyState: Sendable, Equatable {
    case available(details: String)
    case missing(path: String)
    case broken(message: String)

    var isAvailable: Bool {
        if case .available = self { true } else { false }
    }
}

nonisolated struct DependencyReport: Sendable, Equatable, Identifiable {
    var dependency: Dependency
    /// Chemin du binaire ou adresse du service.
    var location: String
    var state: DependencyState

    var id: Dependency { dependency }
}

/// Ce que le diagnostic doit savoir pour vérifier chaque dépendance.
nonisolated struct DiagnosticsSettings: Sendable, Equatable {
    var toolPaths: ToolPaths
    var llmServer: LLMServerSettings

    static func load() -> DiagnosticsSettings {
        DiagnosticsSettings(toolPaths: .load(), llmServer: .load())
    }
}

nonisolated protocol DependencyChecking: Sendable {
    func check(_ dependency: Dependency, settings: DiagnosticsSettings) async -> DependencyReport
}

extension DependencyChecking {
    nonisolated func checkAll(settings: DiagnosticsSettings) async -> [DependencyReport] {
        await withTaskGroup(of: DependencyReport.self) { group in
            for dependency in Dependency.allCases {
                group.addTask { await check(dependency, settings: settings) }
            }
            var reports: [DependencyReport] = []
            for await report in group { reports.append(report) }
            return reports.sorted { lhs, rhs in
                Dependency.allCases.firstIndex(of: lhs.dependency)! < Dependency.allCases.firstIndex(of: rhs.dependency)!
            }
        }
    }
}

/// Vérifie chaque binaire (présence puis appel de contrôle) et chaque service LLM.
nonisolated struct DependencyChecker: DependencyChecking {
    private static let logger = Logger(subsystem: "com.voxlab", category: "Diagnostics")

    let runner: any ProcessRunning
    var transport: any HTTPTransport = URLSession.shared
    var foundationModelsAvailability: @Sendable () -> String? = {
        FoundationModelsError.unavailabilityReason(SystemLanguageModel.default.availability)
    }

    @concurrent
    func check(_ dependency: Dependency, settings: DiagnosticsSettings) async -> DependencyReport {
        switch dependency {
        case .foundationModels:
            let reason = foundationModelsAvailability()
            return DependencyReport(
                dependency: dependency,
                location: "Sur l'appareil",
                state: reason.map { .broken(message: $0) } ?? .available(details: "Disponible")
            )
        case .llmServer:
            return await checkServer(settings.llmServer)
        case .ffmpeg, .ytDlp, .demucs:
            return await checkBinary(dependency, path: dependency.path(in: settings.toolPaths) ?? "")
        }
    }

    private func checkBinary(_ dependency: Dependency, path: String) async -> DependencyReport {
        let url = ToolPaths.url(for: path)
        let report = { (state: DependencyState) in
            DependencyReport(dependency: dependency, location: path, state: state)
        }

        guard FileManager.default.isExecutableFile(atPath: url.path(percentEncoded: false)) else {
            Self.logger.notice("\(dependency.displayName, privacy: .public) introuvable : \(path, privacy: .public)")
            return report(.missing(path: path))
        }

        let request = ProcessRequest(
            executable: url,
            arguments: dependency.probeArguments,
            timeout: dependency.probeTimeout
        )
        do {
            let result = try await runner.run(request).checked()
            return report(.available(details: Self.summary(of: result, for: dependency)))
        } catch {
            Self.logger.error("\(dependency.displayName, privacy: .public) en échec : \(error.localizedDescription, privacy: .public)")
            return report(.broken(message: error.localizedDescription))
        }
    }

    private func checkServer(_ server: LLMServerSettings) async -> DependencyReport {
        let report = { (state: DependencyState) in
            DependencyReport(dependency: .llmServer, location: server.baseURL, state: state)
        }
        let provider = OpenAICompatibleProvider(settings: { server }, transport: transport)
        do {
            let models = try await provider.listModels()
            guard models.contains(server.model) else {
                return report(.broken(message: LLMServerError.modelNotFound(model: server.model, available: models).localizedDescription))
            }
            return report(.available(details: "Modèle « \(server.model) » disponible"))
        } catch {
            return report(.broken(message: error.localizedDescription))
        }
    }

    private static func summary(of result: ProcessResult, for dependency: Dependency) -> String {
        if dependency == .demucs { return "Opérationnel" }
        let output = result.stdout.isEmpty ? result.stderr : result.stdout
        let firstLine = output.split(whereSeparator: \.isNewline).first.map(String.init) ?? ""
        return firstLine.isEmpty ? "Opérationnel" : firstLine
    }
}
