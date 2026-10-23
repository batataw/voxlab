import SwiftUI

/// Détail d'un job : en-tête, pipeline, audio et textes, en cartes.
struct JobDetailPage: View {
    let job: Job
    let navigation: AppNavigation

    @Environment(JobController.self) private var controller
    @State private var isConfirmingDeletion = false

    var body: some View {
        Page {
            JobDetailCards(job: job) { isConfirmingDeletion = true }
        }
        .navigationTitle(job.title)
        .confirmationDialog("Supprimer « \(job.title) » et ses fichiers ?", isPresented: $isConfirmingDeletion) {
            Button("Supprimer", role: .destructive) {
                navigation.historyPath.removeAll()
                controller.delete(job)
            }
        } message: {
            Text("Les fichiers audio et les textes du job seront effacés du disque.")
        }
    }
}

/// Cartes du détail, séparées du conteneur défilant (et ainsi rendables hors fenêtre).
struct JobDetailCards: View {
    let job: Job
    let onDelete: () -> Void

    @Environment(JobController.self) private var controller

    private var isRunning: Bool { job.overallStatus == .running }

    var body: some View {
        VStack(alignment: .leading, spacing: Theme.cardSpacing) {
            headerCard
            pipelineCard
            audioCard
            TranscriptTabsView(job: job, isEditable: !isRunning)
                .id(job.id)
        }
    }

    private var headerCard: some View {
        Card {
            HStack(alignment: .top, spacing: 12) {
                JobIcon(job: job)
                VStack(alignment: .leading, spacing: 3) {
                    Text(job.title)
                        .font(.title3.bold())
                        .lineLimit(2)
                    Text(job.sourceReference)
                        .font(.caption.monospaced())
                        .foregroundStyle(.secondary)
                        .lineLimit(1)
                        .truncationMode(.middle)
                        .textSelection(.enabled)
                }
                Spacer()
                if isRunning {
                    RoundIconButton(title: "Annuler", systemImage: "stop.fill", tint: .red) { controller.cancel(job) }
                } else if let step = job.resumeStep {
                    RoundIconButton(title: "Reprendre à « \(step.displayName) »", systemImage: "play.fill", tint: .accentColor) { controller.resume(job) }
                }
                RoundIconButton(title: "Afficher dans le Finder", systemImage: "folder") {
                    NSWorkspace.shared.activateFileViewerSelecting([controller.directory(of: job)])
                }
                RoundIconButton(title: "Supprimer le job", systemImage: "trash", action: onDelete)
                    .disabled(isRunning)
            }
        } footer: {
            TargetLanguageView(job: job, isEditable: !isRunning)
        }
    }

    private var pipelineCard: some View {
        SectionCard(title: "Pipeline") {
            StatusPill(status: job.overallStatus, label: job.statusLabel)
        } content: {
            VStack(spacing: 0) {
                ForEach(job.orderedStepRuns) { run in
                    StepRow(run: run, canRerun: !isRunning) {
                        controller.rerun(run.step, of: job)
                    }
                    if run.step != Step.allCases.last {
                        Divider().padding(.leading, 34)
                    }
                }
            }
        }
    }

    @ViewBuilder
    private var audioCard: some View {
        let source = controller.existingArtifact(JobArtifact.source, of: job)
        let vocals = controller.existingArtifact(JobArtifact.vocals, of: job)
        if source != nil || vocals != nil {
            SectionCard(title: "Audio") {
                VStack(spacing: 8) {
                    if let source, job.stepRun(for: .import)?.status == .done {
                        AudioPlayerView(title: "Source", url: source)
                    }
                    if let vocals, job.stepRun(for: .separate)?.status == .done {
                        AudioPlayerView(title: "Voix", url: vocals)
                    }
                }
            }
        }
    }
}

/// Ligne d'étape : pastille colorée, nom, durée, statut, relance.
private struct StepRow: View {
    let run: StepRun
    let canRerun: Bool
    let onRerun: () -> Void

    var body: some View {
        VStack(alignment: .leading, spacing: 6) {
            HStack(spacing: 12) {
                IconTile(systemImage: run.step.systemImage, color: run.step.tint)
                Text(run.step.displayName)
                    .font(.body.weight(.medium))
                Spacer()
                if let duration = run.duration {
                    Text(Duration.seconds(duration), format: .units(allowed: [.hours, .minutes, .seconds], width: .narrow))
                        .font(.caption.monospacedDigit())
                        .foregroundStyle(.secondary)
                }
                StatusPill(status: run.status, label: run.status == .running ? "\(Int((run.progress * 100).rounded())) %" : nil)
                Button(action: onRerun) {
                    Image(systemName: "arrow.clockwise")
                        .font(.system(size: 12, weight: .semibold))
                        .foregroundStyle(.secondary)
                        .frame(width: 24, height: 24)
                        .contentShape(.rect)
                }
                .buttonStyle(.plain)
                .disabled(!canRerun)
                .opacity(canRerun ? 1 : 0.4)
                .help("Relancer cette étape")
                .accessibilityLabel("Relancer cette étape")
            }
            if run.status == .running {
                ThinProgressBar(value: run.progress, tint: run.step.tint)
                    .padding(.leading, 34)
            }
            if let message = run.errorMessage {
                Text(message)
                    .font(.caption)
                    .foregroundStyle(.red)
                    .textSelection(.enabled)
                    .padding(.leading, 34)
            }
        }
        .padding(.vertical, 8)
    }
}
