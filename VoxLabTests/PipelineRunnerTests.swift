import Foundation
import Synchronization
import SwiftData
import Testing
@testable import VoxLab

/// Étape factice : enregistre ses appels, peut échouer ou attendre une annulation.
final class MockStep: PipelineStep {
    enum Behavior: Sendable {
        case succeed(StepOutput)
        case fail
        case waitForCancellation
    }

    let step: Step
    private let behavior: Mutex<Behavior>
    private let log: CallLog?

    init(_ step: Step, _ behavior: Behavior = .succeed(StepOutput()), log: CallLog? = nil) {
        self.step = step
        self.behavior = Mutex(behavior)
        self.log = log
    }

    func setBehavior(_ behavior: Behavior) {
        self.behavior.withLock { $0 = behavior }
    }

    func run(_ context: StepContext, onProgress: @escaping @Sendable (Double) -> Void) async throws -> StepOutput {
        log?.calls.withLock { $0.append(step) }
        onProgress(0.5)
        switch behavior.withLock({ $0 }) {
        case .succeed(let output):
            return output
        case .fail:
            throw MockError.boom
        case .waitForCancellation:
            try await Task.sleep(for: .seconds(30))
            return StepOutput()
        }
    }
}

enum MockError: LocalizedError {
    case boom
    var errorDescription: String? { "Échec simulé" }
}

/// Mutex partagé entre les étapes factices pour observer l'ordre d'exécution.
final class CallLog: Sendable {
    let calls = Mutex<[Step]>([])
    var steps: [Step] { calls.withLock { $0 } }
}

@MainActor
@Suite("PipelineRunner")
struct PipelineRunnerTests {
    let container: ModelContainer
    let store: SwiftDataJobStore
    let storage: JobStorage
    let job: Job

    init() throws {
        container = try ModelContainer(for: Job.self, StepRun.self, configurations: ModelConfiguration(isStoredInMemoryOnly: true))
        store = SwiftDataJobStore(context: container.mainContext)
        storage = JobStorage(rootDirectory: FileManager.default.temporaryDirectory.appending(path: "voxlab-pipeline-\(UUID().uuidString)"))
        job = Job(title: "Test", sourceKind: .file, sourceReference: "/tmp/a.wav", targetLanguage: "fr")
        container.mainContext.insert(job)
    }

    private func makeRunner(_ steps: [any PipelineStep]) -> PipelineRunner {
        PipelineRunner(steps: steps, store: store, storage: storage, quality: { .fast })
    }

    private func run(_ runner: PipelineRunner, scope: PipelineScope = .resume) async {
        await runner.start(jobID: job.id, scope: scope)
        await runner.waitUntilIdle(jobID: job.id)
    }

    private func status(_ step: Step) -> StepStatus? {
        job.stepRun(for: step)?.status
    }

    @Test("Exécute toutes les étapes dans l'ordre et enregistre les textes")
    func runsInOrder() async {
        let log = CallLog()
        let runner = makeRunner([
            MockStep(.translate, .succeed(StepOutput(text: "traduit")), log: log),
            MockStep(.import, log: log),
            MockStep(.correct, .succeed(StepOutput(text: "corrigé")), log: log),
            MockStep(.separate, log: log),
            MockStep(.transcribe, .succeed(StepOutput(text: "brut", detectedLanguage: "en")), log: log),
        ])
        await run(runner)

        #expect(log.steps == Step.allCases)
        #expect(job.overallStatus == .done)
        #expect(job.rawTranscript == "brut")
        #expect(job.correctedTranscript == "corrigé")
        #expect(job.translation == "traduit")
        #expect(job.detectedLanguage == "en")
        #expect(job.stepRuns.allSatisfy { $0.progress == 1 })
    }

    @Test("S'arrête avant une étape non implémentée")
    func stopsAtMissingStep() async {
        let runner = makeRunner([MockStep(.import), MockStep(.separate)])
        await run(runner)

        #expect(status(.import) == .done)
        #expect(status(.separate) == .done)
        #expect(status(.transcribe) == .pending)
        #expect(job.resumeStep == .transcribe)
    }

    @Test("Un échec arrête le pipeline ; la reprise repart de l'étape échouée")
    func resumeAfterFailure() async {
        let log = CallLog()
        let separate = MockStep(.separate, .fail, log: log)
        let runner = makeRunner([MockStep(.import, log: log), separate, MockStep(.transcribe, log: log)])

        await run(runner)
        #expect(status(.import) == .done)
        #expect(status(.separate) == .failed)
        #expect(job.stepRun(for: .separate)?.errorMessage == "Échec simulé")
        #expect(status(.transcribe) == .pending)

        separate.setBehavior(.succeed(StepOutput()))
        log.calls.withLock { $0.removeAll() }
        await run(runner)
        #expect(log.steps == [.separate, .transcribe])
        #expect(status(.separate) == .done)
        #expect(job.stepRun(for: .separate)?.errorMessage == nil)
    }

    @Test("Relancer une seule étape ne touche pas aux autres")
    func rerunSingleStep() async {
        let log = CallLog()
        let runner = makeRunner(Step.allCases.map { MockStep($0, log: log) })
        await run(runner)
        log.calls.withLock { $0.removeAll() }

        await run(runner, scope: .only(.correct))
        #expect(log.steps == [.correct])
        #expect(job.overallStatus == .done)
    }

    @Test("L'annulation marque l'étape en cours comme annulée", .timeLimit(.minutes(1)))
    func cancellation() async throws {
        let runner = makeRunner([MockStep(.import), MockStep(.separate, .waitForCancellation), MockStep(.transcribe)])
        await runner.start(jobID: job.id)
        // Attend que l'étape Separate soit en cours.
        while status(.separate) != .running {
            try await Task.sleep(for: .milliseconds(10))
        }
        await runner.cancel(jobID: job.id)
        await runner.waitUntilIdle(jobID: job.id)

        #expect(status(.import) == .done)
        #expect(status(.separate) == .cancelled)
        #expect(status(.transcribe) == .pending)
        #expect(await runner.isRunning(jobID: job.id) == false)
        #expect(job.resumeStep == .separate)
    }

    @Test("Les étapes « en cours » au lancement sont marquées interrompues")
    func recoverInterrupted() throws {
        job.stepRun(for: .separate)?.markRunning()
        try container.mainContext.save()
        store.recoverInterruptedRuns()
        #expect(status(.separate) == .failed)
        #expect(job.resumeStep == .import)
    }
}
