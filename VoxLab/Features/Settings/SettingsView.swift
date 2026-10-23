import SwiftUI

struct SettingsView: View {
    @AppStorage(SettingsKey.ffmpegPath) private var ffmpegPath = ToolPaths.defaults.ffmpeg
    @AppStorage(SettingsKey.ytDlpPath) private var ytDlpPath = ToolPaths.defaults.ytDlp
    @AppStorage(SettingsKey.demucsPath) private var demucsPath = ToolPaths.defaults.demucs
    @AppStorage(SettingsKey.ollamaPath) private var ollamaPath = ToolPaths.defaults.ollama

    var body: some View {
        Form {
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
