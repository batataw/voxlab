import Foundation
import Synchronization
import Testing
@testable import VoxLab

/// Runner programmable : chaque appel est enregistré et traité par `handler`.
final class ScriptedProcessRunner: ProcessRunning {
    let requests = Mutex<[ProcessRequest]>([])
    private let handler: @Sendable (ProcessRequest, @Sendable (ProcessEvent) -> Void) throws(ProcessRunnerError) -> ProcessResult

    init(handler: @escaping @Sendable (ProcessRequest, @Sendable (ProcessEvent) -> Void) throws(ProcessRunnerError) -> ProcessResult) {
        self.handler = handler
    }

    func run(_ request: ProcessRequest, onEvent: @escaping @Sendable (ProcessEvent) -> Void) async throws(ProcessRunnerError) -> ProcessResult {
        requests.withLock { $0.append(request) }
        return try handler(request, onEvent)
    }
}

private func makeTempDirectory() throws -> URL {
    let url = FileManager.default.temporaryDirectory.appending(path: "voxlab-audio-\(UUID().uuidString)")
    try FileManager.default.createDirectory(at: url, withIntermediateDirectories: true)
    return url
}

private func argument(after flag: String, in arguments: [String]) -> String? {
    guard let index = arguments.firstIndex(of: flag), arguments.indices.contains(index + 1) else { return nil }
    return arguments[index + 1]
}

@Suite("DemucsSeparator")
struct DemucsSeparatorTests {
    let paths = ToolPaths(ffmpeg: "/bin/echo", ytDlp: "/bin/echo", demucs: "/bin/echo", ollama: "/bin/echo")

    /// Simule Demucs : écrit `<-o>/<modèle>/vocals.wav` sauf sur les devices listés comme défaillants.
    private func fakeDemucs(failingDevices: Set<String>) -> ScriptedProcessRunner {
        ScriptedProcessRunner { request, onEvent throws(ProcessRunnerError) in
            let device = argument(after: "-d", in: request.arguments) ?? ""
            guard !failingDevices.contains(device) else {
                return ProcessResult(exitCode: 1, stdout: "", stderr: "RuntimeError: MPS backend out of memory")
            }
            let model = argument(after: "-n", in: request.arguments) ?? "?"
            let out = URL(filePath: argument(after: "-o", in: request.arguments) ?? "/tmp").appending(path: model)
            try? FileManager.default.createDirectory(at: out, withIntermediateDirectories: true)
            FileManager.default.createFile(atPath: out.appending(path: "vocals.wav").path(percentEncoded: false), contents: Data("voix".utf8))
            onEvent(.progress(1))
            return ProcessResult(exitCode: 0, stdout: "", stderr: "")
        }
    }

    @Test("Mode max : htdemucs_ft sur MPS, vocals.wav déplacé, dossier temporaire supprimé")
    func separatesOnMPS() async throws {
        let dir = try makeTempDirectory()
        defer { try? FileManager.default.removeItem(at: dir) }
        let input = dir.appending(path: JobArtifact.source)
        FileManager.default.createFile(atPath: input.path(percentEncoded: false), contents: Data())
        let output = dir.appending(path: JobArtifact.vocals)
        let runner = fakeDemucs(failingDevices: [])

        try await DemucsSeparator(runner: runner, toolPaths: { paths }).separate(input: input, output: output, quality: .max) { _ in }

        let requests = runner.requests.withLock { $0 }
        #expect(requests.count == 1)
        #expect(argument(after: "-n", in: requests[0].arguments) == "htdemucs_ft")
        #expect(argument(after: "-d", in: requests[0].arguments) == "mps")
        #expect(argument(after: "--two-stems", in: requests[0].arguments) == "vocals")
        #expect(try String(contentsOf: output, encoding: .utf8) == "voix")
        #expect(!FileManager.default.fileExists(atPath: dir.appending(path: "demucs_tmp").path(percentEncoded: false)))
    }

    @Test("Repli sur CPU si MPS échoue")
    func fallsBackToCPU() async throws {
        let dir = try makeTempDirectory()
        defer { try? FileManager.default.removeItem(at: dir) }
        let input = dir.appending(path: JobArtifact.source)
        FileManager.default.createFile(atPath: input.path(percentEncoded: false), contents: Data())
        let runner = fakeDemucs(failingDevices: ["mps"])

        try await DemucsSeparator(runner: runner, toolPaths: { paths })
            .separate(input: input, output: dir.appending(path: JobArtifact.vocals), quality: .fast) { _ in }

        let requests = runner.requests.withLock { $0 }
        #expect(requests.map { argument(after: "-d", in: $0.arguments) } == ["mps", "cpu"])
        #expect(argument(after: "-n", in: requests[0].arguments) == "htdemucs")
    }

