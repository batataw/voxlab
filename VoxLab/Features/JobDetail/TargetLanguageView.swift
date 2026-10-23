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
        HStack(spacing: 12) {
            Picker("Langue cible", selection: Binding(
                get: { target },
                set: { controller.setTargetLanguage($0, of: job) }
            )) {
                ForEach(SupportedLanguage.allCases) { language in
                    Text(language.displayName).tag(language)
                }
            }
            .fixedSize()
            .disabled(!isEditable)

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
            Label("Traduction via LLM", systemImage: "sparkles")
                .font(.caption)
                .foregroundStyle(.secondary)
        } else if let source = job.detectedLanguage, source != job.targetLanguage {
            switch status {
            case .installed:
                Label("Langues installées", systemImage: "checkmark.circle")
                    .font(.caption)
                    .foregroundStyle(.green)
            case .downloadable:
                Button("Télécharger \(LanguageName.french(for: source)) → \(target.displayName.lowercased())", systemImage: "arrow.down.circle") {
                    downloadConfiguration = TranslationSession.Configuration(
                        source: Locale.Language(identifier: source),
                        target: Locale.Language(identifier: job.targetLanguage)
                    )
                }
                .controlSize(.small)
            case .unsupported:
                Label("Paire non prise en charge par Apple : activez « Traduire via LLM »", systemImage: "exclamationmark.triangle")
                    .font(.caption)
                    .foregroundStyle(.orange)
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

    private func refresh() async {
        guard let source = job.detectedLanguage, source != job.targetLanguage else {
            status = nil
            return
        }
        status = await AppleTranslator.status(from: source, to: job.targetLanguage)
    }
}
