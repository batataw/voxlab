import SwiftUI
@preconcurrency import Translation

/// Langue cible du job et, pour Apple Translation, état de la paire de langues
/// avec téléchargement via la demande système.
struct TargetLanguageView: View {
    let job: Job
    let isEditable: Bool

    @Environment(JobController.self) private var controller
    @State private var status: TranslationPairStatus?
    @State private var downloadConfiguration: TranslationSession.Configuration?
    @State private var downloadError: String?

    private var target: SupportedLanguage {
        SupportedLanguage(rawValue: job.targetLanguage) ?? .fr
    }

    var body: some View {
        HStack(spacing: 6) {
            Chip(text: detectedLabel, systemImage: "waveform")
            Image(systemName: "arrow.right")
                .font(.caption2)
                .foregroundStyle(.secondary)
            Menu {
                Picker("Langue cible", selection: Binding(
                    get: { target },
                    set: { controller.setTargetLanguage($0, of: job) }
                )) {
                    ForEach(SupportedLanguage.allCases) { language in
                        Text(language.displayName).tag(language)
                    }
                }
                .pickerStyle(.inline)
            } label: {
                Chip(text: target.displayName, systemImage: "globe", tint: .accentColor)
            }
            .menuStyle(.button)
            .buttonStyle(.plain)
            .menuIndicator(.hidden)
            .fixedSize()
            .disabled(!isEditable)
            .help("Changer la langue cible")

            pairStatus
            Spacer()
        }
        .task(id: "\(job.detectedLanguage ?? "")>\(job.targetLanguage)") { await refresh() }
        .translationTask(downloadConfiguration) { session in
            // Affiche la demande système de téléchargement des langues.
            do {
                try await session.prepareTranslation()
                downloadError = nil
            } catch {
                downloadError = error.localizedDescription
            }
            downloadConfiguration = nil
            await refresh()
        }
    }

    @ViewBuilder
    private var pairStatus: some View {
        if controller.translatesViaLLM {
            Chip(text: "Traduction via LLM", systemImage: "sparkles")
        } else if let source = job.detectedLanguage, source != job.targetLanguage {
            switch status {
            case .installed:
                Chip(text: "Langues installées", systemImage: "checkmark.circle.fill", tint: .green)
            case .downloadable:
                Button("Télécharger \(LanguageName.french(for: source)) → \(target.displayName.lowercased())", systemImage: "arrow.down.circle") {
                    downloadConfiguration = TranslationSession.Configuration(
                        source: Locale.Language(identifier: source),
                        target: Locale.Language(identifier: job.targetLanguage)
                    )
                }
                .controlSize(.small)
            case .unsupported:
                Chip(text: "Paire non prise en charge : activez « Traduire via LLM »", systemImage: "exclamationmark.triangle.fill", tint: .orange)
            case nil:
                EmptyView()
            }
            if let downloadError {
                Text(downloadError)
                    .font(.caption)
                    .foregroundStyle(.red)
            }
        }
    }

    private var detectedLabel: String {
        job.detectedLanguage.map { "\(LanguageName.french(for: $0).capitalized) détecté" } ?? "Langue à détecter"
    }

    private func refresh() async {
        guard let source = job.detectedLanguage, source != job.targetLanguage else {
            status = nil
            return
        }
        status = await AppleTranslator.status(from: source, to: job.targetLanguage)
    }
}
