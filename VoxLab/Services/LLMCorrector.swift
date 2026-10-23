import Foundation
import os

nonisolated enum CorrectionError: LocalizedError, Equatable {
    case promptMissing
    case emptyTranscript

    var errorDescription: String? {
        switch self {
        case .promptMissing: "Prompt de correction introuvable dans l'application (Prompts/correction.md)."
        case .emptyTranscript: "La transcription brute est vide : rien à corriger."
        }
    }
}

/// Correction par LLM, bloc par bloc ; chaque bloc reçoit en contexte la fin du bloc
/// précédent déjà corrigé (recouvrement). Une réponse trop éloignée du texte d'origine
/// (résumé, ajout, commentaire) est écartée au profit de l'original.
nonisolated struct LLMCorrector: TranscriptCorrector {
    private static let logger = Logger(subsystem: "com.voxlab", category: "Correction")

    /// Lignes du bloc précédent transmises en contexte.
    static let overlapLines = 4

    let provider: @Sendable (QualityMode) -> any LLMProvider
    let promptTemplate: @Sendable () throws -> String

    init(
        provider: @escaping @Sendable (QualityMode) -> any LLMProvider,
        promptTemplate: @escaping @Sendable () throws -> String = { try LLMCorrector.bundledPrompt() }
    ) {
        self.provider = provider
        self.promptTemplate = promptTemplate
    }

    @concurrent
    func correct(
        _ text: String,
        language: String?,
        quality: QualityMode,
        onProgress: @escaping @Sendable (Double) -> Void
    ) async throws -> String {
        let trimmed = text.trimmingCharacters(in: .whitespacesAndNewlines)
        guard !trimmed.isEmpty else { throw CorrectionError.emptyTranscript }

        let provider = provider(quality)
        let system = try Self.systemPrompt(template: promptTemplate(), language: language)
        let chunks = TextChunker.chunks(of: trimmed, maxCharacters: provider.maxInputCharacters ?? .max)

        var corrected: [String] = []
        for (index, lines) in chunks.enumerated() {
            try Task.checkCancellation()
            let chunk = TextChunk(context: Array(corrected.suffix(Self.overlapLines)), lines: lines)
            corrected.append(contentsOf: try await correct(chunk, with: provider, system: system))
            onProgress(Double(index + 1) / Double(chunks.count))
        }
        return corrected.joined(separator: "\n")
    }

    private func correct(_ chunk: TextChunk, with provider: any LLMProvider, system: String) async throws -> [String] {
        let original = chunk.lines.joined(separator: "\n")
        guard !original.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty else { return chunk.lines }

        let response = try await provider.complete(system: system, user: Self.userMessage(for: chunk))
        let cleaned = Self.matchingBlankLines(Self.clean(response), of: original)
        guard Self.isPlausibleCorrection(cleaned, of: original) else {
            Self.logger.warning("Réponse écartée (trop éloignée de l'original) : \(cleaned.prefix(200), privacy: .public)")
            return chunk.lines
        }
        return cleaned.components(separatedBy: "\n")
    }

    static func userMessage(for chunk: TextChunk) -> String {
        let text = chunk.lines.joined(separator: "\n")
        guard !chunk.context.isEmpty else { return text }
        return """
        Contexte (lignes précédentes, déjà corrigées : ne pas les recopier) :
        \(chunk.context.joined(separator: "\n"))

        Texte à corriger :
        \(text)
        """
    }

    static func systemPrompt(template: String, language: String?) -> String {
        let name = language.flatMap { Locale(identifier: "fr").localizedString(forLanguageCode: $0) } ?? "langue inconnue"
        return template.replacingOccurrences(of: "{{language}}", with: name)
    }

    /// Retire ce que les modèles ajoutent parfois : raisonnement `<think>`, blocs de code, guillemets.
    static func clean(_ response: String) -> String {
        var text = response.replacing(/<think>[\s\S]*?<\/think>/, with: "")
        text = text.trimmingCharacters(in: .whitespacesAndNewlines)
        if text.hasPrefix("```") {
            text = text.replacing(/^```[^\n]*\n?/, with: "").replacing(/\n?```$/, with: "")
        }
        if text.count >= 2, text.first == "\"", text.last == "\"" {
            text = String(text.dropFirst().dropLast())
        }
        return text.trimmingCharacters(in: .whitespacesAndNewlines)
    }

    /// Certains modèles (Foundation Models) séparent chaque vers par une ligne vide :
    /// si l'original n'en contient pas, on les retire.
    static func matchingBlankLines(_ corrected: String, of original: String) -> String {
        let hasBlankLines = original.components(separatedBy: "\n").contains { $0.trimmingCharacters(in: .whitespaces).isEmpty }
        guard !hasBlankLines else { return corrected }
        return corrected.components(separatedBy: "\n")
            .filter { !$0.trimmingCharacters(in: .whitespaces).isEmpty }
            .joined(separator: "\n")
    }

    /// Une correction garde à peu près la même longueur et le même nombre de lignes.
    static func isPlausibleCorrection(_ corrected: String, of original: String) -> Bool {
        guard !corrected.isEmpty else { return false }
        let ratio = Double(corrected.count) / Double(max(original.count, 1))
        let originalLines = original.components(separatedBy: "\n").count
        let correctedLines = corrected.components(separatedBy: "\n").count
        let lineDelta = abs(correctedLines - originalLines)
        return (0.6...1.5).contains(ratio) && lineDelta <= max(2, originalLines / 5)
    }

    static func bundledPrompt() throws -> String {
        guard let url = Bundle.main.url(forResource: "correction", withExtension: "md") else {
            throw CorrectionError.promptMissing
        }
        return try String(contentsOf: url, encoding: .utf8)
    }
}

/// Bloc de lignes à corriger, précédé de lignes de contexte à ne pas recopier.
nonisolated struct TextChunk: Sendable, Equatable {
    var context: [String]
    var lines: [String]
}
