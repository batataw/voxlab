import Foundation
import os

/// Bloc de lignes à réécrire, précédé de lignes de contexte à ne pas recopier.
nonisolated struct TextChunk: Sendable, Equatable {
    var context: [String]
    var lines: [String]
}

/// Mécanique commune à la correction et à la traduction par LLM : découpage en blocs,
/// contexte issu du bloc précédent déjà traité, nettoyage de la réponse et rejet des
/// réponses implausibles (le bloc d'origine est alors conservé).
nonisolated struct LLMChunkedRewriter: Sendable {
    private static let logger = Logger(subsystem: "com.voxlab", category: "LLM")

    /// Lignes du bloc précédent transmises en contexte.
    static let overlapLines = 4

    /// Libellé du contexte, par ex. « déjà corrigées ».
    var contextLabel: String
    /// Rapport de longueur accepté entre réponse et original.
    var lengthRatio: ClosedRange<Double>

    func rewrite(
        _ text: String,
        system: String,
        provider: any LLMProvider,
        onProgress: @escaping @Sendable (Double) -> Void
    ) async throws -> String {
        let chunks = TextChunker.chunks(of: text, maxCharacters: provider.maxInputCharacters ?? .max)
        var output: [String] = []
        for (index, lines) in chunks.enumerated() {
            try Task.checkCancellation()
            let chunk = TextChunk(context: Array(output.suffix(Self.overlapLines)), lines: lines)
            output.append(contentsOf: try await rewrite(chunk, system: system, provider: provider))
            onProgress(Double(index + 1) / Double(chunks.count))
        }
        return output.joined(separator: "\n")
    }

    /// Les lignes vides (séparations de couplets) ne sont pas confiées au modèle, qui les supprime
    /// ou en ajoute : on n'envoie que les lignes non vides et on réinsère les vides à leur place.
    private func rewrite(_ chunk: TextChunk, system: String, provider: any LLMProvider) async throws -> [String] {
        let content = chunk.lines.filter { !Self.isBlank($0) }
        guard !content.isEmpty else { return chunk.lines }
        let original = content.joined(separator: "\n")

        let request = TextChunk(context: chunk.context.filter { !Self.isBlank($0) }, lines: content)
        let response = try await provider.complete(system: system, user: userMessage(for: request))
        let rewritten = Self.clean(response).components(separatedBy: "\n").filter { !Self.isBlank($0) }
        guard isPlausible(rewritten.joined(separator: "\n"), of: original) else {
            Self.logger.warning("Réponse écartée (trop éloignée de l'original), \(rewritten.count) lignes")
            return chunk.lines
        }
        return Self.reinsertingBlankLines(of: chunk.lines, into: rewritten)
    }

    /// Replace les lignes vides de l'original quand le modèle a rendu autant de lignes qu'il en a reçu ;
    /// sinon, la correspondance ligne à ligne est perdue et on garde la réponse telle quelle.
    static func reinsertingBlankLines(of original: [String], into rewritten: [String]) -> [String] {
        guard rewritten.count == original.filter({ !isBlank($0) }).count else { return rewritten }
        var remaining = rewritten.makeIterator()
        return original.map { isBlank($0) ? $0 : (remaining.next() ?? $0) }
    }

    private static func isBlank(_ line: String) -> Bool {
        line.trimmingCharacters(in: .whitespaces).isEmpty
    }

    func userMessage(for chunk: TextChunk) -> String {
        let text = chunk.lines.joined(separator: "\n")
        guard !chunk.context.isEmpty else { return text }
        return """
        Contexte (lignes précédentes, \(contextLabel) : ne pas les recopier) :
        \(chunk.context.joined(separator: "\n"))

        Texte à traiter :
        \(text)
        """
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

    /// Une réécriture garde à peu près le même nombre de lignes, et une longueur proche.
    func isPlausible(_ rewritten: String, of original: String) -> Bool {
        guard !rewritten.isEmpty else { return false }
        let ratio = Double(rewritten.count) / Double(max(original.count, 1))
        let originalLines = original.components(separatedBy: "\n").count
        let lineDelta = abs(rewritten.components(separatedBy: "\n").count - originalLines)
        return lengthRatio.contains(ratio) && lineDelta <= max(2, originalLines / 5)
    }
}
