import Foundation
import os
import Synchronization

/// Description d'un appel à un binaire externe.
nonisolated struct ProcessRequest: Sendable {
    var executable: URL
    var arguments: [String] = []
    /// Variables ajoutées à l'environnement hérité.
    var environment: [String: String] = [:]
    var workingDirectory: URL?
    var timeout: Duration?
    var progressParser: ProgressParser?
}

nonisolated struct ProcessResult: Sendable, Equatable {
    var exitCode: Int32
    var stdout: String
    var stderr: String

    var succeeded: Bool { exitCode == 0 }

    /// Renvoie le résultat si le code de sortie vaut 0, lève `nonZeroExit` sinon.
    func checked() throws(ProcessRunnerError) -> ProcessResult {
        guard succeeded else { throw .nonZeroExit(code: exitCode, stderr: stderr) }
        return self
    }
}

/// Événements émis pendant l'exécution, ligne par ligne.
nonisolated enum ProcessEvent: Sendable, Equatable {
    case stdout(String)
    case stderr(String)
    /// Progression entre 0 et 1, issue du `ProgressParser` de la requête.
    case progress(Double)
}

nonisolated enum ProcessRunnerError: LocalizedError, Equatable {
    case executableNotFound(String)
    case launchFailed(String)
    case nonZeroExit(code: Int32, stderr: String)
    case timedOut(Duration)
    case cancelled

    var errorDescription: String? {
        switch self {
        case .executableNotFound(let path):
            "Binaire introuvable ou non exécutable : \(path)"
        case .launchFailed(let reason):
            "Impossible de lancer le processus : \(reason)"
        case .nonZeroExit(let code, let stderr):
            "Le processus s'est terminé avec le code \(code).\(Self.tail(of: stderr))"
        case .timedOut(let timeout):
            "Délai dépassé (\(timeout.formatted(.units(allowed: [.minutes, .seconds]))))."
        case .cancelled:
            "Exécution annulée."
        }
    }

    /// Dernières lignes de stderr, pour un message lisible dans la timeline.
    private static func tail(of stderr: String) -> String {
        let lines = stderr.split(whereSeparator: \.isNewline).suffix(5)
        return lines.isEmpty ? "" : "\n" + lines.joined(separator: "\n")
    }
}

protocol ProcessRunning: Sendable {
    func run(
        _ request: ProcessRequest,
        onEvent: @escaping @Sendable (ProcessEvent) -> Void
    ) async throws(ProcessRunnerError) -> ProcessResult
}

extension ProcessRunning {
    nonisolated func run(_ request: ProcessRequest) async throws(ProcessRunnerError) -> ProcessResult {
        try await run(request, onEvent: { _ in })
    }
}

/// Unique point d'appel à `Process` dans l'app : streaming de stdout/stderr,
/// annulation coopérative (`terminate`), timeout et parsing de progression.
nonisolated struct ProcessRunner: ProcessRunning {
    private static let logger = Logger(subsystem: "com.voxlab", category: "ProcessRunner")

    /// Délai laissé au processus après SIGTERM avant SIGKILL.
    var killGracePeriod: Duration = .seconds(3)

    @concurrent
    func run(
        _ request: ProcessRequest,
        onEvent: @escaping @Sendable (ProcessEvent) -> Void
    ) async throws(ProcessRunnerError) -> ProcessResult {
        let path = request.executable.path(percentEncoded: false)
        guard FileManager.default.isExecutableFile(atPath: path) else {
            throw .executableNotFound(path)
        }
        guard !Task.isCancelled else { throw .cancelled }

        let process = Process()
        process.executableURL = request.executable
        process.arguments = request.arguments
        if let workingDirectory = request.workingDirectory {
            process.currentDirectoryURL = workingDirectory
        }
        if !request.environment.isEmpty {
            process.environment = ProcessInfo.processInfo.environment
                .merging(request.environment) { _, new in new }
        }

        let stdoutPipe = Pipe()
        let stderrPipe = Pipe()
        process.standardOutput = stdoutPipe
        process.standardError = stderrPipe
        process.standardInput = FileHandle.nullDevice

        let (exitStream, exitContinuation) = AsyncStream.makeStream(of: Int32.self)
        process.terminationHandler = { process in
            exitContinuation.yield(process.terminationStatus)
            exitContinuation.finish()
        }

        do {
            try process.run()
        } catch {
            throw .launchFailed(error.localizedDescription)
        }
        // Ferme nos copies des extrémités d'écriture pour recevoir EOF à la fin du processus.
        try? stdoutPipe.fileHandleForWriting.close()
        try? stderrPipe.fileHandleForWriting.close()

        Self.logger.debug("Lancé : \(path, privacy: .public) \(request.arguments.joined(separator: " "), privacy: .public)")

        let stopReason = Mutex<ProcessRunnerError?>(nil)
        let terminate: @Sendable (ProcessRunnerError) -> Void = { reason in
            // Un processus déjà terminé normalement ne doit pas être requalifié.
            guard process.isRunning else { return }
            let isFirst = stopReason.withLock { current in
                guard current == nil else { return false }
                current = reason
                return true
            }
            guard isFirst else { return }
            process.terminate()
            // Filet de sécurité si le processus ignore SIGTERM.
            let pid = process.processIdentifier
            Task.detached { [killGracePeriod] in
                try? await Task.sleep(for: killGracePeriod)
                if process.isRunning { kill(pid, SIGKILL) }
            }
        }

        let watchdog = request.timeout.map { timeout in
            Task.detached {
                try await Task.sleep(for: timeout)
                terminate(.timedOut(timeout))
            }
        }
        defer { watchdog?.cancel() }

        let parser = request.progressParser
        let (stdout, stderr, exitCode) = await withTaskCancellationHandler {
            async let stdout = Self.collectLines(from: stdoutPipe.fileHandleForReading) { line in
                onEvent(.stdout(line))
                if let value = parser?.progress(in: line) { onEvent(.progress(value)) }
            }
            async let stderr = Self.collectLines(from: stderrPipe.fileHandleForReading) { line in
                onEvent(.stderr(line))
                if let value = parser?.progress(in: line) { onEvent(.progress(value)) }
            }
            var exitCode: Int32 = -1
            for await code in exitStream { exitCode = code }
            return await (stdout, stderr, exitCode)
        } onCancel: {
            terminate(.cancelled)
        }

        if let reason = stopReason.withLock({ $0 }) {
            Self.logger.info("Arrêté (\(String(describing: reason), privacy: .public)) : \(path, privacy: .public)")
            throw reason
        }
        Self.logger.debug("Terminé avec le code \(exitCode) : \(path, privacy: .public)")
        return ProcessResult(exitCode: exitCode, stdout: stdout, stderr: stderr)
    }

    /// Lit un flux jusqu'à EOF. Les lignes sont découpées sur `\n` et `\r`
    /// (les barres de progression type tqdm réécrivent la ligne avec `\r`).
    private static func collectLines(
        from handle: FileHandle,
        onLine: @Sendable (String) -> Void
    ) async -> String {
        var collected = ""
        do {
            for try await line in handle.bytes.lines {
                collected += line + "\n"
                onLine(line)
            }
        } catch {
            logger.error("Lecture du flux interrompue : \(error.localizedDescription, privacy: .public)")
        }
        return collected
    }
}
