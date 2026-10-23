import Foundation

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

/// Correction par LLM, bloc par bloc (voir `LLMChunkedRewriter`).
nonisolated struct LLMCorrector: TranscriptCorrector {
    static let rewriter = LLMChunkedRewriter(contextLabel: "déjà corrigées", lengthRatio: 0.6...1.5)

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
        let system = try Self.systemPrompt(template: promptTemplate(), language: language)
        return try await Self.rewriter.rewrite(trimmed, system: system, provider: provider(quality), onProgress: onProgress)
    }

    static func systemPrompt(template: String, language: String?) -> String {
        template.replacingOccurrences(of: "{{language}}", with: LanguageName.french(for: language))
    }

    static func bundledPrompt() throws -> String {
        guard let url = Bundle.main.url(forResource: "correction", withExtension: "md") else {
            throw CorrectionError.promptMissing
        }
        return try String(contentsOf: url, encoding: .utf8)
    }
}

/// Nom d'une langue en français, pour les prompts (« anglais », « italien »…).
nonisolated enum LanguageName {
    static func french(for code: String?) -> String {
        code.flatMap { Locale(identifier: "fr").localizedString(forLanguageCode: $0) } ?? "langue inconnue"
    }
}
