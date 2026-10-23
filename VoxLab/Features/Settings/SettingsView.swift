import SwiftUI

struct SettingsView: View {
    @AppStorage(SettingsKey.ffmpegPath) private var ffmpegPath = ToolPaths.defaults.ffmpeg
    @AppStorage(SettingsKey.ytDlpPath) private var ytDlpPath = ToolPaths.defaults.ytDlp
    @AppStorage(SettingsKey.demucsPath) private var demucsPath = ToolPaths.defaults.demucs
    @AppStorage(SettingsKey.ollamaPath) private var ollamaPath = ToolPaths.defaults.ollama
    @AppStorage(SettingsKey.quality) private var quality = QualityMode.max

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
                Text("Rapide : htdemucs, large-v3-turbo, Foundation Models. Max : htdemucs_ft, large-v3, Ollama.")
                    .font(.caption)
                    .foregroundStyle(.secondary)
            }
            Section("Binaires externes") {
                TextField("ffmpeg", text: $ffmpegPath)
                TextField("yt-dlp", text: $ytDlpPath)
                TextField("Demucs", text: $demucsPath)
                TextField("Ollama (optionnel)", text: $ollamaPath)
            }
            Section {
                Button("Rétablir les valeurs par défaut") {
                    ffmpegPath = ToolPaths.defaults.ffmpeg
                    ytDlpPath = ToolPaths.defaults.ytDlp
                    demucsPath = ToolPaths.defaults.demucs
                    ollamaPath = ToolPaths.defaults.ollama
                }
            }
        }
        .formStyle(.grouped)
        .frame(width: 520)
        .fixedSize(horizontal: false, vertical: true)
    }
}

#Preview {
    SettingsView()
}
