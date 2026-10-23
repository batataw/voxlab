import Foundation
import Synchronization
import SwiftData
import Testing
@testable import VoxLab

@Suite("Import YouTube")
struct YouTubeImportTests {
    let paths = ToolPaths(ffmpeg: "/bin/echo", ytDlp: "/bin/echo", demucs: "/bin/echo")

    @Test(arguments: [
        "https://www.youtube.com/watch?v=abc123",
        "https://youtu.be/abc123",
        "https://music.youtube.com/watch?v=abc123",
        "  https://m.youtube.com/watch?v=abc123  ",
    ])
    func acceptsYouTubeURLs(_ string: String) {
        #expect(YouTubeURL.parse(string) != nil)
    }

    @Test(arguments: ["https://vimeo.com/123", "youtube.com/watch?v=abc", "ftp://youtube.com/x", "pas une url", ""])
    func rejectsOtherURLs(_ string: String) {
        #expect(YouTubeURL.parse(string) == nil)
    }

    @Test("Titre lu dans la sortie --print, lignes de progression ignorées")
    func parsesTitle() {
        let stdout = "[download]  10.0% of 3MiB\nVOXLAB_TITLE=Ma chanson (Live)\n[download] 100% of 3MiB\n"
        #expect(YtDlpImporter.title(in: stdout) == "Ma chanson (Live)")
        #expect(YtDlpImporter.title(in: "[download] 100%\n") == nil)
    }

    @Test("Télécharge l'audio, le convertit en source.wav et renvoie le titre")
    func downloadsAndConverts() async throws {
        let dir = FileManager.default.temporaryDirectory.appending(path: "voxlab-yt-\(UUID().uuidString)")
        try FileManager.default.createDirectory(at: dir, withIntermediateDirectories: true)
        defer { try? FileManager.default.removeItem(at: dir) }

        // 1er appel : yt-dlp écrit download.webm ; 2e appel : ffmpeg écrit le fichier de sortie.
        let runner = ScriptedProcessRunner { request, onEvent throws(ProcessRunnerError) in
            if request.arguments.contains("--no-playlist") {
                let template = request.arguments[request.arguments.firstIndex(of: "-o")! + 1]
                FileManager.default.createFile(atPath: template.replacingOccurrences(of: "%(ext)s", with: "webm"), contents: Data("opus".utf8))
                onEvent(.progress(1))
                return ProcessResult(exitCode: 0, stdout: "VOXLAB_TITLE=Ma chanson\n", stderr: "")
            }
            FileManager.default.createFile(atPath: request.arguments.last!, contents: Data("wav".utf8))
            return ProcessResult(exitCode: 0, stdout: "", stderr: "")
        }
        let destination = dir.appending(path: JobArtifact.source)
        let url = try #require(URL(string: "https://youtu.be/abc123"))

        let metadata = try await YtDlpImporter(runner: runner, toolPaths: { paths }).importSource(.youtube(url), to: destination) { _ in }

        #expect(metadata.title == "Ma chanson")
        #expect(try String(contentsOf: destination, encoding: .utf8) == "wav")
        let requests = runner.requests.withLock { $0 }
        #expect(requests.count == 2)
        #expect(requests[0].arguments.last == "https://youtu.be/abc123")
        #expect(requests[1].arguments.contains { $0.hasSuffix("download.webm") })
        // Le dossier de téléchargement temporaire est supprimé.
        #expect(try FileManager.default.contentsOfDirectory(atPath: dir.path(percentEncoded: false)) == ["source.wav"])
    }

    @Test("Échec yt-dlp : message lisible, pas de conversion")
    func downloadFailure() async throws {
        let dir = FileManager.default.temporaryDirectory.appending(path: "voxlab-yt-\(UUID().uuidString)")
        try FileManager.default.createDirectory(at: dir, withIntermediateDirectories: true)
        defer { try? FileManager.default.removeItem(at: dir) }
        let runner = ScriptedProcessRunner { _, _ throws(ProcessRunnerError) in
            ProcessResult(exitCode: 1, stdout: "", stderr: "ERROR: [youtube] abc123: Video unavailable")
        }

        await #expect(throws: YtDlpError.downloadFailed("ERROR: [youtube] abc123: Video unavailable")) {
            _ = try await YtDlpImporter(runner: runner, toolPaths: { paths })
                .importSource(.youtube(URL(string: "https://youtu.be/abc123")!), to: dir.appending(path: JobArtifact.source)) { _ in }
        }
        #expect(runner.requests.withLock { $0.count } == 1)
    }

    @MainActor
    @Test("Le titre découvert à l'import remplace le titre provisoire du job")
    func importUpdatesTitle() async throws {
        let container = try ModelContainer(for: Job.self, StepRun.self, configurations: ModelConfiguration(isStoredInMemoryOnly: true))
        let job = Job(title: "YouTube – https://youtu.be/abc", sourceKind: .youtube, sourceReference: "https://youtu.be/abc", targetLanguage: "fr")
        container.mainContext.insert(job)
        let store = SwiftDataJobStore(context: container.mainContext)
        let storage = JobStorage(rootDirectory: FileManager.default.temporaryDirectory.appending(path: "voxlab-yt-\(UUID().uuidString)"))
        defer { try? FileManager.default.removeItem(at: storage.rootDirectory) }
        let runner = PipelineRunner(steps: [MockStep(.import, .succeed(StepOutput(title: "Ma chanson")))], store: store, storage: storage)

        await runner.start(jobID: job.id)
        await runner.waitUntilIdle(jobID: job.id)

        #expect(job.title == "Ma chanson")
    }
}

/// Vrai téléchargement (réseau). `TEST_RUNNER_VOXLAB_INTEGRATION=1 xcodebuild test …`.
@Suite("Intégration YouTube", .enabled(if: ProcessInfo.processInfo.environment["VOXLAB_INTEGRATION"] == "1"))
struct YouTubeIntegrationTests {
    @Test("« Me at the zoo » (19 s) → source.wav et titre", .timeLimit(.minutes(5)))
    func download() async throws {
        let dir = FileManager.default.temporaryDirectory.appending(path: "voxlab-yt-real-\(UUID().uuidString)")
        try FileManager.default.createDirectory(at: dir, withIntermediateDirectories: true)
        defer { try? FileManager.default.removeItem(at: dir) }
        let destination = dir.appending(path: JobArtifact.source)
        let progress = Mutex<[Double]>([])

        let metadata = try await YtDlpImporter(runner: ProcessRunner(), toolPaths: { .defaults })
            .importSource(.youtube(URL(string: "https://www.youtube.com/watch?v=jNQXAC9IVRw")!), to: destination) { value in
                progress.withLock { $0.append(value) }
            }

        print("[youtube] titre=\(metadata.title ?? "-") progression=\(progress.withLock { $0.count }) points")
        #expect(metadata.title == "Me at the zoo")
        #expect(FileManager.default.fileExists(atPath: destination.path(percentEncoded: false)))
        #expect(progress.withLock { $0 }.last == 1)
    }
}
