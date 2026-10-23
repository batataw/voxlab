import Foundation
import Synchronization
import Testing
@testable import VoxLab

@Suite("ProcessRunner")
struct ProcessRunnerTests {
    let runner = ProcessRunner(killGracePeriod: .milliseconds(500))

    @Test("Capture stdout et le code de sortie")
    func capturesStdout() async throws {
        let result = try await runner.run(ProcessRequest(executable: URL(filePath: "/bin/echo"), arguments: ["bonjour", "VoxLab"]))
        #expect(result.exitCode == 0)
        #expect(result.stdout == "bonjour VoxLab\n")
        #expect(result.stderr.isEmpty)
    }

    @Test("Streame chaque ligne de stdout et stderr")
    func streamsLines() async throws {
        let events = Mutex<[ProcessEvent]>([])
        let request = ProcessRequest(
            executable: URL(filePath: "/bin/sh"),
            arguments: ["-c", "echo un; echo deux; echo erreur >&2"]
        )
        _ = try await runner.run(request) { event in events.withLock { $0.append(event) } }

        let received = events.withLock { $0 }
        #expect(received.filter { if case .stdout = $0 { true } else { false } } == [.stdout("un"), .stdout("deux")])
        #expect(received.contains(.stderr("erreur")))
    }

    @Test("Découpe les lignes réécrites avec \\r et émet la progression")
    func parsesCarriageReturnProgress() async throws {
        let events = Mutex<[ProcessEvent]>([])
        let request = ProcessRequest(
            executable: URL(filePath: "/bin/sh"),
            arguments: ["-c", "printf ' 10%%|#   |\\r 55%%|##  |\\r100%%|####|\\n' >&2"],
            progressParser: .demucs
        )
        _ = try await runner.run(request) { event in events.withLock { $0.append(event) } }

        let progress = events.withLock { $0 }.compactMap { event -> Double? in
            if case .progress(let value) = event { value } else { nil }
        }
        #expect(progress == [0.10, 0.55, 1.0])
    }

    @Test("Renvoie un code non nul sans lever, checked() lève")
    func nonZeroExit() async throws {
        let result = try await runner.run(ProcessRequest(executable: URL(filePath: "/bin/sh"), arguments: ["-c", "echo oups >&2; exit 3"]))
        #expect(result.exitCode == 3)
        #expect(throws: ProcessRunnerError.nonZeroExit(code: 3, stderr: "oups\n")) {
            try result.checked()
        }
    }

    @Test("Binaire inexistant")
    func missingExecutable() async {
        await #expect(throws: ProcessRunnerError.executableNotFound("/nope/absent")) {
            try await runner.run(ProcessRequest(executable: URL(filePath: "/nope/absent")))
        }
    }

    @Test("L'annulation de la tâche termine le processus", .timeLimit(.minutes(1)))
    func cancellation() async {
        let clock = ContinuousClock()
        let start = clock.now
        let task = Task {
            try await runner.run(ProcessRequest(executable: URL(filePath: "/bin/sleep"), arguments: ["30"]))
        }
        try? await Task.sleep(for: .milliseconds(300))
        task.cancel()

        let result = await task.result
        #expect(throws: ProcessRunnerError.cancelled) { try result.get() }
        #expect(clock.now - start < .seconds(5))
    }

    @Test("Le timeout termine le processus", .timeLimit(.minutes(1)))
    func timeout() async {
        let clock = ContinuousClock()
        let start = clock.now
        await #expect(throws: ProcessRunnerError.timedOut(.milliseconds(300))) {
            try await runner.run(ProcessRequest(executable: URL(filePath: "/bin/sleep"), arguments: ["30"], timeout: .milliseconds(300)))
        }
        #expect(clock.now - start < .seconds(5))
    }

    @Test("Un processus rapide n'est pas affecté par son timeout")
    func timeoutNotTriggered() async throws {
        let result = try await runner.run(ProcessRequest(executable: URL(filePath: "/bin/echo"), arguments: ["ok"], timeout: .seconds(10)))
        #expect(result.stdout == "ok\n")
    }
}

@Suite("ProgressParser")
struct ProgressParserTests {
    @Test(arguments: [
        (" 45%|████▌     | 52.6/117.0 [00:10<00:12, 5.1seconds/s]", 0.45),
        ("100%|██████████| 117.0/117.0 [00:22<00:00]", 1.0),
    ])
    func demucs(line: String, expected: Double) {
        #expect(ProgressParser.demucs.progress(in: line) == expected)
    }

    @Test func demucsIgnoresOtherLines() {
        #expect(ProgressParser.demucs.progress(in: "Separated tracks will be stored in /tmp") == nil)
    }

    @Test(arguments: [
        ("[download]  42.3% of    3.52MiB at    1.20MiB/s ETA 00:01", 0.423),
        ("[download] 100% of    3.52MiB in 00:00:02", 1.0),
    ])
    func ytDlp(line: String, expected: Double) throws {
        let value = try #require(ProgressParser.ytDlp.progress(in: line))
        #expect(abs(value - expected) < 0.0001)
    }

    @Test func ytDlpIgnoresOtherLines() {
        #expect(ProgressParser.ytDlp.progress(in: "[youtube] abc: Downloading webpage") == nil)
    }
}
