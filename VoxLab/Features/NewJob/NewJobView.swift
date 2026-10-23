import SwiftUI
import UniformTypeIdentifiers

struct NewJobView: View {
    /// Appelé avec le job créé, pour le sélectionner dans l'historique.
    let onCreated: (Job) -> Void

    @Environment(JobController.self) private var controller
    @Environment(\.dismiss) private var dismiss
    @State private var fileURL: URL?
    @State private var targetLanguage = SupportedLanguage.fr
    @State private var isTargeted = false
    @State private var isPickingFile = false
    @State private var rejectionMessage: String?

    var body: some View {
        VStack(alignment: .leading, spacing: 16) {
            Text("Nouveau job")
                .font(.title2.bold())

            dropZone

            Picker("Langue cible", selection: $targetLanguage) {
                ForEach(SupportedLanguage.allCases) { language in
                    Text(language.displayName).tag(language)
                }
            }
            .frame(maxWidth: 280)

            HStack {
                Spacer()
                Button("Annuler", role: .cancel) { dismiss() }
                    .keyboardShortcut(.cancelAction)
                Button("Lancer") {
                    guard let fileURL else { return }
                    onCreated(controller.createJob(fileURL: fileURL, targetLanguage: targetLanguage))
                    dismiss()
                }
                .keyboardShortcut(.defaultAction)
                .disabled(fileURL == nil)
            }
        }
        .padding(20)
        .frame(width: 520)
        .fileImporter(isPresented: $isPickingFile, allowedContentTypes: [.audio]) { result in
            if case .success(let url) = result { accept(url) }
        }
    }

    private var dropZone: some View {
        VStack(spacing: 10) {
            Image(systemName: fileURL == nil ? "arrow.down.doc" : "music.note")
                .font(.system(size: 32))
                .foregroundStyle(.secondary)
            if let fileURL {
                Text(fileURL.lastPathComponent)
                    .font(.headline)
                    .lineLimit(1)
                    .truncationMode(.middle)
            } else {
                Text("Déposez un fichier audio ici")
                    .font(.headline)
            }
            Text(FileImporter.supportedExtensions.sorted().joined(separator: " · "))
                .font(.caption)
                .foregroundStyle(.secondary)
            Button(fileURL == nil ? "Choisir un fichier…" : "Changer…") { isPickingFile = true }
            if let rejectionMessage {
                Text(rejectionMessage)
                    .font(.caption)
                    .foregroundStyle(.red)
            }
        }
        .frame(maxWidth: .infinity, minHeight: 170)
        .background {
            RoundedRectangle(cornerRadius: 12)
                .strokeBorder(style: StrokeStyle(lineWidth: 2, dash: [6]))
                .foregroundStyle(isTargeted ? Color.accentColor : Color.secondary.opacity(0.4))
        }
        .dropDestination(for: URL.self) { urls, _ in
            guard let url = urls.first else { return false }
            return accept(url)
        } isTargeted: { isTargeted = $0 }
    }

    @discardableResult
    private func accept(_ url: URL) -> Bool {
        guard FileImporter.supportedExtensions.contains(url.pathExtension.lowercased()) else {
            rejectionMessage = "Format non pris en charge : .\(url.pathExtension)"
            return false
        }
        rejectionMessage = nil
        fileURL = url
        return true
    }
}
