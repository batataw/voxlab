import SwiftUI

/// Carte d'un job dans l'historique.
struct JobCard: View {
    let job: Job

    var body: some View {
        Card {
            VStack(alignment: .leading, spacing: 8) {
                HStack(spacing: 12) {
                    JobIcon(job: job)
                    VStack(alignment: .leading, spacing: 2) {
                        Text(job.title)
                            .font(.headline)
                            .lineLimit(1)
                        Text("\(job.createdAt.formatted(.dateTime.day().month().hour().minute())) · \(job.sourceKind == .youtube ? "YouTube" : "Fichier")")
                            .font(.caption)
                            .foregroundStyle(.secondary)
                    }
                    Spacer()
                    StatusPill(status: job.overallStatus, label: job.statusLabel)
                }
                if let running = job.runningStep {
                    ThinProgressBar(value: running.progress, tint: running.step.tint)
                }
            }
        } footer: {
            JobChips(job: job)
        }
        .contentShape(.rect)
    }
}

/// Pastille d'un job : note de musique pour un fichier, lecture rouge pour YouTube.
struct JobIcon: View {
    let job: Job

    var body: some View {
        switch job.sourceKind {
        case .file: RoundIcon(systemImage: "music.note", tint: .orange)
        case .youtube: RoundIcon(systemImage: "play.rectangle.fill", tint: .red)
        }
    }
}

/// Étiquettes d'un job : langues, qualité, durée, lignes, traduction obsolète.
struct JobChips: View {
    let job: Job

    var body: some View {
        HStack(spacing: 6) {
            Chip(text: "\(job.detectedLanguage ?? "auto") → \(job.targetLanguage)", systemImage: "globe")
            Chip(text: job.quality.displayName, systemImage: "bolt.fill")
            // Durée totale seulement pour un job terminé : en cours, elle n'aurait pas de sens.
            if job.overallStatus == .done, let duration = job.totalDuration {
                Chip(text: Duration.seconds(duration).formatted(.units(allowed: [.hours, .minutes, .seconds], width: .narrow, maximumUnitCount: 2)), systemImage: "clock")
            }
            if let lines = job.transcriptLineCount {
                Chip(text: "\(lines) lignes", systemImage: "text.alignleft")
            }
            if job.isTranslationStale {
                Chip(text: "Traduction obsolète", systemImage: "exclamationmark.triangle.fill", tint: .orange)
            }
        }
    }
}
