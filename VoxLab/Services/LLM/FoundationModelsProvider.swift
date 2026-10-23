import Foundation
import FoundationModels
import os

nonisolated enum FoundationModelsError: LocalizedError, Equatable {
    case unavailable(String)
    case contextExceeded
    case guardrail
    case unsupportedLanguage
    case refused
    case failed(String)

    var errorDescription: String? {
        switch self {
        case .unavailable(let reason):
            "Apple Foundation Models indisponible : \(reason)"
        case .contextExceeded:
            "Le texte dépasse le contexte de Foundation Models."
        case .guardrail:
            "Foundation Models a refusé ce contenu (garde-fous Apple). Utilisez le serveur local dans Réglages."
        case .unsupportedLanguage:
            "Langue non prise en charge par Foundation Models. Utilisez le serveur local dans Réglages."
        case .refused:
            "Foundation Models a refusé de répondre. Utilisez le serveur local dans Réglages."
        case .failed(let details):
            "Foundation Models a échoué : \(details)"
        }
    }

    /// Message lisible pour une indisponibilité du modèle système, `nil` s'il est disponible.
    static func unavailabilityReason(_ availability: SystemLanguageModel.Availability) -> String? {
        switch availability {
        case .available:
            nil
        case .unavailable(.deviceNotEligible):
            "ce Mac n'est pas compatible avec Apple Intelligence."
        case .unavailable(.appleIntelligenceNotEnabled):
            "Apple Intelligence n'est pas activé (Réglages Système › Apple Intelligence et Siri)."
        case .unavailable(.modelNotReady):
            "le modèle est en cours de téléchargement par le système."
        case .unavailable(let other):
            "\(other)"
        }
    }
}

/// Modèle on-device d'Apple. Contexte d'environ 4 096 jetons partagés entre instructions,
/// texte envoyé et réponse : le corrector découpe le texte en conséquence.
nonisolated struct FoundationModelsProvider: LLMProvider {
    private static let logger = Logger(subsystem: "com.voxlab", category: "FoundationModels")

    /// Environ 1 000 jetons en entrée : la réponse fait à peu près la même taille.
    let maxInputCharacters: Int? = 3_000

    @concurrent
    func complete(system: String, user: String) async throws -> String {
        // Garde-fous assouplis : on transforme un texte fourni par l'utilisateur (des paroles).
        let model = SystemLanguageModel(guardrails: .permissiveContentTransformations)
        if let reason = FoundationModelsError.unavailabilityReason(model.availability) {
            throw FoundationModelsError.unavailable(reason)
        }
        let session = LanguageModelSession(model: model, instructions: system)
        do {
            let response = try await session.respond(to: user, options: GenerationOptions(temperature: 0.2))
            return response.content
        } catch let error as LanguageModelSession.GenerationError {
            Self.logger.error("Génération en échec : \(error.localizedDescription, privacy: .public)")
            switch error {
            case .exceededContextWindowSize: throw FoundationModelsError.contextExceeded
            case .guardrailViolation: throw FoundationModelsError.guardrail
            case .unsupportedLanguageOrLocale: throw FoundationModelsError.unsupportedLanguage
            case .refusal: throw FoundationModelsError.refused
            default: throw FoundationModelsError.failed(error.localizedDescription)
            }
        }
    }
}
