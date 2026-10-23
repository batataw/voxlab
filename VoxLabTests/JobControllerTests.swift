import Foundation
import SwiftData
import Testing
@testable import VoxLab

@MainActor
@Suite("JobController")
struct JobControllerTests {
    let container: ModelContainer
    let storage: JobStorage
    let controller: JobController

    init() throws {
        container = try ModelContainer(for: Job.self, StepRun.self, configurations: ModelConfiguration(isStoredInMemoryOnly: true))
        storage = JobStorage(rootDirectory: FileManager.default.temporaryDirectory.appending(path: "voxlab-controller-\(UUID().uuidString)"))
        let store = SwiftDataJobStore(context: container.mainContext)
        controller = JobController(
            runner: PipelineRunner(steps: [], store: store, storage: storage),
            storage: storage,
            context: container.mainContext
        )
    }

    private func makeJob() -> Job {
        let job = Job(title: "Test", sourceKind: .file, sourceReference: "/tmp/a.mp3", targetLanguage: "en")
        container.mainContext.insert(job)
        return job
    }

    @Test("Éditer le texte corrigé écrit le fichier et rend la traduction obsolète")
    func editingCorrectedMarksTranslationStale() throws {
        defer { try? FileManager.default.removeItem(at: storage.rootDirectory) }
        let job = makeJob()
        job.correctedTranscript = "avant"
        job.translation = "before"

        controller.updateText("après", kind: .corrected, of: job)

        #expect(job.correctedTranscript == "après")
        #expect(job.isTranslationStale)
        let file = storage.directory(for: job.id).appending(path: JobArtifact.correctedTranscript)
        #expect(try String(contentsOf: file, encoding: .utf8) == "après")
    }

    @Test("Sans traduction, rien n'est marqué obsolète ; la traduction s'écrit dans translation_<lang>.txt")
    func otherEdits() throws {
        defer { try? FileManager.default.removeItem(at: storage.rootDirectory) }
        let job = makeJob()
        job.correctedTranscript = "avant"
        controller.updateText("après", kind: .corrected, of: job)
        #expect(!job.isTranslationStale)

        job.translation = "x"
        controller.updateText("hello", kind: .translated, of: job)
        let file = storage.directory(for: job.id).appending(path: "translation_en.txt")
        #expect(try String(contentsOf: file, encoding: .utf8) == "hello")
    }

    @Test("Changer la langue cible rend la traduction existante obsolète")
    func changingTargetLanguage() {
        let job = makeJob()
        controller.setTargetLanguage(.de, of: job)
        #expect(job.targetLanguage == "de")
        #expect(!job.isTranslationStale)

        job.translation = "Regen"
        controller.setTargetLanguage(.it, of: job)
        #expect(job.isTranslationStale)
    }
}
