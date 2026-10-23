import SwiftData
import SwiftUI

struct RootView: View {
    let diagnostics: DiagnosticsViewModel

    @State private var selectedJobID: PersistentIdentifier?
    @State private var isShowingDiagnostics = false

    var body: some View {
        NavigationSplitView {
            HistoryView(selection: $selectedJobID)
                .navigationSplitViewColumnWidth(min: 220, ideal: 260)
        } detail: {
            JobDetailContainer(jobID: selectedJobID)
        }
        .toolbar {
            ToolbarItem {
                Button {
                    isShowingDiagnostics = true
                } label: {
                    Label("Diagnostic", systemImage: diagnosticsSymbol)
                }
                .help("Diagnostic des dépendances externes")
            }
        }
        .sheet(isPresented: $isShowingDiagnostics) {
            DiagnosticsView(viewModel: diagnostics)
        }
        .task {
            await diagnostics.refresh()
            if !diagnostics.missingRequired.isEmpty {
                isShowingDiagnostics = true
            }
        }
        .onReceive(NotificationCenter.default.publisher(for: .showDiagnostics)) { _ in
            isShowingDiagnostics = true
        }
    }

    private var diagnosticsSymbol: String {
        guard diagnostics.hasCheckedOnce else { return "stethoscope" }
        return diagnostics.missingRequired.isEmpty ? "stethoscope" : "exclamationmark.triangle"
    }
}

/// Résout l'identifiant sélectionné en `Job` dans le contexte courant.
private struct JobDetailContainer: View {
    let jobID: PersistentIdentifier?
    @Environment(\.modelContext) private var modelContext

    var body: some View {
        if let jobID, let job = modelContext.model(for: jobID) as? Job {
            JobDetailView(job: job)
        } else {
            ContentUnavailableView(
                "Aucun job sélectionné",
                systemImage: "waveform",
                description: Text("Choisissez un job dans l'historique.")
            )
        }
    }
}
