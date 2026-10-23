import Foundation

/// Extrait une progression (0…1) des sorties des outils en ligne de commande.
nonisolated enum ProgressParser: Sendable {
    /// Barre tqdm de Demucs : ` 45%|████▌     | 52.6/117.0 [00:10<00:12, …]`.
    case demucs
    /// yt-dlp : `[download]  42.3% of   3.52MiB at  1.20MiB/s ETA 00:01`.
    case ytDlp
    /// ffmpeg lancé avec `-progress pipe:1` : `out_time_us=12345678`, rapporté à la durée totale.
    case ffmpeg(totalSeconds: Double)

    func progress(in line: String) -> Double? {
        switch self {
        case .demucs:
            Self.percentage(in: line, pattern: /(\d{1,3})%\|/)
        case .ytDlp:
            Self.percentage(in: line, pattern: /\[download\]\s+(\d{1,3}(?:\.\d+)?)%/)
        case .ffmpeg(let totalSeconds):
            Self.ffmpegProgress(in: line, totalSeconds: totalSeconds)
        }
    }

    private static func ffmpegProgress(in line: String, totalSeconds: Double) -> Double? {
        guard totalSeconds > 0,
              let match = line.firstMatch(of: /^out_time_us=(\d+)$/),
              let microseconds = Double(match.1)
        else { return nil }
        return min(max(microseconds / 1_000_000 / totalSeconds, 0), 1)
    }

    private static func percentage(in line: String, pattern: Regex<(Substring, Substring)>) -> Double? {
        guard let match = line.firstMatch(of: pattern), let value = Double(match.1) else {
            return nil
        }
        return min(max(value / 100, 0), 1)
    }
}
