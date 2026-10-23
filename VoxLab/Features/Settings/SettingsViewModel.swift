import Foundation
import Observation

@MainActor
@Observable
final class SettingsViewModel {
    private(set) var availableModels: [String] = []
    private(set) var serverError: String?
    private(set) var isLoadingModels = false

    /// Interroge le serveur LLM pour proposer ses modèles.
    func refreshModels(baseURL: String) async {
        isLoadingModels = true
        defer { isLoadingModels = false }
        let provider = OpenAICompatibleProvider(settings: { LLMServerSettings(baseURL: baseURL, model: "") })
        do {
            availableModels = try await provider.listModels().sorted()
            serverError = nil
        } catch {
            availableModels = []
            serverError = error.localizedDescription
        }
    }
}
