import Foundation
import SwiftData

/// État d'exécution d'une étape pour un job donné.
@Model
final class StepRun {
    // Les enums sont stockés en brut pour rester utilisables dans les prédicats SwiftData.
    var stepRaw: String
    var statusRaw: String
    var progress: Double
    var startedAt: Date?
    var finishedAt: Date?
    var errorMessage: String?
    var job: Job?

    init(step: Step) {
        self.stepRaw = step.rawValue
        self.statusRaw = StepStatus.pending.rawValue
        self.progress = 0
    }

    var step: Step {
        Step(rawValue: stepRaw) ?? .import
    }

    var status: StepStatus {
        get { StepStatus(rawValue: statusRaw) ?? .pending }
        set { statusRaw = newValue.rawValue }
    }

    var duration: TimeInterval? {
        guard let startedAt else { return nil }
        return (finishedAt ?? .now).timeIntervalSince(startedAt)
    }

    func markRunning() {
        status = .running
        progress = 0
        startedAt = .now
        finishedAt = nil
        errorMessage = nil
    }

    func markDone() {
        status = .done
        progress = 1
        finishedAt = .now
    }

    func markFailed(_ message: String) {
        status = .failed
        finishedAt = .now
        errorMessage = message
    }

    func markCancelled() {
        status = .cancelled
        finishedAt = .now
    }

    func reset() {
        status = .pending
        progress = 0
        startedAt = nil
        finishedAt = nil
        errorMessage = nil
    }
}
