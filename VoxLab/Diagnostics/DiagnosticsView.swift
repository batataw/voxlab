import SwiftUI

struct DiagnosticsView: View {
    let viewModel: DiagnosticsViewModel
    @Environment(\.dismiss) private var dismiss

    var body: some View {
        VStack(alignment: .leading, spacing: 16) {
            Text("Diagnostic des dépendances")
                .font(.title2.bold())
            Text("VoxLab s'appuie sur des outils installés à part. Les chemins sont modifiables dans Réglages.")
                .foregroundStyle(.secondary)

            List(viewModel.reports) { report in
                DependencyRow(report: report)
            }
            .listStyle(.inset)
            .frame(minHeight: 260)
            .overlay {
                if viewModel.reports.isEmpty, viewModel.isChecking {
                    ProgressView("Vérification…")
                }
            }

            HStack {
                SettingsLink {
                    Text("Ouvrir les réglages…")
                }
                Spacer()
                if viewModel.isChecking, !viewModel.reports.isEmpty {
                    ProgressView().controlSize(.small)
                }
                Button("Revérifier") {
                    Task { await viewModel.refresh() }
                }
                .disabled(viewModel.isChecking)
                Button("Fermer") { dismiss() }
                    .keyboardShortcut(.defaultAction)
            }
        }
        .padding(20)
        .frame(width: 620)
    }
}

private struct DependencyRow: View {
    let report: DependencyReport

    var body: some View {
        HStack(alignment: .firstTextBaseline, spacing: 10) {
            Image(systemName: symbol)
                .foregroundStyle(color)
            VStack(alignment: .leading, spacing: 4) {
                HStack {
                    Text(report.dependency.displayName).bold()
                    if !report.dependency.isRequired {
                        Text("optionnel")
                            .font(.caption)
                            .foregroundStyle(.secondary)
                    }
                }
                Text(report.path)
                    .font(.caption.monospaced())
                    .foregroundStyle(.secondary)
                    .textSelection(.enabled)
                detail
            }
        }
        .padding(.vertical, 4)
    }

    @ViewBuilder
    private var detail: some View {
        switch report.state {
        case .available(let details):
            Text(details)
                .font(.caption)
                .lineLimit(1)
        case .missing:
            Text("Introuvable. Installation : `\(report.dependency.installHint)`")
                .font(.caption)
                .textSelection(.enabled)
        case .broken(let message):
            Text(message)
                .font(.caption)
                .foregroundStyle(.red)
                .lineLimit(4)
                .textSelection(.enabled)
        }
    }

    private var symbol: String {
        switch report.state {
        case .available: "checkmark.circle.fill"
        case .missing: report.dependency.isRequired ? "xmark.circle.fill" : "minus.circle"
        case .broken: "exclamationmark.triangle.fill"
        }
    }

    private var color: Color {
        switch report.state {
        case .available: .green
        case .missing: report.dependency.isRequired ? .red : .secondary
        case .broken: .orange
        }
    }
}
