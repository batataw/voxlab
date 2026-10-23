import Foundation
import os

/// Outils externes dont dépend le pipeline.
nonisolated enum Dependency: String, CaseIterable, Sendable, Identifiable {
    case ffmpeg
    case ytDlp
    case demucs
    case ollama

    var id: String { rawValue }

    var displayName: String {
        switch self {
        case .ffmpeg: "ffmpeg"
        case .ytDlp: "yt-dlp"
        case .demucs: "Demucs"
        case .ollama: "Ollama"
        }
    }

    /// Ollama n'est qu'un provider LLM alternatif.
    var isRequired: Bool { self != .ollama }

    var installHint: String {
        switch self {
        case .ffmpeg: "brew install ffmpeg"
        case .ytDlp: "brew install yt-dlp"
        case .demucs: "uv venv ~/.voxlab/venv && uv pip install --python ~/.voxlab/venv demucs"
        case .ollama: "brew install ollama"
        }
    }

    func path(in paths: ToolPaths) -> String {
        switch self {
        case .ffmpeg: paths.ffmpeg
        case .ytDlp: paths.ytDlp
        case .demucs: paths.demucs
        case .ollama: paths.ollama
        }
    }

    /// Arguments d'un appel rapide qui prouve que le binaire fonctionne.
    fileprivate var probeArguments: [String] {
        switch self {
        case .ffmpeg: ["-version"]
        case .ytDlp, .ollama: ["--version"]
        // Demucs n'a pas d'option de version ; `--help` charge torch, donc c'est un vrai test.
        case .demucs: ["--help"]
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
    var path: String
    var state: DependencyState

    var id: Dependency { dependency }
}

nonisolated protocol DependencyChecking: Sendable {
    func check(_ dependency: Dependency, paths: ToolPaths) async -> DependencyReport
}

extension DependencyChecking {
    nonisolated func checkAll(paths: ToolPaths) async -> [DependencyReport] {
        await withTaskGroup(of: DependencyReport.self) { group in
            for dependency in Dependency.allCases {
                group.addTask { await check(dependency, paths: paths) }
            }
            var reports: [DependencyReport] = []
            for await report in group { reports.append(report) }
            return reports.sorted { lhs, rhs in
                Dependency.allCases.firstIndex(of: lhs.dependency)! < Dependency.allCases.firstIndex(of: rhs.dependency)!
            }
        }
    }
}

/// Vérifie la présence de chaque binaire puis lance un appel de contrôle.
nonisolated struct DependencyChecker: DependencyChecking {
    private static let logger = Logger(subsystem: "com.voxlab", category: "Diagnostics")

    let runner: any ProcessRunning

    @concurrent
    func check(_ dependency: Dependency, paths: ToolPaths) async -> DependencyReport {
        let path = dependency.path(in: paths)
        let url = ToolPaths.url(for: path)
        let report = { (state: DependencyState) in
            DependencyReport(dependency: dependency, path: path, state: state)
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

    private static func summary(of result: ProcessResult, for dependency: Dependency) -> String {
        if dependency == .demucs { return "Opérationnel" }
        let output = result.stdout.isEmpty ? result.stderr : result.stdout
        let firstLine = output.split(whereSeparator: \.isNewline).first.map(String.init) ?? ""
        return firstLine.isEmpty ? "Opérationnel" : firstLine
    }
}
