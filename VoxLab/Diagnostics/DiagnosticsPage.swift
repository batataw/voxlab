import SwiftUI

/// État des outils et services externes, une carte par dépendance.
struct DiagnosticsPage: View {
    let viewModel: DiagnosticsViewModel

    var body: some View {
        Page {
            PageHeader(title: "Diagnostics", subtitle: subtitle) {
                if viewModel.isChecking {
                    ProgressView().controlSize(.small)
                }
                RoundIconButton(title: "Revérifier", systemImage: "arrow.clockwise") {
                    Task { await viewModel.refresh() }
                }
                .disabled(viewModel.isChecking)
            }

            if viewModel.reports.isEmpty, viewModel.isChecking {
                Card {
                    ProgressView("Vérification des outils…")
                        .frame(maxWidth: .infinity)
                        .padding(.vertical, 12)
                }
            }

            ForEach(viewModel.reports) { report in
                DependencyCard(report: report)
            }
        }
    }

    private var subtitle: String {
        guard viewModel.hasCheckedOnce else { return "Vérification des outils installés à part." }
        let missing = viewModel.missingRequired.count
        return missing == 0
            ? "Tous les outils obligatoires sont opérationnels."
            : "\(missing) outil\(missing > 1 ? "s" : "") obligatoire\(missing > 1 ? "s" : "") manquant\(missing > 1 ? "s" : "")."
    }
}

private struct DependencyCard: View {
    let report: DependencyReport

    var body: some View {
        Card {
            HStack(alignment: .top, spacing: 12) {
                RoundIcon(systemImage: icon, tint: color)
                VStack(alignment: .leading, spacing: 4) {
                    Text(report.dependency.displayName).font(.headline)
                    detail
                }
                Spacer()
                StatusPill(status: status, label: statusLabel)
            }
        } footer: {
            HStack(spacing: 6) {
                Chip(text: report.location, systemImage: report.dependency.path(in: .defaults) == nil ? "network" : "terminal")
                Chip(text: report.dependency.isRequired ? "Obligatoire" : "Optionnel", systemImage: report.dependency.isRequired ? "lock.fill" : "circle.dashed")
            }
        }
    }

    @ViewBuilder
    private var detail: some View {
        switch report.state {
        case .available(let details):
            Text(details)
                .font(.callout)
                .foregroundStyle(.secondary)
                .lineLimit(1)
        case .missing:
            Text("Installation : `\(report.dependency.installHint)`")
                .font(.callout)
                .textSelection(.enabled)
        case .broken(let message):
            Text(message)
                .font(.callout)
                .foregroundStyle(report.dependency.isRequired ? .red : .orange)
                .lineLimit(4)
                .textSelection(.enabled)
        }
    }

    private var icon: String {
        switch report.dependency {
        case .ffmpeg: "film"
        case .ytDlp: "play.rectangle.fill"
        case .demucs: "waveform.path"
        case .foundationModels: "apple.intelligence"
        case .llmServer: "server.rack"
        }
    }

    private var color: Color {
        switch report.state {
        case .available: .green
        case .missing, .broken: report.dependency.isRequired ? .red : .orange
        }
    }

    private var status: StepStatus {
        switch report.state {
        case .available: .done
        case .missing, .broken: report.dependency.isRequired ? .failed : .cancelled
        }
    }

    private var statusLabel: String {
        switch report.state {
        case .available: "Opérationnel"
        case .missing: "Introuvable"
        case .broken: "Indisponible"
        }
    }
}
