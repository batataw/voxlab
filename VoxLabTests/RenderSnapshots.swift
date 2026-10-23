import AppKit
import SwiftData
import SwiftUI
import Testing
@testable import VoxLab

/// Rendus PNG des composants pour vérification visuelle (données inventées).
/// `TEST_RUNNER_VOXLAB_RENDER=<dossier> xcodebuild test -only-testing:VoxLabTests/RenderSnapshots`.
@MainActor
@Suite("Rendus", .enabled(if: ProcessInfo.processInfo.environment["VOXLAB_RENDER"] != nil))
struct RenderSnapshots {
    let output = URL(filePath: ProcessInfo.processInfo.environment["VOXLAB_RENDER"] ?? "/tmp")
    let container: ModelContainer

    init() throws {
        container = try ModelContainer(for: Job.self, StepRun.self, configurations: ModelConfiguration(isStoredInMemoryOnly: true))
    }

    private func sampleJobs() -> [Job] {
        let done = Job(title: "Pluie sur la ville (démo)", sourceKind: .youtube, sourceReference: "https://youtu.be/demo", targetLanguage: "fr", quality: .max)
        done.detectedLanguage = "en"
        done.rawTranscript = (1...28).map { "ligne de démonstration \($0)" }.joined(separator: "\n")
        done.translation = "texte"
        done.isTranslationStale = true
        for (index, run) in done.orderedStepRuns.enumerated() {
            run.startedAt = Date(timeIntervalSinceNow: -400)
            run.finishedAt = run.startedAt!.addingTimeInterval(Double([1, 94, 139, 39, 2][index]))
            run.status = .done
        }

        let running = Job(title: "Chanson de test en cours", sourceKind: .file, sourceReference: "/Users/demo/Music/test.mp3", targetLanguage: "fr", quality: .fast)
        running.detectedLanguage = "es"
        running.stepRun(for: .import)?.markDone()
        running.stepRun(for: .separate)?.markDone()
        running.stepRun(for: .transcribe)?.markRunning()
        running.stepRun(for: .transcribe)?.progress = 0.42

        let failed = Job(title: "Morceau en échec", sourceKind: .file, sourceReference: "/Users/demo/Music/echec.flac", targetLanguage: "de")
        failed.stepRun(for: .import)?.markDone()
        failed.stepRun(for: .separate)?.markRunning()
        failed.stepRun(for: .separate)?.markFailed("Demucs a échoué.\nRuntimeError: MPS backend out of memory")
        [done, running, failed].forEach(container.mainContext.insert)
        return [done, running, failed]
    }

    private func render<V: View>(_ view: V, name: String, width: CGFloat = 760, scheme: ColorScheme = .light) throws {
        let content = view
            .padding(24)
            .frame(width: width)
            .background(Theme.pageBackground)
            .environment(\.colorScheme, scheme)
        let renderer = ImageRenderer(content: content)
        renderer.scale = 2
        let image = try #require(renderer.nsImage)
        let tiff = try #require(image.tiffRepresentation)
        let png = try #require(NSBitmapImageRep(data: tiff)?.representation(using: .png, properties: [:]))
        try png.write(to: output.appending(path: "\(name).png"))
    }

    @Test func components() throws {
        let jobs = sampleJobs()
        try render(VStack(alignment: .leading, spacing: 12) {
            PageHeader(title: "Historique", subtitle: "3 jobs") {
                RoundIconButton(title: "Nouveau", systemImage: "plus") {}
                RoundIconButton(title: "Réglages", systemImage: "gearshape.fill") {}
            }
            ForEach(jobs) { JobCard(job: $0) }
        }, name: "historique")

        try render(VStack(alignment: .leading, spacing: 4) {
            ForEach(AppSection.main + [.settings]) { section in
                HStack(spacing: 10) {
                    IconTile(systemImage: section.systemImage, color: section.color)
                    Text(section.title).font(.body.weight(.medium))
                    Spacer()
                }
                .padding(6)
            }
        }, name: "barre-laterale", width: 240)

        try render(VStack(alignment: .leading, spacing: 12) {
            ForEach(jobs) { JobCard(job: $0) }
        }, name: "historique-sombre", scheme: .dark)

        let controller = JobController(
            runner: PipelineRunner(steps: [], store: SwiftDataJobStore(context: container.mainContext), storage: JobStorage()),
            storage: JobStorage(),
            context: container.mainContext
        )
        try render(JobDetailCards(job: jobs[1]) {}.environment(controller), name: "detail", width: 820)
        try render(JobDetailCards(job: jobs[2]) {}.environment(controller), name: "detail-echec", width: 820)
    }
}
