import Foundation

/// Modèle de langage local, interrogé en une seule requête (sans streaming).
nonisolated protocol LLMProvider: Sendable {
    /// Taille maximale conseillée du message utilisateur, en caractères ; `nil` si le contexte est large.
    var maxInputCharacters: Int? { get }

    func complete(system: String, user: String) async throws -> String
}
