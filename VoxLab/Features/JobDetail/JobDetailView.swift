import SwiftUI

struct JobDetailView: View {
    let job: Job
    @Environment(JobController.self) private var controller

    private var isRunning: Bool { job.overallStatus == .running }

    var body: some View {
        ScrollView {
            VStack(alignment: .leading, spacing: 20) {
                header

                VStack(alignment: .leading, spacing: 0) {
                    ForEach(job.orderedStepRuns) { run in
                        StepTimelineRow(run: run, canRerun: !isRunning) {
                            controller.rerun(run.step, of: job)
                        }
                        if run.step != Step.allCases.last {
                            Divider()
                        }
                    }
                }
                .padding(12)
                .background(.background.secondary, in: .rect(cornerRadius: 10))

                audioSection
            }
            .padding(24)
            .frame(maxWidth: .infinity, alignment: .leading)
        }
        .navigationTitle(job.title)
        .toolbar {
            ToolbarItemGroup {
                if isRunning {
                    Button("Annuler", systemImage: "stop.fill") { controller.cancel(job) }
                } else if job.resumeStep != nil {
                    Button("Reprendre", systemImage: "play.fill") { controller.resume(job) }
                        .help("Reprendre à l'étape « \(job.resumeStep?.displayName ?? "") »")
                }
                Button("Afficher dans le Finder", systemImage: "folder") {
                    NSWorkspace.shared.activateFileViewerSelecting([controller.directory(of: job)])
                }
            }
        }
    }

    private var header: some View {
        VStack(alignment: .leading, spacing: 4) {
            Text(job.title)
                .font(.title2.bold())
            Text(job.sourceReference)
                .font(.caption.monospaced())
                .foregroundStyle(.secondary)
                .textSelection(.enabled)
        }
    }

    @ViewBuilder
    private var audioSection: some View {
        let source = controller.existingArtifact(JobArtifact.source, of: job)
        let vocals = controller.existingArtifact(JobArtifact.vocals, of: job)
        if source != nil || vocals != nil {
            VStack(alignment: .leading, spacing: 8) {
                Text("Audio").font(.headline)
                if let source, !isRunning || job.stepRun(for: .import)?.status == .done {
                    AudioPlayerView(title: "Source", url: source)
                }
                if let vocals, job.stepRun(for: .separate)?.status == .done {
                    AudioPlayerView(title: "Voix", url: vocals)
                }
            }
            .padding(12)
            .background(.background.secondary, in: .rect(cornerRadius: 10))
        }
    }
}

private struct StepTimelineRow: View {
    let run: StepRun
    let canRerun: Bool
    let onRerun: () -> Void

    var body: some View {
        HStack(alignment: .top, spacing: 12) {
            Image(systemName: run.step.systemImage)
                .frame(width: 20)
                .foregroundStyle(.secondary)
            VStack(alignment: .leading, spacing: 4) {
                HStack {
                    Text(run.step.displayName).bold()
                    Spacer()
                    if let duration = run.duration {
                        Text(Duration.seconds(duration), format: .units(allowed: [.hours, .minutes, .seconds], width: .narrow))
                            .font(.caption.monospacedDigit())
                            .foregroundStyle(.secondary)
                    }
                    StepStatusBadge(status: run.status)
                    Button("Relancer cette étape", systemImage: "arrow.clockwise", action: onRerun)
                        .labelStyle(.iconOnly)
                        .buttonStyle(.borderless)
                        .disabled(!canRerun)
                        .help("Relancer cette étape")
                }
                if run.status == .running {
                    ProgressView(value: run.progress)
                }
                if let message = run.errorMessage {
                    Text(message)
                        .font(.caption)
                        .foregroundStyle(.red)
                        .textSelection(.enabled)
                }
            }
        }
        .padding(.vertical, 8)
    }
}
