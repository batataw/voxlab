import Foundation
import os
import SwiftData

/// Vue figée d'un job, transmissible hors du MainActor.
nonisolated struct JobSnapshot: Sendable, Equatable {
    var id: UUID
    var source: JobSource
    var targetLanguage: String
    var detectedLanguage: String?
    var statuses: [Step: StepStatus]

    /// Première étape non terminée, dans l'ordre du pipeline.
    var resumeStep: Step? {
        Step.allCases.first { statuses[$0] != .done }
    }
}

/// Accès en écriture à l'état des jobs, utilisé par le `PipelineRunner`.
@MainActor
protocol JobStore: AnyObject, Sendable {
    func snapshot(of jobID: UUID) -> JobSnapshot?
    func markRunning(_ step: Step, of jobID: UUID)
    func setProgress(_ progress: Double, for step: Step, of jobID: UUID)
    func complete(_ step: Step, of jobID: UUID, with output: StepOutput)
    func markFailed(_ step: Step, of jobID: UUID, message: String)
    func markCancelled(_ step: Step, of jobID: UUID)
}

@MainActor
final class SwiftDataJobStore: JobStore {
    private static let logger = Logger(subsystem: "com.voxlab", category: "JobStore")
    private let context: ModelContext

    init(context: ModelContext) {
        self.context = context
    }

    func snapshot(of jobID: UUID) -> JobSnapshot? {
        guard let job = job(jobID) else { return nil }
        return JobSnapshot(
            id: job.id,
            source: job.source,
            targetLanguage: job.targetLanguage,
            detectedLanguage: job.detectedLanguage,
            statuses: Dictionary(uniqueKeysWithValues: job.stepRuns.map { ($0.step, $0.status) })
        )
    }

    func markRunning(_ step: Step, of jobID: UUID) {
        update(step, of: jobID) { $0.markRunning() }
    }

    func setProgress(_ progress: Double, for step: Step, of jobID: UUID) {
        guard let run = job(jobID)?.stepRun(for: step), run.status == .running else { return }
        // Évite d'écrire en base pour chaque ligne de tqdm.
        guard abs(progress - run.progress) >= 0.005 || progress == 1 else { return }
        run.progress = progress
    }

    func complete(_ step: Step, of jobID: UUID, with output: StepOutput) {
        guard let job = job(jobID) else { return }
        if let language = output.detectedLanguage {
            job.detectedLanguage = language
        }
        if let text = output.text {
            switch step {
            case .transcribe: job.rawTranscript = text
            case .correct:
                job.correctedTranscript = text
                if job.translation != nil { job.isTranslationStale = true }
            case .translate:
                job.translation = text
                job.isTranslationStale = false
            case .import, .separate: break
            }
        }
        update(step, of: jobID) { $0.markDone() }
    }

    func markFailed(_ step: Step, of jobID: UUID, message: String) {
        update(step, of: jobID) { $0.markFailed(message) }
    }

    func markCancelled(_ step: Step, of jobID: UUID) {
        update(step, of: jobID) { $0.markCancelled() }
    }

    /// Au lancement : une étape restée « en cours » a été interrompue par la fermeture de l'app.
    func recoverInterruptedRuns() {
        let running = StepStatus.running.rawValue
        let descriptor = FetchDescriptor<StepRun>(predicate: #Predicate { $0.statusRaw == running })
        guard let runs = try? context.fetch(descriptor), !runs.isEmpty else { return }
        runs.forEach { $0.markFailed("Interrompu par la fermeture de l'application.") }
        save()
    }

    private func job(_ id: UUID) -> Job? {
        var descriptor = FetchDescriptor<Job>(predicate: #Predicate { $0.id == id })
        descriptor.fetchLimit = 1
        return try? context.fetch(descriptor).first
    }

    private func update(_ step: Step, of jobID: UUID, _ mutation: (StepRun) -> Void) {
        guard let run = job(jobID)?.stepRun(for: step) else {
            Self.logger.error("Étape \(step.rawValue, privacy: .public) introuvable pour le job \(jobID, privacy: .public)")
            return
        }
        mutation(run)
        save()
    }

    private func save() {
        do {
            try context.save()
        } catch {
            Self.logger.error("Sauvegarde SwiftData impossible : \(error.localizedDescription, privacy: .public)")
        }
    }
}
