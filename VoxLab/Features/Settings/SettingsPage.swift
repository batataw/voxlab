import SwiftUI

/// Réglages de l'app, en cartes.
struct SettingsPage: View {
    @AppStorage(SettingsKey.ffmpegPath) private var ffmpegPath = ToolPaths.defaults.ffmpeg
    @AppStorage(SettingsKey.ytDlpPath) private var ytDlpPath = ToolPaths.defaults.ytDlp
    @AppStorage(SettingsKey.demucsPath) private var demucsPath = ToolPaths.defaults.demucs
    @AppStorage(SettingsKey.quality) private var quality = QualityMode.max
    @AppStorage(SettingsKey.llmProvider) private var provider = LLMProviderChoice.automatic
    @AppStorage(SettingsKey.llmServerURL) private var serverURL = LLMServerSettings.defaults.baseURL
    @AppStorage(SettingsKey.llmServerModel) private var serverModel = LLMServerSettings.defaults.model
    @AppStorage(SettingsKey.translateViaLLM) private var translateViaLLM = false

    @State private var viewModel = SettingsViewModel()

    var body: some View {
        Page {
            PageHeader(title: "Réglages") {
                RoundIconButton(title: "Rétablir les valeurs par défaut", systemImage: "arrow.uturn.backward") { resetDefaults() }
            }

            SettingCard(title: "Qualité", systemImage: "bolt.fill", color: .orange) {
                Picker("Qualité", selection: $quality) {
                    ForEach(QualityMode.allCases, id: \.self) { mode in
                        Text(mode.displayName).tag(mode)
                    }
                }
                .pickerStyle(.segmented)
                .labelsHidden()
                .fixedSize()
            } footer: {
                HStack(spacing: 6) {
                    Chip(text: quality == .max ? "htdemucs_ft" : "htdemucs", systemImage: "waveform.path")
                    Chip(text: quality == .max ? "large-v3" : "large-v3-turbo", systemImage: "text.bubble")
                    Chip(text: provider.resolved(for: quality) == .localServer ? "Serveur local" : "Foundation Models", systemImage: "cpu")
                    Text("S'applique aux nouveaux jobs.")
                        .font(.caption)
                        .foregroundStyle(.secondary)
                }
            }

            SettingCard(title: "Correction", systemImage: "text.badge.checkmark", color: .teal) {
                Picker("Provider", selection: $provider) {
                    ForEach(LLMProviderChoice.allCases, id: \.self) { choice in
                        Text(choice.displayName).tag(choice)
                    }
                }
                .labelsHidden()
                .fixedSize()
            } footer: {
                VStack(alignment: .leading, spacing: 8) {
                    LabeledField(label: "URL du serveur") {
                        TextField("http://localhost:1234/v1", text: $serverURL)
                            .textFieldStyle(.roundedBorder)
                    }
                    LabeledField(label: "Modèle") {
                        HStack {
                            TextField("Modèle", text: $serverModel)
                                .textFieldStyle(.roundedBorder)
                            Menu("Choisir") {
                                ForEach(viewModel.availableModels, id: \.self) { model in
                                    Button(model) { serverModel = model }
                                }
                            }
                            .disabled(viewModel.availableModels.isEmpty)
                            .fixedSize()
                        }
                    }
                    if let error = viewModel.serverError {
                        Chip(text: error, systemImage: "exclamationmark.triangle.fill", tint: .orange)
                    } else if !viewModel.availableModels.isEmpty {
                        Chip(
                            text: viewModel.availableModels.contains(serverModel) ? "Modèle disponible sur le serveur" : "Modèle absent du serveur",
                            systemImage: viewModel.availableModels.contains(serverModel) ? "checkmark.circle.fill" : "exclamationmark.triangle.fill",
                            tint: viewModel.availableModels.contains(serverModel) ? .green : .orange
                        )
                    }
                }
            }

            SettingCard(title: "Traduire via LLM", systemImage: "globe", color: .indigo) {
                Toggle("Traduire via LLM", isOn: $translateViaLLM)
                    .toggleStyle(.switch)
                    .labelsHidden()
            } footer: {
                Text("Plus fidèle au registre familier et à l'argot qu'Apple Translation, mais plus lent. Utilise le provider de la correction.")
                    .font(.caption)
                    .foregroundStyle(.secondary)
            }

            SettingCard(title: "Binaires externes", systemImage: "terminal.fill", color: .gray) {
                EmptyView()
            } footer: {
                VStack(alignment: .leading, spacing: 8) {
                    LabeledField(label: "ffmpeg") { TextField("ffmpeg", text: $ffmpegPath).textFieldStyle(.roundedBorder) }
                    LabeledField(label: "yt-dlp") { TextField("yt-dlp", text: $ytDlpPath).textFieldStyle(.roundedBorder) }
                    LabeledField(label: "Demucs") { TextField("Demucs", text: $demucsPath).textFieldStyle(.roundedBorder) }
                }
            }
        }
        .task(id: serverURL) {
            // Laisse finir la saisie de l'URL avant d'interroger le serveur.
            try? await Task.sleep(for: .milliseconds(400))
            guard !Task.isCancelled else { return }
            await viewModel.refreshModels(baseURL: serverURL)
        }
    }

    private func resetDefaults() {
        ffmpegPath = ToolPaths.defaults.ffmpeg
        ytDlpPath = ToolPaths.defaults.ytDlp
        demucsPath = ToolPaths.defaults.demucs
        serverURL = LLMServerSettings.defaults.baseURL
        serverModel = LLMServerSettings.defaults.model
        provider = .automatic
        translateViaLLM = false
        quality = .max
    }
}

/// Carte de réglage : pastille, titre, contrôle à droite, détails dans la bande.
private struct SettingCard<Control: View, Footer: View>: View {
    let title: String
    let systemImage: String
    let color: Color
    @ViewBuilder let control: Control
    @ViewBuilder let footer: Footer

    var body: some View {
        Card {
            HStack(spacing: 12) {
                RoundIcon(systemImage: systemImage, tint: color)
                Text(title).font(.headline)
                Spacer()
                control
            }
        } footer: {
            footer
        }
    }
}

private struct LabeledField<Field: View>: View {
    let label: String
    @ViewBuilder let field: Field

    var body: some View {
        HStack {
            Text(label)
                .font(.callout)
                .foregroundStyle(.secondary)
                .frame(width: 110, alignment: .leading)
            field
        }
    }
}
