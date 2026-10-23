import SwiftUI
import UniformTypeIdentifiers

/// Création d'un job : fichier déposé ou URL YouTube, langue cible, lancement.
struct NewJobPage: View {
    let navigation: AppNavigation

    @Environment(JobController.self) private var controller
    @AppStorage(SettingsKey.quality) private var quality = QualityMode.max
    @State private var fileURL: URL?
    @State private var urlText = ""
    @State private var targetLanguage = SupportedLanguage.fr
    @State private var isTargeted = false
    @State private var isPickingFile = false
    @State private var rejectionMessage: String?

    private var youtubeURL: URL? { YouTubeURL.parse(urlText) }
    private var canLaunch: Bool { fileURL != nil || youtubeURL != nil }

    var body: some View {
        Page {
            PageHeader(title: "Nouveau", subtitle: "Un fichier audio ou une vidéo YouTube, isolée, transcrite, corrigée puis traduite.")
                .padding(.bottom, 4)

            Card {
                dropZone
            }

            Card {
                HStack(spacing: 12) {
                    RoundIcon(systemImage: "play.rectangle.fill", tint: .red)
                    VStack(alignment: .leading, spacing: 6) {
                        Text("Vidéo YouTube").font(.headline)
                        TextField("https://www.youtube.com/watch?v=…", text: $urlText)
                            .textFieldStyle(.roundedBorder)
                            .onChange(of: urlText) {
                                if !urlText.isEmpty { fileURL = nil }
                            }
                        if !urlText.isEmpty, youtubeURL == nil {
                            Text("URL YouTube non reconnue (youtube.com ou youtu.be).")
                                .font(.caption)
                                .foregroundStyle(.red)
                        }
                    }
                }
            }

            Card {
                HStack(spacing: 12) {
                    RoundIcon(systemImage: "globe", tint: .indigo)
                    Text("Traduire en").font(.headline)
                    Picker("Langue cible", selection: $targetLanguage) {
                        ForEach(SupportedLanguage.allCases) { language in
                            Text(language.displayName).tag(language)
                        }
                    }
                    .labelsHidden()
                    .fixedSize()
                    Spacer()
                }
            } footer: {
                HStack(spacing: 6) {
                    Chip(text: "Qualité \(quality.displayName)", systemImage: "bolt.fill")
                    Chip(text: quality == .max ? "htdemucs_ft · large-v3 · serveur local" : "htdemucs · large-v3-turbo · Foundation Models", systemImage: "cpu")
                }
            }

            Button {
                launch()
            } label: {
                Label("Lancer", systemImage: "play.fill")
                    .font(.headline)
                    .frame(maxWidth: .infinity)
                    .padding(.vertical, 6)
            }
            .buttonStyle(.borderedProminent)
            .controlSize(.large)
            .keyboardShortcut(.defaultAction)
            .disabled(!canLaunch)
        }
        .fileImporter(isPresented: $isPickingFile, allowedContentTypes: [.audio]) { result in
            if case .success(let url) = result { accept(url) }
        }
    }

    private var dropZone: some View {
        VStack(spacing: 10) {
            RoundIcon(systemImage: fileURL == nil ? "arrow.down.doc" : "music.note", tint: .orange, size: 48)
            if let fileURL {
                Text(fileURL.lastPathComponent)
                    .font(.headline)
                    .lineLimit(1)
                    .truncationMode(.middle)
            } else {
                Text("Déposez un fichier audio ici").font(.headline)
            }
            HStack(spacing: 6) {
                ForEach(FileImporter.supportedExtensions.sorted(), id: \.self) { Chip(text: $0) }
            }
            Button(fileURL == nil ? "Choisir un fichier…" : "Changer…") { isPickingFile = true }
            if let rejectionMessage {
                Text(rejectionMessage)
                    .font(.caption)
                    .foregroundStyle(.red)
            }
        }
        .frame(maxWidth: .infinity, minHeight: 180)
        .background {
            RoundedRectangle(cornerRadius: 10)
                .strokeBorder(style: StrokeStyle(lineWidth: 1.5, dash: [6]))
                .foregroundStyle(isTargeted ? Color.accentColor : Color.secondary.opacity(0.35))
        }
        .dropDestination(for: URL.self) { urls, _ in
            guard let url = urls.first else { return false }
            return accept(url)
        } isTargeted: { isTargeted = $0 }
    }

    private func launch() {
        let job: Job
        if let fileURL {
            job = controller.createJob(fileURL: fileURL, targetLanguage: targetLanguage)
        } else if let youtubeURL {
            job = controller.createJob(youtubeURL: youtubeURL, targetLanguage: targetLanguage)
        } else {
            return
        }
        fileURL = nil
        urlText = ""
        navigation.showJob(job.id)
    }

    @discardableResult
    private func accept(_ url: URL) -> Bool {
        guard FileImporter.supportedExtensions.contains(url.pathExtension.lowercased()) else {
            rejectionMessage = "Format non pris en charge : .\(url.pathExtension)"
            return false
        }
        rejectionMessage = nil
        urlText = ""
        fileURL = url
        return true
    }
}
