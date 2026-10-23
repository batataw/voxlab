import Foundation
import os

/// Portée d'une exécution du pipeline.
nonisolated enum PipelineScope: Sendable, Equatable {
    /// De la première étape non terminée jusqu'à la fin.
    case resume
    /// Une seule étape, sans toucher aux autres.
    case only(Step)
}

/// Orchestre les étapes d'un job, une à la fois, et gère leur annulation.
actor PipelineRunner {
    private static let logger = Logger(subsystem: "com.voxlab", category: "Pipeline")

    private let steps: [Step: any PipelineStep]
    private let store: any JobStore
    private let storage: JobStorage
    private var tasks: [UUID: Task<Void, Never>] = [:]

    init(
        steps: [any PipelineStep],
        store: any JobStore,
        storage: JobStorage
    ) {
        self.steps = Dictionary(uniqueKeysWithValues: steps.map { ($0.step, $0) })
        self.store = store
        self.storage = storage
    }

    /// Lance le pipeline pour un job. Sans effet si ce job tourne déjà.
    func start(jobID: UUID, scope: PipelineScope = .resume) {
        guard tasks[jobID] == nil else { return }
        tasks[jobID] = Task {
            await execute(jobID: jobID, scope: scope)
            tasks[jobID] = nil
        }
    }

    func cancel(jobID: UUID) {
        tasks[jobID]?.cancel()
    }

    func isRunning(jobID: UUID) -> Bool {
        tasks[jobID] != nil
    }

    /// Attend la fin de l'exécution en cours (utile aux tests).
    func waitUntilIdle(jobID: UUID) async {
        await tasks[jobID]?.value
    }

    private func execute(jobID: UUID, scope: PipelineScope) async {
        guard let initial = await store.snapshot(of: jobID) else { return }
        let sequence: [Step]
        switch scope {
        case .resume:
            guard let first = initial.resumeStep else { return }
            sequence = Step.allCases.filter { $0.order >= first.order }
        case .only(let step):
            sequence = [step]
        }

        for step in sequence {
            guard let implementation = steps[step] else {
                Self.logger.info("Étape \(step.rawValue, privacy: .public) non implémentée : arrêt du pipeline")
                return
            }
            guard !Task.isCancelled else { return }
            // Re-lecture à chaque étape : la précédente a pu renseigner la langue détectée.
            guard let snapshot = await store.snapshot(of: jobID) else { return }
            let succeeded = await run(implementation, for: snapshot)
            guard succeeded else { return }
        }
    }

    /// Exécute une étape et reporte son état dans le store. Renvoie `true` en cas de succès.
    private func run(_ implementation: any PipelineStep, for snapshot: JobSnapshot) async -> Bool {
        let step = implementation.step
        let jobID = snapshot.id
        await store.markRunning(step, of: jobID)

        let directory: URL
        do {
            directory = try storage.prepareDirectory(for: jobID)
        } catch {
            await store.markFailed(step, of: jobID, message: error.localizedDescription)
            return false
        }
        let context = StepContext(
            jobID: jobID,
            directory: directory,
            source: snapshot.source,
            targetLanguage: snapshot.targetLanguage,
            detectedLanguage: snapshot.detectedLanguage,
            quality: snapshot.quality
        )

        // La progression transite par un flux pour être appliquée dans l'ordre, avant le statut final.
        let (progress, continuation) = AsyncStream.makeStream(of: Double.self, bufferingPolicy: .bufferingNewest(1))
        let store = store
        let progressTask = Task { @MainActor in
            for await value in progress {
                store.setProgress(value, for: step, of: jobID)
            }
        }

        let clock = ContinuousClock()
        let start = clock.now
        do {
            let output = try await implementation.run(context) { continuation.yield($0) }
            continuation.finish()
            await progressTask.value
            await store.complete(step, of: jobID, with: output)
            Self.logger.info("Étape \(step.rawValue, privacy: .public) terminée en \(clock.now - start, privacy: .public)")
            return true
        } catch {
            continuation.finish()
            await progressTask.value
            if Task.isCancelled || Self.isCancellation(error) {
                await store.markCancelled(step, of: jobID)
                Self.logger.info("Étape \(step.rawValue, privacy: .public) annulée")
            } else {
                await store.markFailed(step, of: jobID, message: error.localizedDescription)
                Self.logger.error("Étape \(step.rawValue, privacy: .public) en échec : \(error.localizedDescription, privacy: .public)")
            }
            return false
        }
    }

    private static func isCancellation(_ error: any Error) -> Bool {
        error is CancellationError || (error as? ProcessRunnerError) == .cancelled
    }
}
