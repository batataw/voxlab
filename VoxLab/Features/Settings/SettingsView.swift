import SwiftUI

struct SettingsView: View {
    @AppStorage(SettingsKey.ffmpegPath) private var ffmpegPath = ToolPaths.defaults.ffmpeg
    @AppStorage(SettingsKey.ytDlpPath) private var ytDlpPath = ToolPaths.defaults.ytDlp
    @AppStorage(SettingsKey.demucsPath) private var demucsPath = ToolPaths.defaults.demucs
    @AppStorage(SettingsKey.quality) private var quality = QualityMode.max
    @AppStorage(SettingsKey.llmProvider) private var provider = LLMProviderChoice.automatic
    @AppStorage(SettingsKey.llmServerURL) private var serverURL = LLMServerSettings.defaults.baseURL
    @AppStorage(SettingsKey.llmServerModel) private var serverModel = LLMServerSettings.defaults.model

    @State private var viewModel = SettingsViewModel()

    var body: some View {
        Form {
            Section {
                Picker("Qualité", selection: $quality) {
                    ForEach(QualityMode.allCases, id: \.self) { mode in
                        Text(mode.displayName).tag(mode)
                    }
                }
                .pickerStyle(.segmented)
            } footer: {
                Text("Rapide : htdemucs, large-v3-turbo, Foundation Models. Max : htdemucs_ft, large-v3, serveur local.")
                    .font(.caption)
                    .foregroundStyle(.secondary)
            }

            Section("Correction") {
                Picker("Provider", selection: $provider) {
                    ForEach(LLMProviderChoice.allCases, id: \.self) { choice in
                        Text(choice.displayName).tag(choice)
                    }
                }
                TextField("URL du serveur", text: $serverURL)
                HStack {
                    TextField("Modèle", text: $serverModel)
                    Menu("Choisir") {
                        ForEach(viewModel.availableModels, id: \.self) { model in
                            Button(model) { serverModel = model }
                        }
                    }
                    .disabled(viewModel.availableModels.isEmpty)
                    .fixedSize()
                }
                if let error = viewModel.serverError {
                    Text(error)
                        .font(.caption)
                        .foregroundStyle(.orange)
                } else if !viewModel.availableModels.isEmpty, !viewModel.availableModels.contains(serverModel) {
                    Text("Ce modèle n'est pas proposé par le serveur.")
                        .font(.caption)
                        .foregroundStyle(.orange)
                }
            }

            Section("Binaires externes") {
                TextField("ffmpeg", text: $ffmpegPath)
                TextField("yt-dlp", text: $ytDlpPath)
                TextField("Demucs", text: $demucsPath)
            }

            Section {
                Button("Rétablir les valeurs par défaut") {
                    ffmpegPath = ToolPaths.defaults.ffmpeg
                    ytDlpPath = ToolPaths.defaults.ytDlp
                    demucsPath = ToolPaths.defaults.demucs
                    serverURL = LLMServerSettings.defaults.baseURL
                    serverModel = LLMServerSettings.defaults.model
                    provider = .automatic
                }
            }
        }
        .formStyle(.grouped)
        .frame(width: 560)
        .fixedSize(horizontal: false, vertical: true)
        .task(id: serverURL) {
            // Laisse finir la saisie de l'URL avant d'interroger le serveur.
            try? await Task.sleep(for: .milliseconds(400))
            guard !Task.isCancelled else { return }
            await viewModel.refreshModels(baseURL: serverURL)
        }
    }
}

#Preview {
    SettingsView()
}
