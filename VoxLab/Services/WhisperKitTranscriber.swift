import CoreML
import Foundation
import os
import Synchronization
@preconcurrency import WhisperKit

nonisolated enum WhisperModel: String, Sendable {
    case largeV3 = "openai_whisper-large-v3"
    case largeV3Turbo = "openai_whisper-large-v3-v20240930_turbo"

    init(quality: QualityMode) {
        self = quality == .max ? .largeV3 : .largeV3Turbo
    }
}

nonisolated enum TranscriptionError: LocalizedError, Equatable {
    case audioMissing(String)
    case modelUnavailable(String)
    case failed(String)
    case noSpeech

    var errorDescription: String? {
        switch self {
        case .audioMissing(let path):
            "Piste vocale introuvable : \(path). Relancez l'étape Isolation voix."
        case .modelUnavailable(let details):
            "Impossible de préparer le modèle Whisper (le premier lancement le télécharge et nécessite une connexion).\n\(details)"
        case .failed(let details):
            "La transcription a échoué : \(details)"
        case .noSpeech:
            "Aucune parole détectée dans la piste vocale."
        }
    }
}

/// Transcription locale via WhisperKit (CoreML). Le modèle chargé est gardé en mémoire
/// entre deux jobs : le chargement de large-v3 coûte plusieurs secondes.
actor WhisperKitTranscriber: Transcriber {
    private static let logger = Logger(subsystem: "com.voxlab", category: "WhisperKit")
    private static let repository = "argmaxinc/whisperkit-coreml"
    /// Part de la barre de progression réservée à la préparation du modèle.
    private static let preparationShare = 0.1
    /// Encodeur et décodeur sur le GPU : sur M1, l'ANE (choix par défaut de WhisperKit) échoue
    /// par intermittence avec large-v3 (« Program Inference error ») et des blocs ressortent vides,
    /// jusqu'à une transcription entièrement vide. Le GPU du M1 Max est aussi plus rapide.
    static let computeOptions = ModelComputeOptions(
        melCompute: .cpuAndGPU,
        audioEncoderCompute: .cpuAndGPU,
        textDecoderCompute: .cpuAndGPU
    )
    /// Écrit après un téléchargement complet : un dossier sans ce marqueur peut être partiel.
    private static let completionMarker = ".voxlab-complete"

    private let modelsDirectory: URL
    private var loaded: (model: WhisperModel, pipe: WhisperKit)?

    init(modelsDirectory: URL = WhisperKitTranscriber.defaultModelsDirectory) {
        self.modelsDirectory = modelsDirectory
    }

    static var defaultModelsDirectory: URL {
        URL.applicationSupportDirectory
            .appending(path: "VoxLab", directoryHint: .isDirectory)
            .appending(path: "models", directoryHint: .isDirectory)
    }

    func transcribe(
        audio: URL,
        quality: QualityMode,
        onProgress: @escaping @Sendable (Double) -> Void
    ) async throws -> Transcription {
        let path = audio.path(percentEncoded: false)
        guard FileManager.default.fileExists(atPath: path) else {
            throw TranscriptionError.audioMissing(path)
        }

        let pipe = try await pipeline(for: WhisperModel(quality: quality)) { fraction in
            onProgress(fraction * Self.preparationShare)
        }
        try Task.checkCancellation()

        // Le callback de WhisperKit renvoie `false` pour interrompre le décodage.
        let cancelled = Mutex(false)
        let progress = pipe.progress
        let poller = Task {
            while !Task.isCancelled {
                onProgress(Self.preparationShare + progress.fractionCompleted * (1 - Self.preparationShare))
                try? await Task.sleep(for: .milliseconds(500))
            }
        }
        defer { poller.cancel() }

        let results: [TranscriptionResult]
        do {
            results = try await withTaskCancellationHandler {
                try await pipe.transcribe(
                    audioPath: path,
                    decodeOptions: Self.decodingOptions,
                    callback: { _ in cancelled.withLock { $0 } ? false : nil }
                )
            } onCancel: {
                cancelled.withLock { $0 = true }
            }
        } catch {
            if Task.isCancelled || error is CancellationError { throw CancellationError() }
            throw TranscriptionError.failed(error.localizedDescription)
        }
        if cancelled.withLock({ $0 }) { throw CancellationError() }

        let transcription = Self.makeTranscription(from: results)
        guard !transcription.text.isEmpty else { throw TranscriptionError.noSpeech }
        onProgress(1)
        return transcription
    }

    /// Options adaptées aux paroles : langue détectée automatiquement, découpage VAD
    /// (la piste vocale contient de longs silences) et texte sans jetons spéciaux.
    private static var decodingOptions: DecodingOptions {
        DecodingOptions(
            task: .transcribe,
            language: nil,
            detectLanguage: true,
            skipSpecialTokens: true,
            chunkingStrategy: .vad
        )
    }

    /// Assemble le texte (un segment par ligne) et retient la langue majoritaire des segments.
    static func makeTranscription(from results: [TranscriptionResult]) -> Transcription {
        var lines: [String] = []
        var languageCounts: [String: Int] = [:]
        for result in results {
            let segmentLines = result.segments
                .map { $0.text.trimmingCharacters(in: .whitespacesAndNewlines) }
                .filter { !$0.isEmpty }
            lines.append(contentsOf: segmentLines)
            if !segmentLines.isEmpty {
                languageCounts[result.language, default: 0] += segmentLines.count
            }
        }
        let language = languageCounts.max { $0.value < $1.value }?.key
        return Transcription(text: lines.joined(separator: "\n"), language: language)
    }

    // MARK: - Modèle

    private func pipeline(
        for model: WhisperModel,
        onProgress: @escaping @Sendable (Double) -> Void
    ) async throws -> WhisperKit {
        if let loaded, loaded.model == model { return loaded.pipe }
        loaded = nil

        let folder = try await modelFolder(for: model, onProgress: onProgress)
        let clock = ContinuousClock()
        let start = clock.now
        do {
            let pipe = try await WhisperKit(WhisperKitConfig(
                modelFolder: folder.path(percentEncoded: false),
                computeOptions: Self.computeOptions,
                verbose: false,
                logLevel: .error,
                prewarm: true,
                load: true,
                download: false
            ))
            Self.logger.info("Modèle \(model.rawValue, privacy: .public) chargé en \(clock.now - start, privacy: .public)")
            loaded = (model, pipe)
            onProgress(1)
            return pipe
        } catch {
            // Modèle corrompu : il sera retéléchargé au prochain essai.
            try? FileManager.default.removeItem(at: folder.appending(path: Self.completionMarker))
            throw TranscriptionError.modelUnavailable(error.localizedDescription)
        }
    }

    /// Dossier local du modèle, téléchargé depuis Hugging Face s'il manque.
    private func modelFolder(
        for model: WhisperModel,
        onProgress: @escaping @Sendable (Double) -> Void
    ) async throws -> URL {
        let local = modelsDirectory
            .appending(path: "models/\(Self.repository)/\(model.rawValue)", directoryHint: .isDirectory)
        if Self.isComplete(local) { return local }

        Self.logger.info("Téléchargement du modèle \(model.rawValue, privacy: .public)")
        do {
            let folder = try await WhisperKit.download(
                variant: model.rawValue,
                downloadBase: modelsDirectory,
                from: Self.repository,
                progressCallback: { progress in onProgress(progress.fractionCompleted) }
            )
            Self.logger.info("Modèle téléchargé dans \(folder.path(percentEncoded: false), privacy: .public)")
            FileManager.default.createFile(atPath: folder.appending(path: Self.completionMarker).path(percentEncoded: false), contents: Data())
            return folder
        } catch {
            throw TranscriptionError.modelUnavailable(error.localizedDescription)
        }
    }

    private static func isComplete(_ folder: URL) -> Bool {
        FileManager.default.fileExists(atPath: folder.appending(path: completionMarker).path(percentEncoded: false))
    }
}
