import Foundation

nonisolated enum LLMTranslationError: LocalizedError, Equatable {
    case promptMissing

    var errorDescription: String? {
        "Prompt de traduction introuvable dans l'application (Prompts/translation.md)."
    }
}

/// Traduction par LLM, meilleure qu'Apple Translation sur le registre familier et l'argot.
nonisolated struct LLMTranslator: Translator {
    /// D'une langue à l'autre, la longueur varie davantage qu'en correction.
    static let rewriter = LLMChunkedRewriter(contextLabel: "déjà traduites", lengthRatio: 0.4...2.5)

    let provider: @Sendable (QualityMode) -> any LLMProvider
    let promptTemplate: @Sendable () throws -> String

    init(
        provider: @escaping @Sendable (QualityMode) -> any LLMProvider,
        promptTemplate: @escaping @Sendable () throws -> String = { try LLMTranslator.bundledPrompt() }
    ) {
        self.provider = provider
        self.promptTemplate = promptTemplate
    }

    @concurrent
    func translate(
        _ text: String,
        from source: String?,
        to target: String,
        quality: QualityMode,
        onProgress: @escaping @Sendable (Double) -> Void
    ) async throws -> String {
        let system = try promptTemplate()
            .replacingOccurrences(of: "{{source}}", with: LanguageName.french(for: source))
            .replacingOccurrences(of: "{{target}}", with: LanguageName.french(for: target))
        return try await Self.rewriter.rewrite(text, system: system, provider: provider(quality), onProgress: onProgress)
    }

    static func bundledPrompt() throws -> String {
        guard let url = Bundle.main.url(forResource: "translation", withExtension: "md") else {
            throw LLMTranslationError.promptMissing
        }
        return try String(contentsOf: url, encoding: .utf8)
    }
}
