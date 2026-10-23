import Foundation
import Synchronization
import Testing
@testable import VoxLab

/// Provider factice : enregistre les messages et répond via `reply`.
final class MockLLMProvider: LLMProvider {
    let maxInputCharacters: Int?
    let calls = Mutex<[(system: String, user: String)]>([])
    private let reply: @Sendable (String) throws -> String

    init(maxInputCharacters: Int? = nil, reply: @escaping @Sendable (String) throws -> String) {
        self.maxInputCharacters = maxInputCharacters
        self.reply = reply
    }

    func complete(system: String, user: String) async throws -> String {
        calls.withLock { $0.append((system, user)) }
        return try reply(user)
    }
}

/// Partie « texte à corriger » d'un message utilisateur.
private func textToCorrect(in user: String) -> String {
    user.components(separatedBy: "Texte à corriger :\n").last ?? user
}

@Suite("TextChunker")
struct TextChunkerTests {
    @Test("Texte court : un seul bloc")
    func singleChunk() {
        #expect(TextChunker.chunks(of: "a\nb\nc", maxCharacters: 100) == [["a", "b", "c"]])
    }

    @Test("Ne coupe jamais une ligne, et coupe de préférence à une fin de couplet")
    func prefersStanzaBreaks() {
        let text = "un un\ndeux deux\n\ntrois trois\nquatre"
        // 30 caractères : « un un », « deux deux » et la ligne vide tiennent, pas « trois trois ».
        let chunks = TextChunker.chunks(of: text, maxCharacters: 30)
        #expect(chunks == [["un un", "deux deux", ""], ["trois trois", "quatre"]])
        #expect(chunks.flatMap { $0 } == text.components(separatedBy: "\n"))
    }

    @Test("Sans couplet, coupe au plus près de la limite")
    func cutsWithoutStanzas() {
        let lines = (1...10).map { "ligne \($0)" }
        let chunks = TextChunker.chunks(of: lines.joined(separator: "\n"), maxCharacters: 30)
        #expect(chunks.flatMap { $0 } == lines)
        #expect(chunks.allSatisfy { $0.joined(separator: "\n").count < 30 })
    }

    @Test("Une ligne plus longue que la limite forme son propre bloc")
    func oversizedLine() {
        let long = String(repeating: "x", count: 50)
        #expect(TextChunker.chunks(of: "a\n\(long)\nb", maxCharacters: 10) == [["a"], [long], ["b"]])
    }
}

@Suite("LLMCorrector")
struct LLMCorrectorTests {
    let template = "Corrige ce texte en {{language}}."

    private func corrector(_ provider: MockLLMProvider) -> LLMCorrector {
        LLMCorrector(provider: { _ in provider }, promptTemplate: { [template] in template })
    }

    @Test("Prompt système avec le nom de la langue détectée")
    func systemPromptLanguage() async throws {
        let provider = MockLLMProvider { textToCorrect(in: $0) }
        _ = try await corrector(provider).correct("bonjour", language: "it", quality: .max) { _ in }
        #expect(provider.calls.withLock { $0.first?.system } == "Corrige ce texte en italien.")
    }

    @Test("Corrige bloc par bloc, avec en contexte la fin du bloc précédent déjà corrigé")
    func chunkedWithCorrectedContext() async throws {
        let provider = MockLLMProvider(maxInputCharacters: 20) { textToCorrect(in: $0).uppercased() }
        let progress = Mutex<[Double]>([])
        let result = try await corrector(provider).correct("un deux\ntrois quatre\ncinq six", language: "fr", quality: .fast) { value in
            progress.withLock { $0.append(value) }
        }

        #expect(result == "UN DEUX\nTROIS QUATRE\nCINQ SIX")
        let users = provider.calls.withLock { $0.map(\.user) }
        #expect(users.count == 3)
        #expect(users[0] == "un deux")
        #expect(users[1].contains("Contexte (lignes précédentes, déjà corrigées : ne pas les recopier) :\nUN DEUX"))
        #expect(textToCorrect(in: users[2]) == "cinq six")
        #expect(progress.withLock { $0 }.last == 1)
    }

    @Test("Une réponse trop éloignée de l'original est écartée")
    func rejectsImplausibleResponse() async throws {
        let provider = MockLLMProvider { _ in "Voici un résumé : une chanson sur la pluie." }
        let original = "il pleut sur la vile\nje marche sous la pluit\net je pense a toi\nsous la pluie\nsous la pluie"
        let result = try await corrector(provider).correct(original, language: "fr", quality: .max) { _ in }
        #expect(result == original)
    }

    @Test("Nettoie raisonnement, blocs de code et guillemets")
    func cleansResponse() {
        #expect(LLMCorrector.clean("<think>je réfléchis</think>\nIl pleut") == "Il pleut")
        #expect(LLMCorrector.clean("```text\nIl pleut\nsur la ville\n```") == "Il pleut\nsur la ville")
        #expect(LLMCorrector.clean("\"Il pleut\"") == "Il pleut")
    }

    @Test("Retire les lignes vides ajoutées quand l'original n'en a pas")
    func dropsAddedBlankLines() async throws {
        let provider = MockLLMProvider { _ in "Il pleut sur la ville\n\nJe pense à toi\n\nSous la pluie" }
        let result = try await corrector(provider).correct("il pleut sur la vile\nje pense a toi\nsous la pluie", language: "fr", quality: .fast) { _ in }
        #expect(result == "Il pleut sur la ville\nJe pense à toi\nSous la pluie")
    }

