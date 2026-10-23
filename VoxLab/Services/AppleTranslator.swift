import Foundation
import os
@preconcurrency import Translation

/// État d'une paire de langues dans Apple Translation.
nonisolated enum TranslationPairStatus: Sendable, Equatable {
    case installed
    /// Paire prise en charge, mais langues à télécharger par le système.
    case downloadable
    case unsupported
}

nonisolated enum AppleTranslationError: LocalizedError, Equatable {
    case unknownSourceLanguage
    case languagesNotInstalled(source: String, target: String)
    case unsupportedPair(source: String, target: String)
    case failed(String)

    var errorDescription: String? {
        switch self {
        case .unknownSourceLanguage:
            "Langue d'origine inconnue : relancez la transcription."
        case .languagesNotInstalled(let source, let target):
            "Les langues \(LanguageName.french(for: source)) → \(LanguageName.french(for: target)) ne sont pas installées. Utilisez le bouton « Télécharger » à côté de la langue cible."
        case .unsupportedPair(let source, let target):
            "Apple Translation ne traduit pas de l'\(LanguageName.french(for: source)) vers l'\(LanguageName.french(for: target)). Activez « Traduire via LLM » dans Réglages."
        case .failed(let details):
            "La traduction a échoué : \(details)"
        }
    }
}

/// Traduction on-device par Apple Translation, ligne à ligne pour conserver la structure.
/// Seules les langues déjà installées sont utilisables hors interface : leur téléchargement
/// passe par `.translationTask` dans la vue du job.
nonisolated struct AppleTranslator: Translator {
    private static let logger = Logger(subsystem: "com.voxlab", category: "Translation")

    @concurrent
    func translate(
        _ text: String,
        from source: String?,
        to target: String,
        quality: QualityMode,
        onProgress: @escaping @Sendable (Double) -> Void
    ) async throws -> String {
        guard let source else { throw AppleTranslationError.unknownSourceLanguage }
        let lines = text.components(separatedBy: "\n")
        guard source != target else { return text }

        switch await Self.status(from: source, to: target) {
        case .installed: break
        case .downloadable: throw AppleTranslationError.languagesNotInstalled(source: source, target: target)
        case .unsupported: throw AppleTranslationError.unsupportedPair(source: source, target: target)
        }

        let session = TranslationSession(installedSource: Locale.Language(identifier: source), target: Locale.Language(identifier: target))
        // Une requête par ligne non vide ; l'index de ligne sert d'identifiant.
        let requests = lines.enumerated()
            .filter { !$0.element.trimmingCharacters(in: .whitespaces).isEmpty }
            .map { TranslationSession.Request(sourceText: $0.element, clientIdentifier: String($0.offset)) }
        guard !requests.isEmpty else { return text }

        var translated = lines
        var done = 0
        do {
            for try await response in session.translate(batch: requests) {
                if let index = response.clientIdentifier.flatMap(Int.init), translated.indices.contains(index) {
                    translated[index] = response.targetText
                }
                done += 1
                onProgress(Double(done) / Double(requests.count))
            }
        } catch is CancellationError {
            throw CancellationError()
        } catch {
            Self.logger.error("Traduction en échec : \(error.localizedDescription, privacy: .public)")
            throw AppleTranslationError.failed(error.localizedDescription)
        }
        return translated.joined(separator: "\n")
    }

    static func status(from source: String, to target: String) async -> TranslationPairStatus {
        let status = await LanguageAvailability().status(
            from: Locale.Language(identifier: source),
            to: Locale.Language(identifier: target)
        )
        switch status {
        case .installed: return .installed
        case .supported: return .downloadable
        case .unsupported: return .unsupported
        @unknown default: return .unsupported
        }
    }
}

/// Choisit Apple Translation ou le LLM selon le réglage « Traduire via LLM ».
nonisolated struct RoutingTranslator: Translator {
    let apple: any Translator
    let llm: any Translator
    let useLLM: @Sendable () -> Bool

    @concurrent
    func translate(
        _ text: String,
        from source: String?,
        to target: String,
        quality: QualityMode,
        onProgress: @escaping @Sendable (Double) -> Void
    ) async throws -> String {
        let translator = useLLM() ? llm : apple
        return try await translator.translate(text, from: source, to: target, quality: quality, onProgress: onProgress)
    }
}