    @Test("Échec sur MPS et CPU : erreur lisible")
    func failsOnBothDevices() async throws {
        let dir = try makeTempDirectory()
        defer { try? FileManager.default.removeItem(at: dir) }
        let input = dir.appending(path: JobArtifact.source)
        FileManager.default.createFile(atPath: input.path(percentEncoded: false), contents: Data())

        await #expect(throws: DemucsError.separationFailed("RuntimeError: MPS backend out of memory")) {
            try await DemucsSeparator(runner: fakeDemucs(failingDevices: ["mps", "cpu"]), toolPaths: { paths })
                .separate(input: input, output: dir.appending(path: JobArtifact.vocals), quality: .max) { _ in }
        }
    }

    @Test("L'annulation ne déclenche pas le repli CPU")
    func cancellationDoesNotFallBack() async throws {
        let dir = try makeTempDirectory()
        defer { try? FileManager.default.removeItem(at: dir) }
        let input = dir.appending(path: JobArtifact.source)
        FileManager.default.createFile(atPath: input.path(percentEncoded: false), contents: Data())
        let runner = ScriptedProcessRunner { _, _ throws(ProcessRunnerError) in throw .cancelled }

        await #expect(throws: ProcessRunnerError.cancelled) {
            try await DemucsSeparator(runner: runner, toolPaths: { paths })
                .separate(input: input, output: dir.appending(path: JobArtifact.vocals), quality: .max) { _ in }
        }
        #expect(runner.requests.withLock { $0.count } == 1)
    }

    @Test("Source absente")
    func missingInput() async {
        let runner = fakeDemucs(failingDevices: [])
        await #expect(throws: DemucsError.inputMissing("/nope/source.wav")) {
            try await DemucsSeparator(runner: runner, toolPaths: { paths })
                .separate(input: URL(filePath: "/nope/source.wav"), output: URL(filePath: "/nope/vocals.wav"), quality: .max) { _ in }
        }
    }

    @Test("Progression agrégée sur les 4 modèles de htdemucs_ft")
    func aggregatedProgress() {
        var progress = DemucsProgress(modelCount: 4)
        #expect(progress.update(with: 0) == 0)
        #expect(progress.update(with: 1) == 0.25)
        #expect(progress.update(with: 1) == 0.25)  // tqdm réaffiche 100 % à la fermeture
        #expect(progress.update(with: 0) == 0.25)
        #expect(progress.update(with: 1) == 0.5)
        _ = progress.update(with: 0); _ = progress.update(with: 1)
        _ = progress.update(with: 0)
        #expect(progress.update(with: 1) == 1)
        _ = progress.update(with: 0)  // une barre de trop ne dépasse pas 100 %
        #expect(progress.update(with: 1) == 1)
    }
}

@Suite("FileImporter")
struct FileImporterTests {
    let paths = ToolPaths(ffmpeg: "/bin/echo", ytDlp: "/bin/echo", demucs: "/bin/echo", ollama: "/bin/echo")

    @Test("Convertit en WAV 44,1 kHz stéréo via un fichier temporaire")
    func convertsToWav() async throws {
        let dir = try makeTempDirectory()
        defer { try? FileManager.default.removeItem(at: dir) }
        let input = dir.appending(path: "chanson.MP3")
        FileManager.default.createFile(atPath: input.path(percentEncoded: false), contents: Data())
        let runner = ScriptedProcessRunner { request, _ throws(ProcessRunnerError) in
            FileManager.default.createFile(atPath: request.arguments.last!, contents: Data("wav".utf8))
            return ProcessResult(exitCode: 0, stdout: "", stderr: "")
        }
        let destination = dir.appending(path: JobArtifact.source)

        try await FileImporter(runner: runner, toolPaths: { paths }).importSource(.file(input), to: destination) { _ in }

        let arguments = try #require(runner.requests.withLock { $0.first }).arguments
        #expect(argument(after: "-i", in: arguments) == input.path(percentEncoded: false))
        #expect(argument(after: "-ar", in: arguments) == "44100")
        #expect(argument(after: "-ac", in: arguments) == "2")
        #expect(arguments.last?.hasSuffix("source.partial.wav") == true)
        #expect(try String(contentsOf: destination, encoding: .utf8) == "wav")
        #expect(try FileManager.default.contentsOfDirectory(atPath: dir.path(percentEncoded: false)).sorted() == ["chanson.MP3", "source.wav"])
    }

