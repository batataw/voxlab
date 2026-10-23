import Foundation
import os
import Synchronization

nonisolated enum DemucsError: LocalizedError, Equatable {
    case inputMissing(String)
    case separationFailed(String)
    case outputMissing

    var errorDescription: String? {
        switch self {
        case .inputMissing(let path):
            "Fichier à séparer introuvable : \(path). Relancez l'étape Import."
        case .separationFailed(let details):
            "Demucs a échoué.\n\(details)"
        case .outputMissing:
            "Demucs s'est terminé sans produire de piste vocale."
        }
    }
}

/// Isolation de la voix via la CLI Demucs (`--two-stems vocals`), sur MPS avec repli CPU.
nonisolated struct DemucsSeparator: VocalSeparator {
    private static let logger = Logger(subsystem: "com.voxlab", category: "Demucs")

    let runner: any ProcessRunning
    let toolPaths: @Sendable () -> ToolPaths

    @concurrent
    func separate(
        input: URL,
        output: URL,
        quality: QualityMode,
        onProgress: @escaping @Sendable (Double) -> Void
    ) async throws {
        guard FileManager.default.fileExists(atPath: input.path(percentEncoded: false)) else {
            throw DemucsError.inputMissing(input.path(percentEncoded: false))
        }
        let model = DemucsModel(quality: quality)
        let workDirectory = output.deletingLastPathComponent().appending(path: "demucs_tmp", directoryHint: .isDirectory)
        try? FileManager.default.removeItem(at: workDirectory)
        defer { try? FileManager.default.removeItem(at: workDirectory) }

        var lastError = ""
        for device in ["mps", "cpu"] {
            let tracker = Mutex(DemucsProgress(modelCount: model.subModelCount))
            let request = ProcessRequest(
                executable: ToolPaths.url(for: toolPaths().demucs),
                arguments: Self.arguments(model: model, device: device, input: input, workDirectory: workDirectory),
                environment: ToolEnvironment.base.merging(["PYTORCH_ENABLE_MPS_FALLBACK": "1"]) { _, new in new },
                progressParser: .demucs
            )
            Self.logger.info("Séparation \(model.rawValue, privacy: .public) sur \(device, privacy: .public)")
            let result = try await runner.run(request) { event in
                guard case .progress(let value) = event else { return }
                onProgress(tracker.withLock { $0.update(with: value) })
            }
            if result.succeeded {
                try Self.moveVocals(from: workDirectory, to: output)
                return
            }
            lastError = result.stderr.split(whereSeparator: \.isNewline).suffix(5).joined(separator: "\n")
            Self.logger.error("Échec sur \(device, privacy: .public) (code \(result.exitCode)) : \(lastError, privacy: .public)")
            try? FileManager.default.removeItem(at: workDirectory)
            onProgress(0)
        }
        throw DemucsError.separationFailed(lastError)
    }

    static func arguments(model: DemucsModel, device: String, input: URL, workDirectory: URL) -> [String] {
        [
            "-n", model.rawValue,
            "--two-stems", "vocals",
            "-d", device,
            "-o", workDirectory.path(percentEncoded: false),
            "--filename", "{stem}.{ext}",
            input.path(percentEncoded: false),
        ]
    }

    /// Demucs écrit dans `<work>/<modèle>/vocals.wav` : on cherche le fichier sans présumer du chemin exact.
    private static func moveVocals(from workDirectory: URL, to output: URL) throws {
        let enumerator = FileManager.default.enumerator(at: workDirectory, includingPropertiesForKeys: nil)
        guard let vocals = (enumerator?.allObjects as? [URL])?.first(where: { $0.lastPathComponent == "vocals.wav" }) else {
            throw DemucsError.outputMissing
        }
        if FileManager.default.fileExists(atPath: output.path(percentEncoded: false)) {
            try FileManager.default.removeItem(at: output)
        }
        try FileManager.default.moveItem(at: vocals, to: output)
    }
}

nonisolated enum DemucsModel: String, Sendable {
    case htdemucs
    case htdemucsFineTuned = "htdemucs_ft"

    init(quality: QualityMode) {
        self = quality == .max ? .htdemucsFineTuned : .htdemucs
    }

    /// `htdemucs_ft` est un ensemble de 4 modèles : la barre tqdm repart de 0 pour chacun.
    var subModelCount: Int {
        self == .htdemucsFineTuned ? 4 : 1
    }
}

/// Agrège les barres tqdm successives de Demucs en une progression globale.
nonisolated struct DemucsProgress: Sendable {
    let modelCount: Int
    private(set) var completedPasses = 0
    private var last = 0.0

    init(modelCount: Int) {
        self.modelCount = max(modelCount, 1)
    }

    mutating func update(with value: Double) -> Double {
        // Une forte baisse signale le début de la barre du modèle suivant.
        if value + 0.5 < last {
            completedPasses = min(completedPasses + 1, modelCount - 1)
        }
        last = value
        return (Double(completedPasses) + value) / Double(modelCount)
    }
}