    @Test("Garde les lignes vides de l'original (couplets)")
    func keepsStanzaBreaks() {
        #expect(LLMCorrector.matchingBlankLines("A\n\nB", of: "a\n\nb") == "A\n\nB")
    }

    @Test("Transcription vide")
    func emptyTranscript() async {
        let provider = MockLLMProvider { $0 }
        await #expect(throws: CorrectionError.emptyTranscript) {
            try await corrector(provider).correct("  \n ", language: nil, quality: .max) { _ in }
        }
    }

    @Test("Le prompt livré dans l'app respecte la spec")
    func bundledPrompt() throws {
        let prompt = try LLMCorrector.bundledPrompt()
        #expect(prompt.contains("{{language}}"))
        #expect(prompt.contains("refrains"))
        #expect(prompt.contains("garder l'original"))
    }

    @Test("L'étape lit transcript_raw.txt et écrit transcript_corrected.txt")
    func correctStep() async throws {
        let dir = FileManager.default.temporaryDirectory.appending(path: "voxlab-correct-\(UUID().uuidString)")
        try FileManager.default.createDirectory(at: dir, withIntermediateDirectories: true)
        defer { try? FileManager.default.removeItem(at: dir) }
        try "il pleut".write(to: dir.appending(path: JobArtifact.rawTranscript), atomically: true, encoding: .utf8)
        let context = StepContext(jobID: UUID(), directory: dir, source: .file(URL(filePath: "/tmp/a.mp3")), targetLanguage: "en", detectedLanguage: "fr", quality: .max)
        let provider = MockLLMProvider { _ in "Il pleut." }

        let output = try await CorrectStep(corrector: corrector(provider)).run(context) { _ in }

        #expect(output.text == "Il pleut.")
        #expect(try String(contentsOf: dir.appending(path: JobArtifact.correctedTranscript), encoding: .utf8) == "Il pleut.")
    }
}

@Suite("OpenAICompatibleProvider")
struct OpenAICompatibleProviderTests {
    let settings = LLMServerSettings(baseURL: "http://localhost:1234/v1/", model: "mistral")

    @Test("Envoie system + user sans streaming et lit la réponse")
    func chatCompletion() async throws {
        let transport = StubTransport(json: #"{"choices":[{"message":{"role":"assistant","content":"Il pleut."}}]}"#)
        let provider = OpenAICompatibleProvider(settings: { settings }, transport: transport)

        let answer = try await provider.complete(system: "sys", user: "il pleu")

        #expect(answer == "Il pleut.")
        let request = try #require(transport.requests.withLock { $0.first })
        #expect(request.url?.absoluteString == "http://localhost:1234/v1/chat/completions")
        #expect(request.httpMethod == "POST")
        let body = try #require(try JSONSerialization.jsonObject(with: request.httpBody ?? Data()) as? [String: Any])
        #expect(body["model"] as? String == "mistral")
        #expect(body["stream"] as? Bool == false)
        let messages = try #require(body["messages"] as? [[String: String]])
        #expect(messages == [["role": "system", "content": "sys"], ["role": "user", "content": "il pleu"]])
    }

    @Test("Erreur HTTP lisible")
    func httpError() async {
        let provider = OpenAICompatibleProvider(settings: { settings }, transport: StubTransport(status: 404, json: #"{"error":"model not loaded"}"#))
        await #expect(throws: LLMServerError.http(status: 404, body: #"{"error":"model not loaded"}"#)) {
            try await provider.complete(system: "s", user: "u")
        }
    }

    @Test("Réponse vide")
    func emptyResponse() async {
        let provider = OpenAICompatibleProvider(settings: { settings }, transport: StubTransport(json: #"{"choices":[]}"#))
        await #expect(throws: LLMServerError.emptyResponse) {
            try await provider.complete(system: "s", user: "u")
        }
    }

    @Test("URL invalide")
    func invalidURL() async {
        let provider = OpenAICompatibleProvider(settings: { LLMServerSettings(baseURL: "localhost:1234", model: "m") }, transport: StubTransport(json: "{}"))
        await #expect(throws: LLMServerError.invalidURL("localhost:1234")) {
            try await provider.complete(system: "s", user: "u")
        }
    }
}

/// Vraies corrections : Foundation Models et serveur local configuré.
/// `TEST_RUNNER_VOXLAB_INTEGRATION=1 xcodebuild test …`.
@Suite("Intégration LLM", .enabled(if: ProcessInfo.processInfo.environment["VOXLAB_INTEGRATION"] == "1"), .serialized)
struct LLMIntegrationTests {
    let raw = "il pleut sur la vile\nje marche sous la pluit et je pense a toi\nsous la pluie sous la pluie\nsous la pluie sous la pluie"

    private func run(_ provider: any LLMProvider, label: String) async throws -> String {
        let clock = ContinuousClock()
        let start = clock.now
        let result = try await LLMCorrector(provider: { _ in provider }).correct(raw, language: "fr", quality: .max) { _ in }
        print("[\(label)] \(clock.now - start) :\n\(result)")
        return result
    }

    @Test("Foundation Models", .timeLimit(.minutes(5)))
    func foundationModels() async throws {
        let result = try await run(FoundationModelsProvider(), label: "foundation-models")
        #expect(result.components(separatedBy: "\n").count == 4)
        #expect(result.contains("ville"))
    }

    @Test("Serveur local", .timeLimit(.minutes(10)))
    func localServer() async throws {
        let result = try await run(OpenAICompatibleProvider(settings: { LLMServerSettings.load() }), label: "serveur-local")
        #expect(result.components(separatedBy: "\n").count == 4)
        #expect(result.contains("ville"))
        #expect(result.contains("pluie et je pense à toi"))
    }
}