    @Test("Échec ffmpeg : pas de source.wav et message lisible")
    func conversionFailure() async throws {
        let dir = try makeTempDirectory()
        defer { try? FileManager.default.removeItem(at: dir) }
        let input = dir.appending(path: "chanson.flac")
        FileManager.default.createFile(atPath: input.path(percentEncoded: false), contents: Data())
        let runner = ScriptedProcessRunner { _, _ throws(ProcessRunnerError) in
            ProcessResult(exitCode: 1, stdout: "", stderr: "Invalid data found when processing input")
        }
        let destination = dir.appending(path: JobArtifact.source)

        await #expect(throws: FileImportError.conversionFailed("Invalid data found when processing input")) {
            try await FileImporter(runner: runner, toolPaths: { paths }).importSource(.file(input), to: destination) { _ in }
        }
        #expect(!FileManager.default.fileExists(atPath: destination.path(percentEncoded: false)))
    }

    @Test("Refuse les formats non pris en charge et les fichiers absents")
    func rejectsInvalidInput() async throws {
        let dir = try makeTempDirectory()
        defer { try? FileManager.default.removeItem(at: dir) }
        let video = dir.appending(path: "clip.mov")
        FileManager.default.createFile(atPath: video.path(percentEncoded: false), contents: Data())
        let importer = FileImporter(runner: ScriptedProcessRunner { _, _ throws(ProcessRunnerError) in .init(exitCode: 0, stdout: "", stderr: "") }, toolPaths: { paths })
        let destination = dir.appending(path: JobArtifact.source)

        await #expect(throws: FileImportError.unsupportedFormat("mov")) {
            try await importer.importSource(.file(video), to: destination) { _ in }
        }
        await #expect(throws: FileImportError.sourceMissing("/nope/a.mp3")) {
            try await importer.importSource(.file(URL(filePath: "/nope/a.mp3")), to: destination) { _ in }
        }
    }
}

@Suite("ProgressParser ffmpeg")
struct FFmpegProgressTests {
    @Test func parsesOutTime() {
        #expect(ProgressParser.ffmpeg(totalSeconds: 200).progress(in: "out_time_us=50000000") == 0.25)
        #expect(ProgressParser.ffmpeg(totalSeconds: 200).progress(in: "out_time_us=N/A") == nil)
        #expect(ProgressParser.ffmpeg(totalSeconds: 200).progress(in: "total_size=1024") == nil)
        #expect(ProgressParser.ffmpeg(totalSeconds: 10).progress(in: "out_time_us=99000000") == 1)
    }
}

/// Chaîne réelle ffmpeg → Demucs. Lente : `TEST_RUNNER_VOXLAB_INTEGRATION=1 xcodebuild test …`.
@Suite("Intégration audio", .enabled(if: ProcessInfo.processInfo.environment["VOXLAB_INTEGRATION"] == "1"))
struct AudioIntegrationTests {
    @Test("Import puis séparation d'un signal de 20 s", .timeLimit(.minutes(5)))
    func importAndSeparate() async throws {
        let dir = try makeTempDirectory()
        defer { try? FileManager.default.removeItem(at: dir) }
        let runner = ProcessRunner()
        let paths = ToolPaths.defaults

        // Génère une source m4a de 20 s avec ffmpeg.
        let input = dir.appending(path: "signal.m4a")
        _ = try await runner.run(ProcessRequest(
            executable: ToolPaths.url(for: paths.ffmpeg),
            arguments: ["-hide_banner", "-loglevel", "error", "-f", "lavfi", "-i", "sine=frequency=440:duration=20", input.path(percentEncoded: false)]
        )).checked()

        let source = dir.appending(path: JobArtifact.source)
        let importProgress = Mutex<[Double]>([])
        try await FileImporter(runner: runner, toolPaths: { paths })
            .importSource(.file(input), to: source) { value in importProgress.withLock { $0.append(value) } }
        #expect(FileManager.default.fileExists(atPath: source.path(percentEncoded: false)))
        #expect(importProgress.withLock { $0 }.last == 1)

        let vocals = dir.appending(path: JobArtifact.vocals)
        let separateProgress = Mutex<[Double]>([])
        try await DemucsSeparator(runner: runner, toolPaths: { paths })
            .separate(input: source, output: vocals, quality: .fast) { value in separateProgress.withLock { $0.append(value) } }
        #expect(FileManager.default.fileExists(atPath: vocals.path(percentEncoded: false)))
        #expect(separateProgress.withLock { $0 }.last == 1)
    }
}
