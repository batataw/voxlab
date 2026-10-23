import Foundation
import SwiftData
import Testing
@testable import VoxLab

@MainActor
@Suite("Job")
struct JobModelTests {
    let container: ModelContainer

    init() throws {
        container = try ModelContainer(
            for: Job.self, StepRun.self,
            configurations: ModelConfiguration(isStoredInMemoryOnly: true)
        )
    }

    private func makeJob() -> Job {
        let job = Job(title: "Test", sourceKind: .file, sourceReference: "/tmp/a.mp3", targetLanguage: "fr")
        container.mainContext.insert(job)
        return job
    }

    @Test("Un nouveau job a les 5 étapes en attente, dans l'ordre")
    func initialSteps() {
        let job = makeJob()
        #expect(job.orderedStepRuns.map(\.step) == Step.allCases)
        #expect(job.stepRuns.allSatisfy { $0.status == .pending })
        #expect(job.overallStatus == .pending)
        #expect(job.resumeStep == .import)
    }

    @Test("La reprise se fait à la première étape non terminée")
    func resumeAfterFailure() throws {
        let job = makeJob()
        job.stepRun(for: .import)?.markDone()
        job.stepRun(for: .separate)?.markRunning()
        job.stepRun(for: .separate)?.markFailed("Demucs a planté")

        #expect(job.overallStatus == .failed)
        #expect(job.resumeStep == .separate)
        #expect(job.stepRun(for: .separate)?.errorMessage == "Demucs a planté")
    }

    @Test("Statut global terminé quand toutes les étapes le sont")
    func allDone() {
        let job = makeJob()
        job.stepRuns.forEach { $0.markDone() }
        #expect(job.overallStatus == .done)
        #expect(job.resumeStep == nil)
    }

    @Test("Supprimer un job supprime ses étapes")
    func cascadeDelete() throws {
        let job = makeJob()
        try container.mainContext.save()
        container.mainContext.delete(job)
        try container.mainContext.save()
        #expect(try container.mainContext.fetchCount(FetchDescriptor<StepRun>()) == 0)
    }
}

@Suite("JobStorage")
struct JobStorageTests {
    @Test("Crée puis supprime le dossier d'un job")
    func directoryLifecycle() throws {
        let root = FileManager.default.temporaryDirectory.appending(path: "voxlab-tests-\(UUID().uuidString)")
        defer { try? FileManager.default.removeItem(at: root) }
        let storage = JobStorage(rootDirectory: root)
        let id = UUID()

        let dir = try storage.prepareDirectory(for: id)
        #expect(dir.lastPathComponent == id.uuidString)
        #expect(FileManager.default.fileExists(atPath: dir.path(percentEncoded: false)))

        try storage.removeDirectory(for: id)
        #expect(!FileManager.default.fileExists(atPath: dir.path(percentEncoded: false)))
    }
}
