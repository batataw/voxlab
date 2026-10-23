import Foundation
import SwiftData
import Testing
@testable import VoxLab

@MainActor
@Suite("Résumé et recherche des jobs")
struct JobSummaryTests {
    let container: ModelContainer

    init() throws {
        container = try ModelContainer(for: Job.self, StepRun.self, configurations: ModelConfiguration(isStoredInMemoryOnly: true))
    }

    private func makeJob(title: String = "Chanson de test") -> Job {
        let job = Job(title: title, sourceKind: .file, sourceReference: "/tmp/a.mp3", targetLanguage: "fr")
        container.mainContext.insert(job)
        return job
    }

    @Test("Recherche dans le titre et les trois textes, sans tenir compte de la casse ni des accents")
    func search() {
        let job = makeJob(title: "Été indien (démo)")
        job.rawTranscript = "une ligne brute"
        job.correctedTranscript = "Une ligne corrigée"
        job.translation = "A translated line"

        #expect(job.matches(""))
        #expect(job.matches("ete"))
        #expect(job.matches("BRUTE"))
        #expect(job.matches("corrigee"))
        #expect(job.matches("translated"))
        #expect(!job.matches("absent"))
    }

    @Test("Libellé de statut : étape en cours et pourcentage, ou étape en échec")
    func statusLabel() {
        let job = makeJob()
        #expect(job.statusLabel == "En attente")

        job.stepRun(for: .import)?.markDone()
        job.stepRun(for: .separate)?.markRunning()
        job.stepRun(for: .separate)?.progress = 0.426
        #expect(job.statusLabel == "Isolation voix 43 %")

        job.stepRun(for: .separate)?.markFailed("boom")
        #expect(job.statusLabel == "Échec : isolation voix")
    }

    @Test("Durée totale et nombre de lignes")
    func totals() {
        let job = makeJob()
        #expect(job.totalDuration == nil)
        #expect(job.transcriptLineCount == nil)

        let start = Date(timeIntervalSince1970: 0)
        job.stepRun(for: .import)?.startedAt = start
        job.stepRun(for: .import)?.finishedAt = start.addingTimeInterval(2)
        job.stepRun(for: .separate)?.startedAt = start
        job.stepRun(for: .separate)?.finishedAt = start.addingTimeInterval(90)
        job.rawTranscript = "un\n\ndeux\ntrois"

        #expect(job.totalDuration == 92)
        #expect(job.transcriptLineCount == 3)
    }

    @Test("La qualité est figée à la création du job, Max par défaut")
    func quality() {
        #expect(makeJob().quality == .max)
        let fast = Job(title: "x", sourceKind: .file, sourceReference: "/tmp/b.mp3", targetLanguage: "fr", quality: .fast)
        #expect(fast.quality == .fast)
    }
}
