import Foundation
import Synchronization
import Testing
@testable import VoxLab

/// Traducteur factice : préfixe chaque ligne non vide par la langue cible.
final class StubTranslator: Translator {
    let calls = Mutex<[(source: String?, target: String)]>([])

    func translate(_ text: String, from source: String?, to target: String, quality: QualityMode, onProgress: @escaping @Sendable (Double) -> Void) async throws -> String {
        calls.withLock { $0.append((source, target)) }
        onProgress(1)
        return text.components(separatedBy: "\n").map { $0.isEmpty ? $0 : "[\(target)] \($0)" }.joined(separator: "\n")
    }
}

@Suite("Traduction")
struct TranslationTests {
    @Test("Prompt LLM avec langues source et cible, structure ligne à ligne conservée")
    func llmTranslator() async throws {
        let provider = MockLLMProvider { user in
            let text = user.components(separatedBy: "Texte à traiter :\n").last ?? user
            return text.components(separatedBy: "\n").map { "FR: \($0)" }.joined(separator: "\n")
        }
        let translator = LLMTranslator(provider: { _ in provider }, promptTemplate: { "De {{source}} vers {{target}}." })

        let result = try await translator.translate("rain on the town\nI walk alone", from: "en", to: "fr", quality: .max) { _ in }

        #expect(result == "FR: rain on the town\nFR: I walk alone")
        #expect(provider.calls.withLock { $0.first?.system } == "De anglais vers français.")
    }

    @Test("Le prompt de traduction livré dans l'app contient les deux langues")
    func bundledPrompt() throws {
        let prompt = try LLMTranslator.bundledPrompt()
        #expect(prompt.contains("{{source}}"))
        #expect(prompt.contains("{{target}}"))
        #expect(prompt.contains("une ligne de sortie par ligne d'entrée"))
    }

    @Test("Le routage suit le réglage « Traduire via LLM »")
    func routing() async throws {
        let apple = StubTranslator()
        let llm = StubTranslator()
        let useLLM = Mutex(false)
        let router = RoutingTranslator(apple: apple, llm: llm, useLLM: { useLLM.withLock { $0 } })

        _ = try await router.translate("a", from: "en", to: "fr", quality: .max) { _ in }
        useLLM.withLock { $0 = true }
        _ = try await router.translate("a", from: "en", to: "de", quality: .max) { _ in }

        #expect(apple.calls.withLock { $0.map(\.target) } == ["fr"])
        #expect(llm.calls.withLock { $0.map(\.target) } == ["de"])
    }

    @Test("Apple : même langue → texte inchangé ; langue d'origine inconnue → erreur")
    func appleEdgeCases() async throws {
        let text = "Bonjour\n\nÀ demain"
        #expect(try await AppleTranslator().translate(text, from: "fr", to: "fr", quality: .max) { _ in } == text)
        await #expect(throws: AppleTranslationError.unknownSourceLanguage) {
            try await AppleTranslator().translate(text, from: nil, to: "fr", quality: .max) { _ in }
        }
    }

    @Test("L'étape lit le texte corrigé et écrit translation_<langue>.txt")
    func translateStep() async throws {
        let dir = FileManager.default.temporaryDirectory.appending(path: "voxlab-translate-\(UUID().uuidString)")
        try FileManager.default.createDirectory(at: dir, withIntermediateDirectories: true)
        defer { try? FileManager.default.removeItem(at: dir) }
        try "rain\n\nsun".write(to: dir.appending(path: JobArtifact.correctedTranscript), atomically: true, encoding: .utf8)
        let translator = StubTranslator()
        let context = StepContext(jobID: UUID(), directory: dir, source: .file(URL(filePath: "/tmp/a.mp3")), targetLanguage: "it", detectedLanguage: "en", quality: .max)

        let output = try await TranslateStep(translator: translator).run(context) { _ in }

        #expect(output.text == "[it] rain\n\n[it] sun")
        #expect(try String(contentsOf: dir.appending(path: "translation_it.txt"), encoding: .utf8) == "[it] rain\n\n[it] sun")
        #expect(translator.calls.withLock { $0.first?.source } == "en")
    }
}

/// Vraies traductions d'un texte inventé. `TEST_RUNNER_VOXLAB_INTEGRATION=1 xcodebuild test …`.
@Suite("Intégration traduction", .enabled(if: ProcessInfo.processInfo.environment["VOXLAB_INTEGRATION"] == "1"), .serialized)
struct TranslationIntegrationTests {
    let text = "The rain is falling on the empty town\n\nI keep on walking, I won't slow down"

    @Test("Apple Translation anglais → français (si les langues sont installées)")
    func apple() async throws {
        let status = await AppleTranslator.status(from: "en", to: "fr")
        print("[apple] statut en→fr : \(status)")
        guard status == .installed else {
            print("[apple] test ignoré : langues en→fr non installées (bouton « Télécharger » dans le détail du job)")
            return
        }
        let result = try await AppleTranslator().translate(text, from: "en", to: "fr", quality: .max) { _ in }
        print("[apple]\n\(result)")
        #expect(result.components(separatedBy: "\n").count == 3)
        #expect(result.components(separatedBy: "\n")[1].isEmpty)
        #expect(result.lowercased().contains("pluie"))
    }

    @Test("LLM (serveur local) anglais → français", .timeLimit(.minutes(10)))
    func llm() async throws {
        let translator = LLMTranslator(provider: { _ in OpenAICompatibleProvider(settings: { LLMServerSettings.load() }) })
        let result = try await translator.translate(text, from: "en", to: "fr", quality: .max) { _ in }
        print("[llm]\n\(result)")
        #expect(result.components(separatedBy: "\n").count == 3)
        #expect(result.lowercased().contains("pluie"))
    }
}
