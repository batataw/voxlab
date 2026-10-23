import AppKit
import SwiftUI

/// Onglets Brut / Corrigé / Traduit, éditables à la main.
struct TranscriptTabsView: View {
    let job: Job
    let isEditable: Bool

    @Environment(JobController.self) private var controller
    @State private var selection = TranscriptKind.raw
    @State private var draft = ""

    var body: some View {
        VStack(alignment: .leading, spacing: 8) {
            HStack {
                Picker("Texte", selection: $selection) {
                    ForEach(TranscriptKind.allCases) { kind in
                        Text(kind.displayName).tag(kind)
                    }
                }
                .pickerStyle(.segmented)
                .labelsHidden()
                .frame(maxWidth: 300)

                if selection == .translated, job.isTranslationStale {
                    Label("Obsolète", systemImage: "exclamationmark.triangle")
                        .font(.caption)
                        .foregroundStyle(.orange)
                        .help("Le texte corrigé a été modifié depuis la traduction.")
                }
                Spacer()
                Button("Copier", systemImage: "doc.on.doc") {
                    NSPasteboard.general.clearContents()
                    NSPasteboard.general.setString(draft, forType: .string)
                }
                .disabled(draft.isEmpty)
            }

            if job.text(selection) == nil {
                Text("Pas encore de texte : l'étape « \(selection.producingStep.displayName) » n'a pas été exécutée.")
                    .foregroundStyle(.secondary)
                    .frame(maxWidth: .infinity, minHeight: 120)
            } else {
                TextEditor(text: $draft)
                    .font(.body)
                    .frame(minHeight: 280)
                    .scrollContentBackground(.hidden)
                    .disabled(!isEditable)
            }
        }
        .onAppear { draft = job.text(selection) ?? "" }
        .onChange(of: selection) { draft = job.text(selection) ?? "" }
        .onChange(of: job.text(selection)) { _, newValue in
            // Texte produit par le pipeline pendant l'affichage.
            if let newValue, newValue != draft { draft = newValue }
        }
        .task(id: draft) {
            // Enregistre l'édition après une courte pause de frappe.
            guard isEditable, job.text(selection) != nil, draft != job.text(selection) else { return }
            try? await Task.sleep(for: .milliseconds(600))
            guard !Task.isCancelled else { return }
            controller.updateText(draft, kind: selection, of: job)
        }
    }
}
