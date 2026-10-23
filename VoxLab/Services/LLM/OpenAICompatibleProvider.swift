import Foundation
import os

nonisolated enum LLMServerError: LocalizedError, Equatable {
    case invalidURL(String)
    case unreachable(String)
    case http(status: Int, body: String)
    case emptyResponse
    case modelNotFound(model: String, available: [String])

    var errorDescription: String? {
        switch self {
        case .invalidURL(let url):
            "URL du serveur LLM invalide : \(url)"
        case .unreachable(let url):
            "Serveur LLM injoignable (\(url)). Lancez LM Studio et activez son serveur local."
        case .http(let status, let body):
            "Le serveur LLM a répondu \(status).\n\(body.prefix(400))"
        case .emptyResponse:
            "Le serveur LLM a renvoyé une réponse vide."
        case .modelNotFound(let model, let available):
            "Modèle « \(model) » absent du serveur. Disponibles : \(available.isEmpty ? "aucun" : available.joined(separator: ", "))."
        }
    }
}

/// Transport HTTP, remplaçable dans les tests.
nonisolated protocol HTTPTransport: Sendable {
    func data(for request: URLRequest) async throws -> (Data, URLResponse)
}

nonisolated extension URLSession: HTTPTransport {
    func data(for request: URLRequest) async throws -> (Data, URLResponse) {
        try await data(for: request, delegate: nil)
    }
}

/// Serveur local exposant l'API OpenAI (`/chat/completions`, `/models`) : LM Studio, Ollama…
nonisolated struct OpenAICompatibleProvider: LLMProvider {
    private static let logger = Logger(subsystem: "com.voxlab", category: "LLMServer")

    let settings: @Sendable () -> LLMServerSettings
    var transport: any HTTPTransport = URLSession.shared
    /// Les modèles locaux de 24-32B peuvent mettre plusieurs minutes sur un long texte.
    var requestTimeout: TimeInterval = 600

    let maxInputCharacters: Int? = 12_000

    @concurrent
    func complete(system: String, user: String) async throws -> String {
        let settings = settings()
        var request = URLRequest(url: try Self.endpoint("chat/completions", base: settings.baseURL))
        request.httpMethod = "POST"
        request.timeoutInterval = requestTimeout
        request.setValue("application/json", forHTTPHeaderField: "Content-Type")
        request.httpBody = try JSONEncoder().encode(ChatRequest(
            model: settings.model,
            messages: [.init(role: "system", content: system), .init(role: "user", content: user)],
            temperature: 0.2,
            stream: false
        ))

        let data = try await send(request, baseURL: settings.baseURL)
        let response = try JSONDecoder().decode(ChatResponse.self, from: data)
        guard let content = response.choices.first?.message.content, !content.isEmpty else {
            throw LLMServerError.emptyResponse
        }
        return content
    }

    /// Identifiants des modèles exposés par le serveur.
    @concurrent
    func listModels() async throws -> [String] {
        let settings = settings()
        var request = URLRequest(url: try Self.endpoint("models", base: settings.baseURL))
        request.timeoutInterval = 5
        let data = try await send(request, baseURL: settings.baseURL)
        return try JSONDecoder().decode(ModelsResponse.self, from: data).data.map(\.id)
    }

    private func send(_ request: URLRequest, baseURL: String) async throws -> Data {
        let data: Data
        let response: URLResponse
        do {
            (data, response) = try await transport.data(for: request)
        } catch is CancellationError {
            throw CancellationError()
        } catch let error as URLError where error.code == .cancelled {
            throw CancellationError()
        } catch {
            Self.logger.error("Requête en échec : \(error.localizedDescription, privacy: .public)")
            throw LLMServerError.unreachable(baseURL)
        }
        if let http = response as? HTTPURLResponse, !(200..<300).contains(http.statusCode) {
            throw LLMServerError.http(status: http.statusCode, body: String(decoding: data, as: UTF8.self))
        }
        return data
    }

    static func endpoint(_ path: String, base: String) throws -> URL {
        let trimmed = base.hasSuffix("/") ? String(base.dropLast()) : base
        guard let url = URL(string: "\(trimmed)/\(path)"), url.scheme?.hasPrefix("http") == true else {
            throw LLMServerError.invalidURL(base)
        }
        return url
    }
}

private nonisolated struct ChatRequest: Encodable {
    struct Message: Codable {
        var role: String
        var content: String
    }

    var model: String
    var messages: [Message]
    var temperature: Double
    var stream: Bool
}

private nonisolated struct ChatResponse: Decodable {
    struct Choice: Decodable {
        struct Message: Decodable {
            var content: String?
        }
        var message: Message
    }
    var choices: [Choice]
}

private nonisolated struct ModelsResponse: Decodable {
    struct Model: Decodable {
        var id: String
    }
    var data: [Model]
}
