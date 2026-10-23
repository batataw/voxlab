import Foundation
import Testing
@testable import VoxLab

/// Runner factice : renvoie un résultat fixe ou lève l'erreur fournie.
struct StubProcessRunner: ProcessRunning {
    var result: Result<ProcessResult, ProcessRunnerError>

    func run(_ request: ProcessRequest, onEvent: @escaping @Sendable (ProcessEvent) -> Void) async throws(ProcessRunnerError) -> ProcessResult {
        try result.get()
    }
}

@Suite("DependencyChecker")
struct DependencyCheckerTests {
    /// `/bin/echo` existe partout : il sert de binaire « présent ».
    let presentPaths = ToolPaths(ffmpeg: "/bin/echo", ytDlp: "/bin/echo", demucs: "/bin/echo", ollama: "/bin/echo")

    @Test("Binaire absent → missing")
    func missing() async {
        let checker = DependencyChecker(runner: StubProcessRunner(result: .success(.init(exitCode: 0, stdout: "", stderr: ""))))
        var paths = presentPaths
        paths.ffmpeg = "/nope/ffmpeg"
        let report = await checker.check(.ffmpeg, paths: paths)
        #expect(report.state == .missing(path: "/nope/ffmpeg"))
    }

    @Test("Binaire présent → première ligne de la version")
    func available() async {
        let output = ProcessResult(exitCode: 0, stdout: "ffmpeg version 8.0\nbuilt with clang\n", stderr: "")
        let checker = DependencyChecker(runner: StubProcessRunner(result: .success(output)))
        let report = await checker.check(.ffmpeg, paths: presentPaths)
        #expect(report.state == .available(details: "ffmpeg version 8.0"))
    }

    @Test("Appel de contrôle en échec → broken")
    func broken() async {
        let checker = DependencyChecker(runner: StubProcessRunner(result: .success(.init(exitCode: 1, stdout: "", stderr: "ModuleNotFoundError: torch"))))
        let report = await checker.check(.demucs, paths: presentPaths)
        guard case .broken(let message) = report.state else {
            Issue.record("État inattendu : \(report.state)")
            return
        }
        #expect(message.contains("torch"))
    }

    @Test("checkAll renvoie toutes les dépendances dans l'ordre")
    func checkAllOrder() async {
        let checker = DependencyChecker(runner: StubProcessRunner(result: .success(.init(exitCode: 0, stdout: "v1", stderr: ""))))
        let reports = await checker.checkAll(paths: presentPaths)
        #expect(reports.map(\.dependency) == Dependency.allCases)
    }

    @MainActor
    @Test("Ollama manquant n'est pas bloquant")
    func optionalOllama() async {
        var paths = presentPaths
        paths.ollama = "/nope/ollama"
        let checker = DependencyChecker(runner: StubProcessRunner(result: .success(.init(exitCode: 0, stdout: "v1", stderr: ""))))
        let viewModel = DiagnosticsViewModel(checker: checker, loadPaths: { paths })
        await viewModel.refresh()
        #expect(viewModel.missingRequired.isEmpty)
    }
}
