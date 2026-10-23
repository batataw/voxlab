import Foundation
import Synchronization
import Testing
@testable import VoxLab

/// Runner factice : renvoie un résultat fixe ou lève l'erreur fournie.
struct StubProcessRunner: ProcessRunning {
    var result: Result<ProcessResult, ProcessRunnerError>

    func run(_ request: ProcessRequest, onEvent: @escaping @Sendable (ProcessEvent) -> Void) async throws(ProcessRunnerError) -> ProcessResult {
        try result.get()
    }
}

/// Transport HTTP factice : enregistre les requêtes et renvoie une réponse fixe.
final class StubTransport: HTTPTransport {
    let requests = Mutex<[URLRequest]>([])
    private let response: @Sendable (URLRequest) throws -> (Int, Data)

    init(response: @escaping @Sendable (URLRequest) throws -> (Int, Data)) {
        self.response = response
    }

    convenience init(status: Int = 200, json: String) {
        self.init { _ in (status, Data(json.utf8)) }
    }

    func data(for request: URLRequest) async throws -> (Data, URLResponse) {
        requests.withLock { $0.append(request) }
        let (status, data) = try response(request)
        return (data, HTTPURLResponse(url: request.url!, statusCode: status, httpVersion: nil, headerFields: nil)!)
    }
}

@Suite("DependencyChecker")
struct DependencyCheckerTests {
    /// `/bin/echo` existe partout : il sert de binaire « présent ».
    let settings = DiagnosticsSettings(
        toolPaths: ToolPaths(ffmpeg: "/bin/echo", ytDlp: "/bin/echo", demucs: "/bin/echo"),
        llmServer: LLMServerSettings(baseURL: "http://localhost:1234/v1", model: "mistral")
    )
    let modelsJSON = #"{"data":[{"id":"mistral"},{"id":"qwen"}]}"#

    private func checker(
        _ result: ProcessResult = .init(exitCode: 0, stdout: "v1", stderr: ""),
        transport: any HTTPTransport = StubTransport(json: #"{"data":[]}"#),
        foundationModels: String? = nil
    ) -> DependencyChecker {
        DependencyChecker(runner: StubProcessRunner(result: .success(result)), transport: transport, foundationModelsAvailability: { foundationModels })
    }

    @Test("Binaire absent → missing")
    func missing() async {
        var settings = settings
        settings.toolPaths.ffmpeg = "/nope/ffmpeg"
        let report = await checker().check(.ffmpeg, settings: settings)
        #expect(report.state == .missing(path: "/nope/ffmpeg"))
    }

    @Test("Binaire présent → première ligne de la version")
    func available() async {
        let report = await checker(.init(exitCode: 0, stdout: "ffmpeg version 8.0\nbuilt with clang\n", stderr: "")).check(.ffmpeg, settings: settings)
        #expect(report.state == .available(details: "ffmpeg version 8.0"))
    }

    @Test("Appel de contrôle en échec → broken")
    func broken() async {
        let report = await checker(.init(exitCode: 1, stdout: "", stderr: "ModuleNotFoundError: torch")).check(.demucs, settings: settings)
        guard case .broken(let message) = report.state else {
            Issue.record("État inattendu : \(report.state)")
            return
        }
        #expect(message.contains("torch"))
    }

    @Test("Serveur LLM : modèle configuré présent")
    func serverWithModel() async throws {
        let transport = StubTransport(json: modelsJSON)
        let report = await checker(transport: transport).check(.llmServer, settings: settings)
        #expect(report.state.isAvailable)
        #expect(transport.requests.withLock { $0.first?.url?.absoluteString } == "http://localhost:1234/v1/models")
    }

    @Test("Serveur LLM : modèle configuré absent")
    func serverWithoutModel() async {
        var settings = settings
        settings.llmServer.model = "llama"
        let report = await checker(transport: StubTransport(json: modelsJSON)).check(.llmServer, settings: settings)
        #expect(report.state == .broken(message: LLMServerError.modelNotFound(model: "llama", available: ["mistral", "qwen"]).localizedDescription))
    }

    @Test("Serveur LLM injoignable")
    func serverDown() async {
        let transport = StubTransport { _ in throw URLError(.cannotConnectToHost) }
        let report = await checker(transport: transport).check(.llmServer, settings: settings)
        #expect(report.state == .broken(message: LLMServerError.unreachable("http://localhost:1234/v1").localizedDescription))
    }

    @Test("Foundation Models indisponible → broken avec la raison")
    func foundationModelsUnavailable() async {
        let report = await checker(foundationModels: "Apple Intelligence n'est pas activé").check(.foundationModels, settings: settings)
        #expect(report.state == .broken(message: "Apple Intelligence n'est pas activé"))
    }

    @Test("checkAll renvoie toutes les dépendances dans l'ordre")
    func checkAllOrder() async {
        let reports = await checker().checkAll(settings: settings)
        #expect(reports.map(\.dependency) == Dependency.allCases)
    }

    @MainActor
    @Test("Les services LLM ne sont pas bloquants")
    func optionalServices() async {
        let transport = StubTransport { _ in throw URLError(.cannotConnectToHost) }
        let viewModel = DiagnosticsViewModel(checker: checker(transport: transport, foundationModels: "indisponible"), loadSettings: { settings })
        await viewModel.refresh()
        #expect(viewModel.missingRequired.isEmpty)
    }
}
